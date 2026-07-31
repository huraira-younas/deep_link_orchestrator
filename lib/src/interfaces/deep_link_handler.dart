import '../deep_link_intent.dart';
import 'deep_link_policy.dart';

/// Processes a specific type of [DeepLinkIntent].
///
/// Register implementations with [DeepLinkDispatcher.registerHandler] keyed
/// by the concrete [DeepLinkIntent] subtype they handle.
///
/// Prefer [TypedDeepLinkHandler] unless you need custom [canHandle] logic; it
/// removes the type check and the cast.
///
/// Example:
/// ```dart
/// class ProductHandler implements DeepLinkHandler {
///   @override
///   bool get requiresAuthentication => false;
///
///   @override
///   bool canHandle(DeepLinkIntent intent) => intent is ProductIntent;
///
///   @override
///   Future<void> handle({
///     required DeepLinkHandlerContext context,
///     required DeepLinkIntent intent,
///   }) async {
///     final productIntent = intent as ProductIntent;
///     // navigate to product screen
///   }
/// }
/// ```
abstract class DeepLinkHandler {
  /// Creates a [DeepLinkHandler].
  const DeepLinkHandler();

  /// Whether this handler requires an authenticated user session.
  ///
  /// When `true`, [DeepLinkDispatcher] checks
  /// [DeepLinkAuthenticationPolicy.isAuthenticated] before calling [handle].
  /// If the user is not authenticated the URI is saved via
  /// [DeepLinkPendingStore] and dispatch reports
  /// [DeepLinkDispatchResult.authDeferred] without invoking [handle].
  bool get requiresAuthentication;

  /// Returns `true` if this handler is able to process [intent].
  ///
  /// Even though the dispatcher already selects handlers by runtime type,
  /// this method allows an implementation to reject edge-case intents (e.g.
  /// URIs with unsupported query parameters).
  bool canHandle(DeepLinkIntent intent);

  /// Processes [intent] using the provided [context].
  ///
  /// Throw any exception to signal failure; the orchestrator logs the error,
  /// drops any stored pending URI so the link is not replayed later, and
  /// continues processing subsequent intents.
  Future<void> handle({
    required DeepLinkHandlerContext context,
    required DeepLinkIntent intent,
  });
}

/// A [DeepLinkHandler] bound to one intent type.
///
/// Implements [canHandle] from the type parameter and hands [onHandle] an
/// already-cast intent, so a handler is reduced to the code that matters.
/// [requiresAuthentication] defaults to `false`; override it to gate the
/// handler behind a signed-in session.
///
/// Example:
/// ```dart
/// class ProductHandler extends TypedDeepLinkHandler<ProductIntent> {
///   @override
///   Future<void> onHandle(ProductIntent intent, DeepLinkHandlerContext _) =>
///       router.push('/product/${intent.productId}');
/// }
/// ```
abstract class TypedDeepLinkHandler<T extends DeepLinkIntent>
    extends DeepLinkHandler {
  /// Creates a [TypedDeepLinkHandler].
  const TypedDeepLinkHandler();

  @override
  bool get requiresAuthentication => false;

  @override
  bool canHandle(DeepLinkIntent intent) => intent is T;

  @override
  Future<void> handle({
    required DeepLinkHandlerContext context,
    required DeepLinkIntent intent,
  }) => onHandle(intent as T, context);

  /// Processes the already-typed [intent].
  Future<void> onHandle(T intent, DeepLinkHandlerContext context);
}
