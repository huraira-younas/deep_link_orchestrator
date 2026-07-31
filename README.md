# deep_link_orchestrator

A modular, type-safe deep link orchestration package for Flutter. Handles validation, deduplication, authentication gating, and dispatching with pluggable sources, policies, and handlers.

Built on top of [`app_links`](https://pub.dev/packages/app_links) with zero additional runtime dependencies.

## Features

- **Handler-based dispatching** -- each handler declares what it can handle and whether it requires authentication.
- **Typed intents** -- define concrete `DeepLinkIntent` subclasses with parsed fields; handlers match via `intent is ProfileIntent`.
- **Debounce & deduplication** -- prevents duplicate link processing from rapid-fire or replayed intents.
- **Authentication gating** -- automatically saves pending links when the user isn't authenticated and replays them after login.
- **Validation** -- reject links with unsupported schemes, hosts, or paths before they reach your handlers.
- **Pluggable architecture** -- swap out any component (source, validator, auth policy, pending store, logger) with your own implementation.
- **Cold & warm start** -- handles both the initial app launch link and links received while the app is running.

## Installation

```yaml
dependencies:
  deep_link_orchestrator: ^1.0.0
```

```bash
flutter pub get
```

## Quick start

### 1. Define your intents

Extend `DeepLinkIntent` with concrete types that carry parsed data:

```dart
import 'package:deep_link_orchestrator/deep_link_orchestrator.dart';

class ProfileIntent extends DeepLinkIntent {
  const ProfileIntent({
    required this.userId,
    required super.sourceId,
    required super.uri,
  });

  final String userId;
}

class InviteIntent extends DeepLinkIntent {
  const InviteIntent({
    required this.inviteCode,
    required super.sourceId,
    required super.uri,
  });

  final String inviteCode;
}
```

### 2. Create an intent resolver

The resolver converts raw intents from sources into your concrete types:

```dart
DeepLinkIntent resolveIntent(DeepLinkIntent intent) {
  final segments = intent.uri.pathSegments;
  final params = intent.uri.queryParameters;

  if (segments.firstOrNull == 'profile' && segments.length > 1) {
    return ProfileIntent(
      userId: segments[1],
      sourceId: intent.sourceId,
      uri: intent.uri,
    );
  }

  if (segments.firstOrNull == 'invite' && params.containsKey('code')) {
    return InviteIntent(
      inviteCode: params['code']!,
      sourceId: intent.sourceId,
      uri: intent.uri,
    );
  }

  return intent;
}
```

### 3. Create handlers

Extend `TypedDeepLinkHandler<T>` and you get the type check and the cast for free:

```dart
class ProfileHandler extends TypedDeepLinkHandler<ProfileIntent> {
  @override
  Future<void> onHandle(ProfileIntent intent, DeepLinkHandlerContext context) =>
      router.push('/profile/${intent.userId}');
}

class InviteHandler extends TypedDeepLinkHandler<InviteIntent> {
  /// Deferred to the pending store until the user signs in.
  @override
  bool get requiresAuthentication => true;

  @override
  Future<void> onHandle(InviteIntent intent, DeepLinkHandlerContext context) =>
      InviteService.accept(intent.inviteCode);
}
```

Implement the lower-level `DeepLinkHandler` directly only when a handler needs
to reject some intents of its own type, which is what `canHandle` is for.

### 4. Wire it up

```dart
final orchestrator = DeepLinkOrchestrator(
  sources: [AppLinksDeepLinkSource()],
  intentResolver: resolveIntent,
  validationPolicy: DeepLinkValidator(
    supportedPaths: ['/profile', '/invite'],
    expectedHost: 'example.com',
    customScheme: 'myapp',
  ),
);

orchestrator.dispatcher.registerHandlers({
  ProfileIntent: ProfileHandler(...),
  InviteIntent: InviteHandler(...),
});

await orchestrator.initialize();
await orchestrator.checkInitialIntent();

// Dispose when done
await orchestrator.dispose();
```

`checkInitialIntent()` consumes the cold-start URI once per process. Platform channels keep returning the launch URI for the lifetime of the process, so calling it again later replays only the pending store, never the original link. That makes it safe to call from a widget that remounts, such as a shell rebuilt after a role or session change. Use `resetInitialIntent()` in the rare case where replaying the launch link is actually what you want.

## Architecture

```
┌─────────────────┐
│  DeepLinkSource  │  (AppLinksDeepLinkSource, or your own)
└────────┬────────┘
         │ RawDeepLinkIntent
         ▼
┌─────────────────────────┐
│  DeepLinkOrchestrator   │  debounce → dedup → validate → resolve → dispatch
└────────┬────────────────┘
         │ ProfileIntent / InviteIntent / ...
         ▼
┌─────────────────────┐
│  DeepLinkDispatcher  │  find matching handler → auth gate → handle
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  DeepLinkHandler     │  your application logic
└─────────────────────┘
```

### Processing pipeline

1. **Source** receives a raw URI and wraps it in a `RawDeepLinkIntent`.
2. **Orchestrator** debounces rapid-fire intents, then checks deduplication.
3. **Validation policy** rejects links with unsupported schemes/hosts/paths.
4. **Intent resolver** (optional) converts the raw intent into a concrete subclass with parsed fields.
5. **Dispatcher** looks up the handler by `intent.runtimeType` in its map, then confirms `canHandle`. If that handler has `requiresAuthentication == true` and the user isn't authenticated, the link is saved to the **pending store** for later replay. Otherwise, the handler processes the intent.

Debouncing is keyed on `dedupeKey`, so a burst of callbacks for one link collapses without discarding a different link that arrives in the same window. Links are then processed one at a time in arrival order: a slow handler delays the links behind it but never causes one to be dropped. `handleIntent` returns a future that completes once the intent has actually been processed, which makes the pipeline straightforward to drive from a test.

## Configuration

### Validation

Use `DeepLinkValidator` or implement `DeepLinkValidationPolicy`:

```dart
DeepLinkValidator(
  supportedPaths: ['/profile', '/settings'],
  expectedHost: 'example.com',
  customScheme: 'myapp',
)
```

This accepts `myapp://` (any host), `https://example.com/...`, and `https://www.example.com/...`.

Every rule is a constructor argument, so widening the validator does not require subclassing it:

| Argument | Effect |
|----------|--------|
| `supportedPaths` | Path prefixes to accept. Empty accepts every non-root path. |
| `allowedSubdomains` | Labels prefixed to `expectedHost`. Defaults to `['www']`; add `'share'` to accept `share.example.com`. |
| `additionalHosts` | Unrelated hosts to accept, for staging domains or link shorteners. |
| `allowRootPath` | Accepts `/` and the empty path, rejected by default as carrying no destination. |

If a rule genuinely cannot be expressed as configuration, override the `@protected` `isSupportedHost` or `isSupportedPath` rather than `failureReason`, so the error messages stay consistent.

### Authentication gating

Implement `DeepLinkAuthenticationPolicy` to let the orchestrator know when the user is signed in:

```dart
class MyAuthPolicy implements DeepLinkAuthenticationPolicy {
  @override
  bool get isAuthenticated => AuthService.instance.isLoggedIn;
}
```

When a handler has `requiresAuthentication == true` and the user isn't authenticated, the link URI is saved to the pending store. After login, call `orchestrator.checkInitialIntent()` to replay it.

Deferral is the *only* thing that writes to the pending store. If a link is rejected by validation, has no registered handler, or its handler throws, the stored URI is dropped instead of kept, so a link that fails to open is never replayed later.

### Deduplication

Intents are identified by `DeepLinkIntent.dedupeKey`, which defaults to `sourceId:uri`. Override that getter on your intent type to change what counts as the same link, for example to ignore a tracking query parameter.

The default `TimeWindowDeepLinkDeduplicationStrategy` collapses identical intents that arrive within one second and handles the URI again once the window expires. That absorbs platform double-fires without blocking a link the user opens again later.

| Scenario | Behavior |
|----------|----------|
| Same URI arrives 50 ms after the last one | Collapsed, handler runs once |
| Same URI arrives 5 s after the last one | Treated as a new open, handler runs again |

```dart
DeepLinkOrchestrator(
  sources: [AppLinksDeepLinkSource()],
  deduplicationStrategy: TimeWindowDeepLinkDeduplicationStrategy(
    windowDuration: const Duration(milliseconds: 800),
  ),
)
```

The alternatives are `DefaultDeepLinkDeduplicationStrategy`, which suppresses a URI for the whole session until you call `resetDeduplication()`, and `NoopDeepLinkDeduplicationStrategy`, which processes everything.

A link only counts as seen once it has been handled. If validation rejects it, no handler claims it, or the handler throws, the strategy is asked to forget it so the next attempt is not silently swallowed.

Implement `DeepLinkDeduplicationStrategy` for fully custom logic. The strategy owns its bookkeeping, so it is free to remember one intent, many, or none:

```dart
class OncePerLaunchStrategy implements DeepLinkDeduplicationStrategy {
  final Set<String> _seen = {};

  @override
  bool shouldProcess(DeepLinkIntent intent) => _seen.add(intent.dedupeKey);

  @override
  void forget(DeepLinkIntent intent) => _seen.remove(intent.dedupeKey);

  @override
  void reset() => _seen.clear();
}
```

### Pending store

The package ships with `NoopDeepLinkPendingStore` (default) and `InMemoryDeepLinkPendingStore`. For persistence across app restarts, implement `DeepLinkPendingStore` with your own storage:

```dart
class SharedPrefsPendingStore implements DeepLinkPendingStore {
  @override
  Future<void> savePending(Uri uri) async { /* ... */ }

  @override
  Future<void> clearPending() async { /* ... */ }

  @override
  Uri? readPending() { /* ... */ }
}
```

### Dispatcher

`DeepLinkOrchestrator` creates a `DeepLinkDispatcher` by default. You can supply your own with an optional named `handlers` map (`Type` → `DeepLinkHandler`), or register handlers later via `registerHandler` / `registerHandlers`:

```dart
DeepLinkOrchestrator(
  sources: [AppLinksDeepLinkSource()],
  dispatcher: DeepLinkDispatcher(
    handlers: {
      ProfileIntent: ProfileHandler(...),
      InviteIntent: InviteHandler(...),
    },
  ),
);
```

To call the dispatcher yourself (e.g. in tests), use named arguments on `dispatch`. It returns a `DeepLinkDispatchResult` rather than throwing for routine outcomes:

```dart
final result = await dispatcher.dispatch(
  context: DeepLinkHandlerContext(
    pendingStore: pendingStore,
    authPolicy: authPolicy,
    sharedData: const {},
  ),
  intent: resolvedIntent,
);

switch (result) {
  case DeepLinkDispatchResult.handled:
  case DeepLinkDispatchResult.noHandler:   // nothing registered, treated as a no-op
  case DeepLinkDispatchResult.authDeferred: // saved for replay after login
  case DeepLinkDispatchResult.failed:
}
```

Only exceptions thrown by your `handle` implementation propagate; the orchestrator catches those and reports `failed`.

### Logging

Inject any `DeepLinkLogger`. The default `DeveloperDeepLinkLogger` writes to `dart:developer`'s `log()`. Use `NoopDeepLinkLogger` to silence output, or implement your own.

### Custom sources

Implement `DeepLinkSource` to receive links from other channels (push notifications, attribution SDKs, etc.):

```dart
class NotificationDeepLinkSource implements DeepLinkSource {
  @override
  String get id => 'notification';

  @override
  Future<void> initialize(DeepLinkIntentSink onIntent) async {
    // Listen to your notification stream and call onIntent(...)
  }

  @override
  Future<DeepLinkIntent?> getInitialIntent() async => null;

  @override
  Future<void> dispose() async {}
}
```

Then pass it alongside `AppLinksDeepLinkSource`:

```dart
DeepLinkOrchestrator(
  sources: [AppLinksDeepLinkSource(), NotificationDeepLinkSource()],
);
```

## API overview

| Class | Role |
|---|---|
| `DeepLinkOrchestrator` | Top-level entry point; wires sources, policies, resolver, and dispatcher. |
| `DeepLinkIntent` | Abstract base for all intents; extend it with parsed fields. |
| `RawDeepLinkIntent` | Concrete intent created by sources before resolution. |
| `TypedDeepLinkHandler<T>` | Handler bound to one intent type; implement `onHandle(T intent, context)` and nothing else. |
| `DeepLinkHandler` | Lower-level handler with `canHandle`, `requiresAuthentication`, and `handle(context:, intent:)`. |
| `DeepLinkDispatcher` | Registers handlers in a `Map<Type, DeepLinkHandler>` for O(1) dispatch by `intent.runtimeType`; constructor `handlers:`, methods `registerHandler`, `registerHandlers`, `dispatch(context:, intent:)`. |
| `DeepLinkDispatchResult` | Outcome of a dispatch: `handled`, `noHandler`, `authDeferred`, or `failed`. |
| `DeepLinkValidator` | Built-in scheme/host/path validation. |
| `AppLinksDeepLinkSource` | `app_links` v7 integration (cold + warm start). |
| `DeepLinkLogger` | Logging interface with `DeveloperDeepLinkLogger` and `NoopDeepLinkLogger`. |

### Policy interfaces

| Interface | Purpose | Default |
|---|---|---|
| `DeepLinkValidationPolicy` | Accept or reject URIs | `AllowAllDeepLinkValidationPolicy` |
| `DeepLinkAuthenticationPolicy` | Report auth state | `AlwaysAuthenticatedPolicy` |
| `DeepLinkDeduplicationStrategy` | Decide whether an intent is a duplicate; built-ins: `TimeWindowDeepLinkDeduplicationStrategy` (time-bounded), `DefaultDeepLinkDeduplicationStrategy` (whole session), `NoopDeepLinkDeduplicationStrategy` (never) | `TimeWindowDeepLinkDeduplicationStrategy` (1 s) |
| `DeepLinkPendingStore` | Persist/replay pending links | `NoopDeepLinkPendingStore` |

## Platform setup

This package uses [`app_links`](https://pub.dev/packages/app_links) under the hood. Follow the platform-specific setup instructions in the [app_links documentation](https://pub.dev/packages/app_links):

- **Android**: Add `intent-filter` entries in `AndroidManifest.xml` and host an `assetlinks.json` file.
- **iOS**: Enable Associated Domains in Xcode and host an `apple-app-site-association` file.
- **Desktop / Web**: See the app_links README for platform-specific configuration.

## License

MIT -- see [LICENSE](LICENSE).
