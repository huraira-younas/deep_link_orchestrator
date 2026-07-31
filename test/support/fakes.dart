import 'package:deep_link_orchestrator/deep_link_orchestrator.dart';

/// A raw intent whose source and URI are easy to build in a test.
RawDeepLinkIntent rawIntent(String uri, {String sourceId = 'test'}) =>
    RawDeepLinkIntent(uri: Uri.parse(uri), sourceId: sourceId);

/// A [DeepLinkSource] that emits intents on demand instead of from a channel.
class FakeDeepLinkSource implements DeepLinkSource {
  FakeDeepLinkSource({this.initialIntent});

  /// Returned by [getInitialIntent] on every call, mimicking platform
  /// channels that keep replaying the launch URI for the whole process.
  DeepLinkIntent? initialIntent;

  DeepLinkIntentSink? _onIntent;
  bool disposed = false;

  @override
  String get id => 'fake';

  @override
  Future<void> initialize(DeepLinkIntentSink onIntent) async =>
      _onIntent = onIntent;

  @override
  Future<DeepLinkIntent?> getInitialIntent() async => initialIntent;

  @override
  Future<void> dispose() async => disposed = true;

  /// Pushes [intent] through the pipeline as if the platform had delivered it.
  Future<void> emit(DeepLinkIntent intent) async => _onIntent?.call(intent);
}

/// Records every intent it handles, with configurable behaviour.
class RecordingHandler extends TypedDeepLinkHandler<RawDeepLinkIntent> {
  RecordingHandler({
    this.requiresAuthentication = false,
    this.onCalled,
    this.throws = false,
  });

  final List<Uri> handled = <Uri>[];
  final Future<void> Function(RawDeepLinkIntent intent)? onCalled;
  final bool throws;

  @override
  final bool requiresAuthentication;

  @override
  Future<void> onHandle(
    RawDeepLinkIntent intent,
    DeepLinkHandlerContext context,
  ) async {
    handled.add(intent.uri);
    await onCalled?.call(intent);
    if (throws) throw StateError('handler failed for ${intent.uri}');
  }
}

/// An auth policy whose signed-in state can be flipped mid-test.
class MutableAuthPolicy implements DeepLinkAuthenticationPolicy {
  MutableAuthPolicy({this.isAuthenticated = true});

  @override
  bool isAuthenticated;
}

/// A validation policy that rejects any URI containing [rejectSubstring].
class SubstringRejectPolicy implements DeepLinkValidationPolicy {
  const SubstringRejectPolicy(this.rejectSubstring);

  final String rejectSubstring;

  @override
  String? failureReason(Uri uri) =>
      uri.toString().contains(rejectSubstring) ? 'rejected: $uri' : null;
}
