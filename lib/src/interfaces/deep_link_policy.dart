import '../deep_link_intent.dart';

// ---------------------------------------------------------------------------
// Abstract policies
// ---------------------------------------------------------------------------

/// Determines whether a URI is acceptable for processing.
///
/// Implement this interface to enforce app-specific rules such as allowed
/// schemes, hosts, or path patterns. Return a non-null failure reason
/// string to reject the link, or `null` to allow it through.
///
/// See also:
/// - [AllowAllDeepLinkValidationPolicy] — a no-op implementation.
/// - [DeepLinkValidator] in `deep_link_validator.dart` — a ready-made
///   scheme/host/path validator.
abstract interface class DeepLinkValidationPolicy {
  /// Returns a human-readable reason if [uri] should be rejected, or `null`
  /// if the URI is valid.
  String? failureReason(Uri uri);
}

/// Indicates whether the current user session is authenticated.
///
/// The [DeepLinkDispatcher] queries this policy before invoking any handler
/// whose [DeepLinkHandler.requiresAuthentication] flag is `true`. If the
/// user is not authenticated the intent is persisted via
/// [DeepLinkPendingStore] and replayed after login.
///
/// See also:
/// - [AlwaysAuthenticatedPolicy] — a no-op implementation for apps without
///   authentication.
abstract interface class DeepLinkAuthenticationPolicy {
  /// Whether the user is currently authenticated.
  bool get isAuthenticated;
}

/// Decides whether an incoming [DeepLinkIntent] is a duplicate.
///
/// The strategy owns its own bookkeeping, so implementations are free to
/// remember one intent, many, or none at all. [DeepLinkOrchestrator] calls
/// [shouldProcess] once per intent and calls [forget] again if processing did
/// not complete, so a transient failure never permanently blocks a link.
///
/// Intents are identified by [DeepLinkIntent.dedupeKey]; override that getter
/// on your intent type to change what counts as the same link.
///
/// See also:
/// - [DefaultDeepLinkDeduplicationStrategy] for suppressing a URI for the
///   lifetime of the session.
/// - [TimeWindowDeepLinkDeduplicationStrategy] for suppressing a URI only
///   within a rolling window.
abstract interface class DeepLinkDeduplicationStrategy {
  /// Whether [intent] should be processed, recording it as seen when `true`.
  bool shouldProcess(DeepLinkIntent intent);

  /// Drops any record of [intent] so it can be processed again.
  void forget(DeepLinkIntent intent);

  /// Drops every recorded intent.
  void reset();
}

/// Persists a pending [Uri] so it can be replayed after authentication.
///
/// When a handler requires authentication but the user is not yet logged in,
/// the orchestrator saves the URI with [savePending] and replays it via
/// [readPending] once authentication succeeds.
///
/// See also:
/// - [NoopDeepLinkPendingStore] — discards all pending URIs (default).
/// - [InMemoryDeepLinkPendingStore] — stores one URI in memory.
abstract interface class DeepLinkPendingStore {
  /// Persists [uri] so it can be replayed after authentication.
  Future<void> savePending(Uri uri);

  /// Removes any previously stored pending URI.
  Future<void> clearPending();

  /// Returns the stored pending URI, or `null` if none exists.
  Uri? readPending();
}

// ---------------------------------------------------------------------------
// Default implementations
// ---------------------------------------------------------------------------

/// A [DeepLinkValidationPolicy] that accepts every URI unconditionally.
///
/// Use this (or omit the `validationPolicy` parameter on
/// [DeepLinkOrchestrator]) when URI filtering is handled elsewhere, such as
/// in the platform's `AndroidManifest.xml` or `Info.plist`.
class AllowAllDeepLinkValidationPolicy implements DeepLinkValidationPolicy {
  /// Creates an [AllowAllDeepLinkValidationPolicy].
  const AllowAllDeepLinkValidationPolicy();

  /// Always returns `null`, allowing every URI to proceed.
  @override
  String? failureReason(Uri uri) => null;
}

/// A [DeepLinkAuthenticationPolicy] that always reports the user as
/// authenticated.
///
/// Use this for apps that do not have a login flow, or during development
/// when you want to skip authentication gating.
class AlwaysAuthenticatedPolicy implements DeepLinkAuthenticationPolicy {
  /// Creates an [AlwaysAuthenticatedPolicy].
  const AlwaysAuthenticatedPolicy();

  /// Always returns `true`.
  @override
  bool get isAuthenticated => true;
}

/// A [DeepLinkDeduplicationStrategy] that suppresses a URI for the lifetime
/// of the session.
///
/// Once a link has been handled it is never handled again until
/// [DeepLinkOrchestrator.resetDeduplication] is called. Appropriate when
/// re-navigating to the same destination in one session is undesirable.
///
/// This strategy is stateful; create one instance per orchestrator.
class DefaultDeepLinkDeduplicationStrategy
    implements DeepLinkDeduplicationStrategy {
  /// Creates a [DefaultDeepLinkDeduplicationStrategy].
  DefaultDeepLinkDeduplicationStrategy();

  final Set<String> _seen = <String>{};

  @override
  bool shouldProcess(DeepLinkIntent intent) => _seen.add(intent.dedupeKey);

  @override
  void forget(DeepLinkIntent intent) => _seen.remove(intent.dedupeKey);

  @override
  void reset() => _seen.clear();
}

/// A [DeepLinkDeduplicationStrategy] that suppresses duplicates only within
/// a rolling time window.
///
/// After [windowDuration] has elapsed the same URI is treated as a new
/// intent, allowing intentional re-navigation to the same destination. This
/// is the right choice for most apps: it absorbs platform double-fires
/// without permanently blocking a link the user taps again later.
///
/// This strategy is stateful; create one instance per orchestrator.
class TimeWindowDeepLinkDeduplicationStrategy
    implements DeepLinkDeduplicationStrategy {
  /// Creates a [TimeWindowDeepLinkDeduplicationStrategy].
  ///
  /// [windowDuration] controls how long after the first occurrence of a URI
  /// a duplicate is suppressed. Defaults to one second.
  TimeWindowDeepLinkDeduplicationStrategy({
    this.windowDuration = const Duration(seconds: 1),
  });

  /// The duration during which identical intents are considered duplicates.
  final Duration windowDuration;

  final Map<String, DateTime> _expiryByKey = <String, DateTime>{};

  @override
  bool shouldProcess(DeepLinkIntent intent) {
    final now = DateTime.now();
    _expiryByKey.removeWhere((_, expiry) => !now.isBefore(expiry));

    final key = intent.dedupeKey;
    if (_expiryByKey.containsKey(key)) return false;

    _expiryByKey[key] = now.add(windowDuration);
    return true;
  }

  @override
  void forget(DeepLinkIntent intent) => _expiryByKey.remove(intent.dedupeKey);

  @override
  void reset() => _expiryByKey.clear();
}

/// A [DeepLinkDeduplicationStrategy] that processes every intent.
///
/// Use when the platform is known not to double-fire, or when duplicate
/// handling is idempotent and cheap.
class NoopDeepLinkDeduplicationStrategy
    implements DeepLinkDeduplicationStrategy {
  /// Creates a [NoopDeepLinkDeduplicationStrategy].
  const NoopDeepLinkDeduplicationStrategy();

  @override
  bool shouldProcess(DeepLinkIntent intent) => true;

  @override
  void forget(DeepLinkIntent intent) {}

  @override
  void reset() {}
}

/// A [DeepLinkPendingStore] that silently discards all pending URIs.
///
/// This is the default store used by [DeepLinkOrchestrator]. Choose it when
/// your app has no authentication flow or when you prefer not to replay
/// deferred deep links.
class NoopDeepLinkPendingStore implements DeepLinkPendingStore {
  /// Creates a [NoopDeepLinkPendingStore].
  const NoopDeepLinkPendingStore();

  /// Does nothing.
  @override
  Future<void> savePending(Uri uri) async {}

  /// Does nothing.
  @override
  Future<void> clearPending() async {}

  /// Always returns `null`.
  @override
  Uri? readPending() => null;
}

/// A [DeepLinkPendingStore] that holds one pending [Uri] in memory.
///
/// Stores the most-recently deferred URI in a private field. The stored URI
/// is lost when the process is killed; use a persistent store (e.g.
/// `SharedPreferences`) for cross-launch replay.
class InMemoryDeepLinkPendingStore implements DeepLinkPendingStore {
  Uri? _pending;

  /// Stores [uri], overwriting any previously stored value.
  @override
  Future<void> savePending(Uri uri) async => _pending = uri;

  /// Clears the stored URI.
  @override
  Future<void> clearPending() async => _pending = null;

  /// Returns the stored URI, or `null` if none has been saved.
  @override
  Uri? readPending() => _pending;
}

// ---------------------------------------------------------------------------
// Handler context
// ---------------------------------------------------------------------------

/// Immutable context passed to every [DeepLinkHandler.handle] call.
///
/// Provides handlers with access to shared infrastructure (auth policy,
/// pending store, and arbitrary shared data) without coupling them to the
/// orchestrator directly.
class DeepLinkHandlerContext {
  /// Creates a [DeepLinkHandlerContext].
  const DeepLinkHandlerContext({
    required this.pendingStore,
    required this.authPolicy,
    this.sharedData = const <String, Object?>{},
  });

  /// The policy used to check whether the user is authenticated.
  final DeepLinkAuthenticationPolicy authPolicy;

  /// The store used to persist and retrieve deferred deep link URIs.
  final DeepLinkPendingStore pendingStore;

  /// Arbitrary data shared across all handlers in a single orchestrator.
  ///
  /// Use this map to propagate app-level context (e.g. a navigator key or
  /// a dependency-injection container) without hard-coding dependencies in
  /// each handler.
  final Map<String, Object?> sharedData;
}
