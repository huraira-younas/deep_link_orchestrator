import 'package:deep_link_orchestrator/deep_link_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = DeepLinkValidator(
    expectedHost: 'example.com',
    customScheme: 'myapp',
    supportedPaths: ['/product', '/invite'],
  );

  group('scheme and host', () {
    test('accepts the custom scheme regardless of host', () {
      expect(
        validator.isValid(Uri.parse('myapp://anything/product/1')),
        isTrue,
      );
    });

    test('accepts the expected host over https and http', () {
      expect(
        validator.isValid(Uri.parse('https://example.com/product/1')),
        isTrue,
      );
      expect(
        validator.isValid(Uri.parse('http://example.com/product/1')),
        isTrue,
      );
    });

    test('accepts the www subdomain by default', () {
      expect(
        validator.isValid(Uri.parse('https://www.example.com/product/1')),
        isTrue,
      );
    });

    test('rejects an unrelated host', () {
      expect(
        validator.isValid(Uri.parse('https://evil.com/product/1')),
        isFalse,
      );
    });

    test('rejects a subdomain that was not opted in', () {
      expect(
        validator.isValid(Uri.parse('https://share.example.com/product/1')),
        isFalse,
      );
    });

    test('accepts a subdomain listed in allowedSubdomains', () {
      const withShare = DeepLinkValidator(
        expectedHost: 'example.com',
        customScheme: 'myapp',
        supportedPaths: ['/product'],
        allowedSubdomains: ['www', 'share'],
      );

      expect(
        withShare.isValid(Uri.parse('https://share.example.com/product/1')),
        isTrue,
      );
      expect(
        withShare.isValid(Uri.parse('https://www.example.com/product/1')),
        isTrue,
      );
    });

    test('accepts an unrelated host listed in additionalHosts', () {
      const withStaging = DeepLinkValidator(
        expectedHost: 'example.com',
        customScheme: 'myapp',
        supportedPaths: ['/product'],
        additionalHosts: {'staging.internal'},
      );

      expect(
        withStaging.isValid(Uri.parse('https://staging.internal/product/1')),
        isTrue,
      );
    });

    test('rejects a scheme that is neither custom nor http(s)', () {
      expect(
        validator.isValid(Uri.parse('ftp://example.com/product/1')),
        isFalse,
      );
    });
  });

  group('path', () {
    test('rejects a path outside supportedPaths', () {
      expect(
        validator.isValid(Uri.parse('https://example.com/admin')),
        isFalse,
      );
    });

    test('rejects the root path by default', () {
      expect(validator.isValid(Uri.parse('https://example.com/')), isFalse);
    });

    test('accepts the root path when allowRootPath is set', () {
      const rootAllowed = DeepLinkValidator(
        expectedHost: 'example.com',
        customScheme: 'myapp',
        allowRootPath: true,
      );

      expect(rootAllowed.isValid(Uri.parse('https://example.com/')), isTrue);
      expect(rootAllowed.isValid(Uri.parse('myapp://')), isTrue);
    });

    test('accepts any non-root path when supportedPaths is empty', () {
      const anyPath = DeepLinkValidator(
        expectedHost: 'example.com',
        customScheme: 'myapp',
      );

      expect(
        anyPath.isValid(Uri.parse('https://example.com/whatever')),
        isTrue,
      );
      expect(anyPath.isValid(Uri.parse('https://example.com/')), isFalse);
    });
  });

  test('failureReason describes why a URI was rejected', () {
    expect(
      validator.failureReason(Uri.parse('https://evil.com/product')),
      contains('Unsupported scheme/host'),
    );
    expect(
      validator.failureReason(Uri.parse('https://example.com/admin')),
      contains('Unsupported path'),
    );
    expect(
      validator.failureReason(Uri.parse('https://example.com/product/1')),
      isNull,
    );
  });
}
