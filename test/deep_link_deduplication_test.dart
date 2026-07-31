import 'package:deep_link_orchestrator/deep_link_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('DeepLinkIntent.dedupeKey', () {
    test('is shared by identical source and uri', () {
      expect(
        rawIntent('myapp://a/1').dedupeKey,
        rawIntent('myapp://a/1').dedupeKey,
      );
    });

    test('differs across sources and uris', () {
      expect(
        rawIntent('myapp://a/1').dedupeKey,
        isNot(rawIntent('myapp://a/2').dedupeKey),
      );
      expect(
        rawIntent('myapp://a/1', sourceId: 'x').dedupeKey,
        isNot(rawIntent('myapp://a/1', sourceId: 'y').dedupeKey),
      );
    });
  });

  group('DefaultDeepLinkDeduplicationStrategy', () {
    test('suppresses every repeat of a key, not just the most recent', () {
      final strategy = DefaultDeepLinkDeduplicationStrategy();
      final a = rawIntent('myapp://a');
      final b = rawIntent('myapp://b');

      expect(strategy.shouldProcess(a), isTrue);
      expect(strategy.shouldProcess(b), isTrue);
      expect(strategy.shouldProcess(a), isFalse);
    });

    test('forget re-admits a single key', () {
      final strategy = DefaultDeepLinkDeduplicationStrategy();
      final a = rawIntent('myapp://a');

      expect(strategy.shouldProcess(a), isTrue);
      strategy.forget(a);
      expect(strategy.shouldProcess(a), isTrue);
    });

    test('reset re-admits every key', () {
      final strategy = DefaultDeepLinkDeduplicationStrategy();
      final a = rawIntent('myapp://a');

      expect(strategy.shouldProcess(a), isTrue);
      strategy.reset();
      expect(strategy.shouldProcess(a), isTrue);
    });
  });

  group('TimeWindowDeepLinkDeduplicationStrategy', () {
    test('suppresses a repeat inside the window', () {
      final strategy = TimeWindowDeepLinkDeduplicationStrategy(
        windowDuration: const Duration(seconds: 5),
      );
      final a = rawIntent('myapp://a');

      expect(strategy.shouldProcess(a), isTrue);
      expect(strategy.shouldProcess(a), isFalse);
    });

    test('admits a repeat once the window has elapsed', () async {
      final strategy = TimeWindowDeepLinkDeduplicationStrategy(
        windowDuration: const Duration(milliseconds: 20),
      );
      final a = rawIntent('myapp://a');

      expect(strategy.shouldProcess(a), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(strategy.shouldProcess(a), isTrue);
    });

    test('tracks keys independently', () {
      final strategy = TimeWindowDeepLinkDeduplicationStrategy(
        windowDuration: const Duration(seconds: 5),
      );

      expect(strategy.shouldProcess(rawIntent('myapp://a')), isTrue);
      expect(strategy.shouldProcess(rawIntent('myapp://b')), isTrue);
      expect(strategy.shouldProcess(rawIntent('myapp://a')), isFalse);
    });
  });

  test('NoopDeepLinkDeduplicationStrategy admits everything', () {
    const strategy = NoopDeepLinkDeduplicationStrategy();
    final a = rawIntent('myapp://a');

    expect(strategy.shouldProcess(a), isTrue);
    expect(strategy.shouldProcess(a), isTrue);
  });
}
