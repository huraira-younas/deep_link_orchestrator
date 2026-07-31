import 'interfaces/deep_link_handler.dart';
import 'interfaces/deep_link_policy.dart';
import 'deep_link_intent.dart';

/// The outcome of a single [DeepLinkDispatcher.dispatch] call.
///
/// Dispatching never throws for routine outcomes. Callers inspect the result
/// to decide whether the intent should be retried, reported, or forgotten.
enum DeepLinkDispatchResult {
  /// A handler accepted the intent and ran to completion.
  handled,

  /// No handler is registered for the intent type, or the registered handler
  /// returned `false` from [DeepLinkHandler.canHandle].
  ///
  /// This is a no-op, not a failure. Apps commonly resolve links that carry
  /// no action into an intent type with no handler.
  noHandler,

  /// The handler requires authentication but the session is signed out.
  ///
  /// This is the only result that persists the URI through
  /// [DeepLinkPendingStore.savePending] for replay after login.
  authDeferred,

  /// The handler threw while processing the intent.
  failed;

  /// Whether the intent was deliberately postponed for a later replay.
  bool get isDeferred => this == authDeferred;
}

/// Routes [DeepLinkIntent] instances to their registered [DeepLinkHandler].
///
/// Handlers are keyed by the **runtime type** of the intent they handle.
/// Register them with [registerHandler] or [registerHandlers] before calling
/// [DeepLinkOrchestrator.initialize].
///
/// Example:
/// ```dart
/// orchestrator.dispatcher.registerHandlers({
///   ProductIntent: ProductHandler(),
///   InviteIntent: InviteHandler(),
/// });
/// ```
class DeepLinkDispatcher {
  /// Creates a [DeepLinkDispatcher], optionally pre-populated with
  /// [handlers].
  DeepLinkDispatcher({Map<Type, DeepLinkHandler>? handlers})
    : _handlers = Map<Type, DeepLinkHandler>.from(handlers ?? const {});

  final Map<Type, DeepLinkHandler> _handlers;

  /// Replaces all currently registered handlers with [handlers].
  ///
  /// Any previously registered handlers are removed before the new map is
  /// applied.
  void registerHandlers(Map<Type, DeepLinkHandler> handlers) {
    _handlers.clear();
    _handlers.addAll(handlers);
  }

  /// Registers [handler] for the given [intentType], overwriting any
  /// previously registered handler for that type.
  void registerHandler(Type intentType, DeepLinkHandler handler) {
    _handlers[intentType] = handler;
  }

  /// Dispatches [intent] to its registered [DeepLinkHandler].
  ///
  /// Returns [DeepLinkDispatchResult.noHandler] when nothing is registered for
  /// the intent type, and [DeepLinkDispatchResult.authDeferred] when the
  /// handler is gated behind an unauthenticated session, in which case the URI
  /// is saved via [DeepLinkPendingStore.savePending].
  ///
  /// Exceptions thrown by [DeepLinkHandler.handle] propagate to the caller so
  /// they can be logged with their stack trace;
  /// [DeepLinkOrchestrator] maps them to [DeepLinkDispatchResult.failed].
  ///
  /// This method never writes to the pending store except on the
  /// [DeepLinkDispatchResult.authDeferred] path. Clearing consumed or failed
  /// entries is owned by [DeepLinkOrchestrator].
  Future<DeepLinkDispatchResult> dispatch({
    required DeepLinkHandlerContext context,
    required DeepLinkIntent intent,
  }) async {
    final handler = _handlers[intent.runtimeType];

    if (handler == null || !handler.canHandle(intent)) {
      return DeepLinkDispatchResult.noHandler;
    }

    if (handler.requiresAuthentication && !context.authPolicy.isAuthenticated) {
      await context.pendingStore.savePending(intent.uri);
      return DeepLinkDispatchResult.authDeferred;
    }

    await handler.handle(context: context, intent: intent);
    return DeepLinkDispatchResult.handled;
  }
}
