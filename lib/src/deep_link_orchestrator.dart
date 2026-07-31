import 'dart:async' show Completer, Timer;

import 'interfaces/deep_link_source.dart';
import 'interfaces/deep_link_policy.dart';
import 'deep_link_dispatcher.dart';
import 'deep_link_logger.dart';
import 'deep_link_intent.dart';

/// The central coordinator for the deep link pipeline.
///
/// [DeepLinkOrchestrator] wires together one or more [DeepLinkSource]s, a
/// validation policy, a deduplication strategy, an authentication policy, and
/// a [DeepLinkDispatcher] into a single, managed pipeline.
///
/// ## Lifecycle
///
/// 1. Construct the orchestrator with your sources and policies.
/// 2. Register handlers on [dispatcher].
/// 3. Call [initialize] (typically in `initState` or `main`).
/// 4. Call [checkInitialIntent] to process any cold-start deep link.
/// 5. Call [dispose] when the orchestrator is no longer needed.
///
/// ## Pending store semantics
///
/// The pending store holds at most one URI, and only ever because something
/// deliberately deferred it: an unauthenticated handler, or a handler that
/// called [DeepLinkPendingStore.savePending] itself. Every other outcome
/// clears the store, so a link that fails to open is never replayed later.
///
/// ## Ordering
///
/// Intents are debounced per URI and then processed one at a time in arrival
/// order. A slow handler delays the links behind it but never causes one to
/// be dropped.
///
/// ## Example
///
/// ```dart
/// final orchestrator = DeepLinkOrchestrator(
///   sources: [AppLinksDeepLinkSource()],
///   validationPolicy: DeepLinkValidator(
///     expectedHost: 'example.com',
///     customScheme: 'myapp',
///     supportedPaths: ['/product'],
///   ),
/// );
///
/// orchestrator.dispatcher.registerHandlers({
///   ProductIntent: ProductHandler(),
/// });
///
/// await orchestrator.initialize();
/// await orchestrator.checkInitialIntent();
/// ```
class DeepLinkOrchestrator {
  /// Creates a [DeepLinkOrchestrator].
  ///
  /// [sources] must contain at least one [DeepLinkSource].
  ///
  /// All policy and strategy parameters are optional; sensible defaults are
  /// used when omitted:
  /// - [validationPolicy] defaults to [AllowAllDeepLinkValidationPolicy].
  /// - [deduplicationStrategy] defaults to a one-second
  ///   [TimeWindowDeepLinkDeduplicationStrategy], which absorbs platform
  ///   double-fires without blocking a link the user opens again later.
  /// - [authPolicy] defaults to [AlwaysAuthenticatedPolicy].
  /// - [pendingStore] defaults to [NoopDeepLinkPendingStore].
  /// - [dispatcher] defaults to an empty [DeepLinkDispatcher].
  /// - [logger] defaults to [DeveloperDeepLinkLogger].
  /// - [debounceDelay] defaults to 300 ms.
  DeepLinkOrchestrator({
    required List<DeepLinkSource> sources,

    DeepLinkDeduplicationStrategy? deduplicationStrategy,
    DeepLinkValidationPolicy? validationPolicy,
    DeepLinkAuthenticationPolicy? authPolicy,
    DeepLinkIntentResolver? intentResolver,
    DeepLinkPendingStore? pendingStore,
    DeepLinkDispatcher? dispatcher,

    this.debounceDelay = const Duration(milliseconds: 300),
    this.sharedData = const <String, Object?>{},
    DeepLinkLogger? logger,
  }) : _deduplicationStrategy =
           deduplicationStrategy ?? TimeWindowDeepLinkDeduplicationStrategy(),
       _validationPolicy =
           validationPolicy ?? const AllowAllDeepLinkValidationPolicy(),
       _pendingStore = pendingStore ?? const NoopDeepLinkPendingStore(),
       _authPolicy = authPolicy ?? const AlwaysAuthenticatedPolicy(),
       _logger = logger ?? const DeveloperDeepLinkLogger(),
       _dispatcher = dispatcher ?? DeepLinkDispatcher(),
       _intentResolver = intentResolver,
       _sources = sources;

  final DeepLinkDeduplicationStrategy _deduplicationStrategy;
  final DeepLinkValidationPolicy _validationPolicy;
  final DeepLinkAuthenticationPolicy _authPolicy;
  final DeepLinkIntentResolver? _intentResolver;
  final DeepLinkPendingStore _pendingStore;
  final DeepLinkDispatcher _dispatcher;
  final List<DeepLinkSource> _sources;
  final DeepLinkLogger _logger;

  /// The delay applied between receiving a raw URI and processing it.
  ///
  /// Debouncing prevents duplicate intents that arrive in rapid succession
  /// (e.g. from multiple platform callbacks) from being processed more than
  /// once. Intents are debounced per URI, so two different links arriving
  /// within the same window are both processed. Defaults to 300 milliseconds.
  final Duration debounceDelay;

  /// Arbitrary data made available to every handler via
  /// [DeepLinkHandlerContext.sharedData].
  ///
  /// Use this map to pass app-level singletons (e.g. a navigator key or a
  /// service locator) into handlers without coupling them to global state.
  final Map<String, Object?> sharedData;

  final Map<String, _DebouncedIntent> _debounced = <String, _DebouncedIntent>{};
  Future<void> _queue = Future<void>.value();
  bool _initialIntentConsumed = false;
  bool _isInitialized = false;
  bool _isDisposed = false;

  /// The dispatcher used to route intents to their registered handlers.
  ///
  /// Call [DeepLinkDispatcher.registerHandler] or
  /// [DeepLinkDispatcher.registerHandlers] on this object before calling
  /// [initialize].
  DeepLinkDispatcher get dispatcher => _dispatcher;

  /// Subscribes all [DeepLinkSource]s to their platform channels.
  ///
  /// This method is idempotent: subsequent calls after the first are no-ops.
  /// Must be awaited before [checkInitialIntent] or [handleIntent].
  Future<void> initialize() async {
    if (_isInitialized) return;

    for (final source in _sources) {
      await source.initialize(_onIntentReceived);
    }

    _isInitialized = true;
    _logger.info(message: 'Initialized ${_sources.length} source(s)');
  }

  /// Cancels all subscriptions and releases resources held by each source.
  ///
  /// Pending debounced intents are dropped and anything awaiting them
  /// completes, so a caller blocked on [handleIntent] is never stranded.
  /// After [dispose] returns the orchestrator must not be used again.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    for (final entry in _debounced.values) {
      entry.cancel();
    }
    _debounced.clear();

    for (final source in _sources) {
      await source.dispose();
    }
  }

  /// Processes the deep link that cold-started the app, if any.
  ///
  /// The cold-start URI is consumed **once per process**. Platform channels
  /// keep returning the launch URI for the lifetime of the process, so
  /// without this guard every later call would replay the same link. That
  /// makes this method safe to call from a widget that remounts, such as a
  /// shell rebuilt after a role or session change.
  ///
  /// Iterates through [sources] in order and processes the first non-null
  /// initial intent it finds. If no source returns an initial intent, falls
  /// back to any URI stored in the [DeepLinkPendingStore], replayed as a
  /// deferred intent.
  ///
  /// Must be called after [initialize].
  Future<void> checkInitialIntent() async {
    if (!_initialIntentConsumed) {
      for (final source in _sources) {
        final intent = await source.getInitialIntent();
        if (intent == null) continue;

        _initialIntentConsumed = true;
        await _onIntentReceived(intent);
        return;
      }

      _initialIntentConsumed = true;
    }

    final stored = _pendingStore.readPending();
    if (stored == null) return;

    await _onIntentReceived(
      RawDeepLinkIntent(
        sourceId: 'stored_pending',
        isDeferred: true,
        uri: stored,
      ),
    );
  }

  /// Manually injects [intent] into the pipeline.
  ///
  /// Useful for testing or for forwarding intents from custom platform
  /// channels that are not modelled as a [DeepLinkSource]. The returned
  /// future completes once the intent has been debounced and processed.
  Future<void> handleIntent(DeepLinkIntent intent) => _onIntentReceived(intent);

  /// Forgets every intent the deduplication strategy has recorded.
  ///
  /// After this call the next intent will always be processed, even if it
  /// was seen before. Useful after manual navigation resets where
  /// re-processing the same link is intentional.
  void resetDeduplication() => _deduplicationStrategy.reset();

  /// Allows the cold-start URI to be picked up again by [checkInitialIntent].
  ///
  /// Rarely needed. The cold-start link is consumed once per process on
  /// purpose, so only call this when replaying the launch link is genuinely
  /// the intended behaviour.
  void resetInitialIntent() => _initialIntentConsumed = false;

  /// Debounces [intent] per URI, then processes it behind any earlier intent.
  ///
  /// Debouncing is keyed on [DeepLinkIntent.dedupeKey] rather than applied
  /// globally, so a burst of callbacks for one link collapses without
  /// discarding a different link that arrives in the same window.
  Future<void> _onIntentReceived(DeepLinkIntent intent) {
    if (_isDisposed) return Future<void>.value();

    // Reuse the completer of the call being superseded so its awaiter still
    // completes when the collapsed intent is finally processed.
    final entry = _debounced.remove(intent.dedupeKey)?..cancelTimer();
    final completer = entry?.completer ?? Completer<void>();

    _debounced[intent.dedupeKey] = _DebouncedIntent(
      completer: completer,
      timer: Timer(debounceDelay, () {
        _debounced.remove(intent.dedupeKey);
        _enqueue(() => _runIntent(intent)).whenComplete(() {
          if (!completer.isCompleted) completer.complete();
        });
      }),
    );

    return completer.future;
  }

  /// Chains [task] after any in-flight processing so intents never overlap.
  ///
  /// Errors are absorbed here as well as in [_processIntent]; a throw from a
  /// custom policy must not poison the queue for every later link.
  Future<void> _enqueue(Future<void> Function() task) => _queue = _queue
      .then((_) => task())
      .catchError((Object error, StackTrace stackTrace) {
        _logger.error(
          message: 'Deep link pipeline error',
          stackTrace: stackTrace,
          error: error,
        );
      });

  Future<void> _runIntent(DeepLinkIntent intent) async {
    if (_isDisposed) return;

    if (!_deduplicationStrategy.shouldProcess(intent)) {
      _logger.info(message: 'Duplicate deep link ignored: ${intent.uri}');
      return;
    }

    // Only a completed handle should suppress a retry of the same URI.
    final result = await _processIntent(intent);
    if (result != .handled) {
      _deduplicationStrategy.forget(intent);
    }
  }

  Future<DeepLinkDispatchResult> _processIntent(DeepLinkIntent intent) async {
    final store = _RecordingPendingStore(_pendingStore);

    try {
      final reason = _validationPolicy.failureReason(intent.uri);
      if (reason != null) {
        _logger.warn(message: reason);
        return .failed;
      }

      final resolved = _intentResolver?.call(intent) ?? intent;
      _logger.info(
        message: 'Dispatching ${resolved.runtimeType} for ${intent.uri}',
      );

      final result = await _dispatcher.dispatch(
        intent: resolved,
        context: DeepLinkHandlerContext(
          authPolicy: _authPolicy,
          sharedData: sharedData,
          pendingStore: store,
        ),
      );

      if (result == .noHandler) {
        _logger.warn(
          message: 'No handler registered for ${resolved.runtimeType}',
        );
      }

      return result;
    } catch (error, stackTrace) {
      _logger.error(
        message: 'Failed to process deep link: ${intent.uri}',
        stackTrace: stackTrace,
        error: error,
      );
      return .failed;
    } finally {
      // A URI survives only when this pass deliberately deferred it. Anything
      // else (handled, unroutable, invalid, or thrown) drops the stored link
      // so it cannot reopen on a later checkInitialIntent.
      if (!store.didSave) await _pendingStore.clearPending();
    }
  }
}

/// A scheduled intent plus the awaiter that is waiting on its processing.
class _DebouncedIntent {
  _DebouncedIntent({required this.completer, required this.timer});

  final Completer<void> completer;
  final Timer timer;

  void cancelTimer() => timer.cancel();

  void cancel() {
    timer.cancel();
    if (!completer.isCompleted) completer.complete();
  }
}

/// Wraps a [DeepLinkPendingStore] to record whether a deferral was requested
/// during a single dispatch pass.
class _RecordingPendingStore implements DeepLinkPendingStore {
  _RecordingPendingStore(this._delegate);

  final DeepLinkPendingStore _delegate;

  /// Whether [savePending] was called and not subsequently cleared.
  bool didSave = false;

  @override
  Future<void> savePending(Uri uri) async {
    didSave = true;
    await _delegate.savePending(uri);
  }

  @override
  Future<void> clearPending() async {
    didSave = false;
    await _delegate.clearPending();
  }

  @override
  Uri? readPending() => _delegate.readPending();
}
