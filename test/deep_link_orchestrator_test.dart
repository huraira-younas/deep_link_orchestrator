import 'package:deep_link_orchestrator/deep_link_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late InMemoryDeepLinkPendingStore store;
  late FakeDeepLinkSource source;
  late MutableAuthPolicy auth;

  setUp(() {
    store = InMemoryDeepLinkPendingStore();
    source = FakeDeepLinkSource();
    auth = MutableAuthPolicy();
  });

  DeepLinkOrchestrator build({
    DeepLinkDeduplicationStrategy? deduplicationStrategy,
    DeepLinkValidationPolicy? validationPolicy,
    required DeepLinkHandler handler,
  }) => DeepLinkOrchestrator(
    sources: [source],
    pendingStore: store,
    authPolicy: auth,
    logger: const NoopDeepLinkLogger(),
    debounceDelay: Duration.zero,
    validationPolicy: validationPolicy,
    deduplicationStrategy:
        deduplicationStrategy ?? const NoopDeepLinkDeduplicationStrategy(),
    dispatcher: DeepLinkDispatcher(handlers: {RawDeepLinkIntent: handler}),
  );

  group('cold start', () {
    test('processes the launch link once even if checked repeatedly', () async {
      final handler = RecordingHandler();
      final orchestrator = build(handler: handler);
      source.initialIntent = rawIntent('myapp://product/1');

      await orchestrator.initialize();
      await orchestrator.checkInitialIntent();
      await orchestrator.checkInitialIntent();
      await orchestrator.checkInitialIntent();

      expect(handler.handled, hasLength(1));
      await orchestrator.dispose();
    });

    test('resetInitialIntent opts back in to the launch link', () async {
      final handler = RecordingHandler();
      final orchestrator = build(handler: handler);
      source.initialIntent = rawIntent('myapp://product/1');

      await orchestrator.initialize();
      await orchestrator.checkInitialIntent();
      orchestrator.resetInitialIntent();
      await orchestrator.checkInitialIntent();

      expect(handler.handled, hasLength(2));
      await orchestrator.dispose();
    });
  });

  group('pending store lifecycle', () {
    test('a handled link leaves nothing behind', () async {
      final orchestrator = build(handler: RecordingHandler());
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://product/1'));

      expect(store.readPending(), isNull);
      await orchestrator.dispose();
    });

    test('a link whose handler throws is not saved for later', () async {
      final orchestrator = build(handler: RecordingHandler(throws: true));
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://product/1'));

      expect(store.readPending(), isNull);
      await orchestrator.dispose();
    });

    test('a link with no handler is not saved for later', () async {
      final orchestrator = DeepLinkOrchestrator(
        sources: [source],
        pendingStore: store,
        debounceDelay: Duration.zero,
        logger: const NoopDeepLinkLogger(),
        deduplicationStrategy: const NoopDeepLinkDeduplicationStrategy(),
      );
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://product/1'));

      expect(store.readPending(), isNull);
      await orchestrator.dispose();
    });

    test('an invalid link is not saved for later', () async {
      final orchestrator = build(
        handler: RecordingHandler(),
        validationPolicy: const SubstringRejectPolicy('blocked'),
      );
      await orchestrator.initialize();
      await store.savePending(Uri.parse('myapp://stale'));

      await orchestrator.handleIntent(rawIntent('myapp://blocked'));

      expect(store.readPending(), isNull);
      await orchestrator.dispose();
    });

    test('only an auth deferral survives, and replays after sign in', () async {
      auth.isAuthenticated = false;
      final handler = RecordingHandler(requiresAuthentication: true);
      final orchestrator = build(handler: handler);
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://invite/1'));
      expect(store.readPending(), Uri.parse('myapp://invite/1'));
      expect(handler.handled, isEmpty);

      auth.isAuthenticated = true;
      await orchestrator.checkInitialIntent();

      expect(handler.handled, [Uri.parse('myapp://invite/1')]);
      expect(store.readPending(), isNull);
      await orchestrator.dispose();
    });

    test('a replayed pending link is marked deferred', () async {
      final seen = <bool>[];
      final orchestrator = build(
        handler: RecordingHandler(
          onCalled: (intent) async => seen.add(intent.isDeferred),
        ),
      );
      await orchestrator.initialize();
      await store.savePending(Uri.parse('myapp://invite/1'));

      await orchestrator.checkInitialIntent();

      expect(seen, [true]);
      await orchestrator.dispose();
    });
  });

  group('ordering', () {
    test('two links arriving together are both handled, in order', () async {
      final handler = RecordingHandler(
        onCalled: (_) => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      final orchestrator = build(handler: handler);
      await orchestrator.initialize();

      await Future.wait([
        orchestrator.handleIntent(rawIntent('myapp://product/1')),
        orchestrator.handleIntent(rawIntent('myapp://product/2')),
      ]);

      expect(handler.handled, [
        Uri.parse('myapp://product/1'),
        Uri.parse('myapp://product/2'),
      ]);
      await orchestrator.dispose();
    });

    test('a burst of the same link collapses to one handle', () async {
      final handler = RecordingHandler();
      final orchestrator = DeepLinkOrchestrator(
        sources: [source],
        pendingStore: store,
        logger: const NoopDeepLinkLogger(),
        debounceDelay: const Duration(milliseconds: 30),
        deduplicationStrategy: const NoopDeepLinkDeduplicationStrategy(),
        dispatcher: DeepLinkDispatcher(handlers: {RawDeepLinkIntent: handler}),
      );
      await orchestrator.initialize();

      await Future.wait([
        orchestrator.handleIntent(rawIntent('myapp://product/1')),
        orchestrator.handleIntent(rawIntent('myapp://product/1')),
        orchestrator.handleIntent(rawIntent('myapp://product/1')),
      ]);

      expect(handler.handled, hasLength(1));
      await orchestrator.dispose();
    });

    test('handleIntent completes only after the handler has run', () async {
      var finished = false;
      final orchestrator = build(
        handler: RecordingHandler(
          onCalled: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            finished = true;
          },
        ),
      );
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://product/1'));

      expect(finished, isTrue);
      await orchestrator.dispose();
    });
  });

  group('deduplication', () {
    test('suppresses a link that already opened', () async {
      final handler = RecordingHandler();
      final orchestrator = build(
        handler: handler,
        deduplicationStrategy: DefaultDeepLinkDeduplicationStrategy(),
      );
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://product/1'));
      await orchestrator.handleIntent(rawIntent('myapp://product/1'));

      expect(handler.handled, hasLength(1));
      await orchestrator.dispose();
    });

    test('lets a link that failed be retried', () async {
      final handler = RecordingHandler(throws: true);
      final orchestrator = build(
        handler: handler,
        deduplicationStrategy: DefaultDeepLinkDeduplicationStrategy(),
      );
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://product/1'));
      await orchestrator.handleIntent(rawIntent('myapp://product/1'));

      expect(handler.handled, hasLength(2));
      await orchestrator.dispose();
    });

    test('resetDeduplication re-admits a handled link', () async {
      final handler = RecordingHandler();
      final orchestrator = build(
        handler: handler,
        deduplicationStrategy: DefaultDeepLinkDeduplicationStrategy(),
      );
      await orchestrator.initialize();

      await orchestrator.handleIntent(rawIntent('myapp://product/1'));
      orchestrator.resetDeduplication();
      await orchestrator.handleIntent(rawIntent('myapp://product/1'));

      expect(handler.handled, hasLength(2));
      await orchestrator.dispose();
    });
  });

  group('lifecycle', () {
    test('initialize is idempotent and dispose releases sources', () async {
      final orchestrator = build(handler: RecordingHandler());

      await orchestrator.initialize();
      await orchestrator.initialize();
      await orchestrator.dispose();

      expect(source.disposed, isTrue);
    });

    test('dispose completes callers awaiting a debounced link', () async {
      final handler = RecordingHandler();
      final orchestrator = DeepLinkOrchestrator(
        sources: [source],
        pendingStore: store,
        logger: const NoopDeepLinkLogger(),
        debounceDelay: const Duration(seconds: 30),
        dispatcher: DeepLinkDispatcher(handlers: {RawDeepLinkIntent: handler}),
      );
      await orchestrator.initialize();

      final pending = orchestrator.handleIntent(rawIntent('myapp://product/1'));
      await orchestrator.dispose();

      await expectLater(pending, completes);
      expect(handler.handled, isEmpty);
    });

    test('a link emitted by a source flows through the pipeline', () async {
      final handler = RecordingHandler();
      final orchestrator = build(handler: handler);
      await orchestrator.initialize();

      await source.emit(rawIntent('myapp://product/1'));

      expect(handler.handled, [Uri.parse('myapp://product/1')]);
      await orchestrator.dispose();
    });
  });
}
