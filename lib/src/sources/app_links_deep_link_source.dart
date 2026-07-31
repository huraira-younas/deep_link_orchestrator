import 'dart:async' show StreamSubscription;

import 'package:app_links/app_links.dart';

import '../interfaces/deep_link_source.dart';
import '../deep_link_intent.dart';

/// A [DeepLinkSource] backed by the [`app_links`](https://pub.dev/packages/app_links)
/// package.
///
/// Handles both universal links (`https://`) and custom-scheme links
/// (`myapp://`) on Android, iOS, macOS, and Windows.
///
/// Pass a pre-configured [AppLinks] instance to the constructor when you need
/// to inject a test double; omit it to use the default platform
/// implementation.
///
/// Example:
/// ```dart
/// final orchestrator = DeepLinkOrchestrator(
///   sources: [AppLinksDeepLinkSource()],
/// );
/// ```
class AppLinksDeepLinkSource implements DeepLinkSource {
  /// Creates an [AppLinksDeepLinkSource].
  ///
  /// [appLinks] may be provided for testing; defaults to `AppLinks()`.
  AppLinksDeepLinkSource({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  /// The source identifier used in every [RawDeepLinkIntent] this source
  /// produces.
  static const String sourceId = 'app_links';

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;

  /// Returns [sourceId] (`'app_links'`).
  @override
  String get id => sourceId;

  /// Subscribes to [AppLinks.uriLinkStream] and forwards each URI to
  /// [onIntent] as a [RawDeepLinkIntent].
  ///
  /// Any existing subscription is cancelled before a new one is created,
  /// making this method safe to call more than once.
  @override
  Future<void> initialize(DeepLinkIntentSink onIntent) async {
    await _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen((uri) {
      onIntent(RawDeepLinkIntent(sourceId: id, uri: uri));
    });
  }

  /// Returns a [RawDeepLinkIntent] wrapping the URI that cold-started the
  /// app, or `null` if the app was opened normally.
  @override
  Future<DeepLinkIntent?> getInitialIntent() async {
    final uri = await _appLinks.getInitialLink();
    if (uri == null) return null;
    return RawDeepLinkIntent(sourceId: id, uri: uri);
  }

  /// Cancels the active stream subscription and sets it to `null`.
  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
