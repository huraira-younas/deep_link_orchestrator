/// A function that transforms one [DeepLinkIntent] into another.
///
/// Use this to upgrade a [RawDeepLinkIntent] into a richer, typed intent
/// based on the URI's path or query parameters before dispatching.
///
/// Example:
/// ```dart
/// DeepLinkIntent resolver(DeepLinkIntent intent) {
///   if (intent.uri.path.startsWith('/product')) {
///     return ProductIntent(uri: intent.uri, sourceId: intent.sourceId);
///   }
///   return intent;
/// }
/// ```
typedef DeepLinkIntentResolver = DeepLinkIntent Function(DeepLinkIntent intent);

/// Immutable base class for all deep link intents.
///
/// An intent represents a single incoming deep link at a point in time.
/// Subclass this to create domain-specific intent types that your
/// [DeepLinkHandler] implementations can match against.
abstract class DeepLinkIntent {
  /// Creates a [DeepLinkIntent].
  ///
  /// [sourceId] identifies which [DeepLinkSource] produced the intent.
  /// [uri] is the raw URI of the deep link.
  /// [attributes] carries arbitrary key-value metadata.
  /// [isDeferred] marks intents that were stored and replayed after
  /// authentication.
  const DeepLinkIntent({
    this.attributes = const <String, Object?>{},
    this.isDeferred = false,
    required this.sourceId,
    required this.uri,
  });

  /// Arbitrary key-value metadata attached to this intent.
  ///
  /// Handlers may use this map to carry extra information that does not
  /// fit neatly into the URI (e.g. push-notification payloads).
  final Map<String, Object?> attributes;

  /// Whether this intent was deferred and is being replayed.
  ///
  /// An intent is deferred when it arrived while the user was not yet
  /// authenticated and was stored by [DeepLinkPendingStore] for later
  /// replay. Handlers can inspect this flag to adjust their behaviour
  /// (e.g. skip animations on deferred navigation).
  final bool isDeferred;

  /// The identifier of the [DeepLinkSource] that produced this intent.
  final String sourceId;

  /// The URI carried by this deep link.
  final Uri uri;

  /// Stable identity used for debouncing and deduplication.
  ///
  /// Two intents sharing a [dedupeKey] represent the same open of the same
  /// destination. Override this to widen or narrow what counts as a
  /// duplicate, for example to ignore a tracking query parameter.
  String get dedupeKey => '$sourceId:$uri';

  /// Serialises this intent to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'attributes': attributes,
    'isDeferred': isDeferred,
    'uri': uri.toString(),
    'sourceId': sourceId,
  };
}

/// A concrete [DeepLinkIntent] that wraps a raw URI without further typing.
///
/// [DeepLinkOrchestrator] emits [RawDeepLinkIntent] instances from its
/// sources. A [DeepLinkIntentResolver] can promote them to richer subtypes
/// before the [DeepLinkDispatcher] routes them to a handler.
class RawDeepLinkIntent extends DeepLinkIntent {
  /// Creates a [RawDeepLinkIntent].
  const RawDeepLinkIntent({
    required super.sourceId,
    required super.uri,
    super.attributes,
    super.isDeferred,
  });

  @override
  Map<String, Object?> toJson() => {
    'attributes': attributes,
    'isDeferred': isDeferred,
    'uri': uri.toString(),
    'sourceId': sourceId,
  };
}
