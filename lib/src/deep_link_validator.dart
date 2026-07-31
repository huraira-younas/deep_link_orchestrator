import 'package:flutter/foundation.dart' show protected;

import 'interfaces/deep_link_policy.dart';

/// A [DeepLinkValidationPolicy] that validates URIs by scheme, host, and
/// path prefix.
///
/// Accepts a URI if:
/// 1. Its scheme matches [customScheme], **or**
/// 2. Its scheme is `https` or `http` and its host is [expectedHost], one of
///    [expectedHost] prefixed by an entry in [allowedSubdomains], or a member
///    of [additionalHosts].
///
/// Additionally, when [supportedPaths] is non-empty, the URI path must start
/// with at least one of the listed prefixes.
///
/// Every rule is configurable, so a project should not need to subclass this
/// to widen it. When a rule genuinely cannot be expressed as configuration,
/// override [isSupportedHost] or [isSupportedPath] rather than
/// [failureReason], to keep the error messages consistent.
///
/// Example:
/// ```dart
/// final validator = DeepLinkValidator(
///   expectedHost: 'example.com',
///   customScheme: 'myapp',
///   supportedPaths: ['/product', '/invite'],
///   allowedSubdomains: ['www', 'share'],
/// );
/// ```
class DeepLinkValidator implements DeepLinkValidationPolicy {
  /// Creates a [DeepLinkValidator].
  ///
  /// [expectedHost] is the domain name used for universal/app links
  /// (e.g. `'example.com'`).
  ///
  /// [customScheme] is the app-specific URI scheme (e.g. `'myapp'`).
  ///
  /// [supportedPaths] is the list of path prefixes that are considered valid.
  /// An empty list disables path validation and all paths are accepted.
  ///
  /// [allowedSubdomains] are prefixes of [expectedHost] that are also
  /// accepted, so `'share'` accepts `share.example.com`. Defaults to `www`.
  ///
  /// [additionalHosts] are unrelated hosts that are also accepted, useful for
  /// staging domains or link shorteners.
  ///
  /// [allowRootPath] accepts `/` and the empty path, which is otherwise
  /// rejected as carrying no destination.
  const DeepLinkValidator({
    required this.expectedHost,
    required this.customScheme,

    this.allowedSubdomains = const <String>['www'],
    this.additionalHosts = const <String>{},
    this.supportedPaths = const <String>[],
    this.allowRootPath = false,
  });

  /// The list of path prefixes that are accepted
  /// (e.g. `['/product', '/invite']`).
  ///
  /// When empty every path allowed by [allowRootPath] is accepted.
  final List<String> supportedPaths;

  /// Subdomain labels of [expectedHost] that are also accepted.
  final List<String> allowedSubdomains;

  /// Hosts accepted in addition to those derived from [expectedHost].
  final Set<String> additionalHosts;

  /// The expected host for `https`/`http` universal links
  /// (e.g. `'example.com'`).
  final String expectedHost;

  /// The custom URI scheme for app-specific deep links (e.g. `'myapp'`).
  final String customScheme;

  /// Whether `/` and the empty path are accepted.
  final bool allowRootPath;

  /// Returns `true` if [uri] passes all validation rules.
  bool isValid(Uri uri) => failureReason(uri) == null;

  /// Returns a failure description if [uri] is invalid, or `null` if valid.
  @override
  String? failureReason(Uri uri) {
    if (!isSupportedHost(uri)) {
      return 'Unsupported scheme/host: ${uri.scheme}://${uri.host}';
    }
    if (!isSupportedPath(uri.path)) {
      return 'Unsupported path: ${uri.path}';
    }
    return null;
  }

  /// Whether [path] is one of the destinations this app knows how to open.
  @protected
  bool isSupportedPath(String path) {
    if (path.isEmpty || path == '/') return allowRootPath;
    if (supportedPaths.isEmpty) return true;
    return supportedPaths.any(path.startsWith);
  }

  /// Whether [uri] arrives on a scheme and host that belong to this app.
  @protected
  bool isSupportedHost(Uri uri) {
    if (uri.scheme == customScheme) return true;
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;

    final host = uri.host;
    if (host == expectedHost || additionalHosts.contains(host)) return true;
    return allowedSubdomains.any((sub) => host == '$sub.$expectedHost');
  }
}
