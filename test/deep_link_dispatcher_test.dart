import 'package:deep_link_orchestrator/deep_link_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late InMemoryDeepLinkPendingStore store;
  late MutableAuthPolicy auth;

  DeepLinkHandlerContext contextOf() =>
      DeepLinkHandlerContext(pendingStore: store, authPolicy: auth);

  setUp(() {
    store = InMemoryDeepLinkPendingStore();
    auth = MutableAuthPolicy();
  });

  test('routes an intent to the handler registered for its type', () async {
    final handler = RecordingHandler();
    final dispatcher = DeepLinkDispatcher(
      handlers: {RawDeepLinkIntent: handler},
    );

    final result = await dispatcher.dispatch(
      intent: rawIntent('myapp://product/1'),
      context: contextOf(),
    );

    expect(result, DeepLinkDispatchResult.handled);
    expect(handler.handled, [Uri.parse('myapp://product/1')]);
  });

  test(
    'reports noHandler instead of throwing for an unroutable type',
    () async {
      final result = await DeepLinkDispatcher().dispatch(
        intent: rawIntent('myapp://product/1'),
        context: contextOf(),
      );

      expect(result, DeepLinkDispatchResult.noHandler);
    },
  );

  test('defers and stores the uri when auth is required but absent', () async {
    auth.isAuthenticated = false;
    final handler = RecordingHandler(requiresAuthentication: true);
    final dispatcher = DeepLinkDispatcher(
      handlers: {RawDeepLinkIntent: handler},
    );

    final result = await dispatcher.dispatch(
      intent: rawIntent('myapp://invite/1'),
      context: contextOf(),
    );

    expect(result, DeepLinkDispatchResult.authDeferred);
    expect(result.isDeferred, isTrue);
    expect(store.readPending(), Uri.parse('myapp://invite/1'));
    expect(handler.handled, isEmpty);
  });

  test('runs a gated handler once the session is authenticated', () async {
    final handler = RecordingHandler(requiresAuthentication: true);
    final dispatcher = DeepLinkDispatcher(
      handlers: {RawDeepLinkIntent: handler},
    );

    final result = await dispatcher.dispatch(
      intent: rawIntent('myapp://invite/1'),
      context: contextOf(),
    );

    expect(result, DeepLinkDispatchResult.handled);
    expect(store.readPending(), isNull);
  });

  test('lets a handler exception propagate to the orchestrator', () async {
    final dispatcher = DeepLinkDispatcher(
      handlers: {RawDeepLinkIntent: RecordingHandler(throws: true)},
    );

    expect(
      () => dispatcher.dispatch(
        intent: rawIntent('myapp://product/1'),
        context: contextOf(),
      ),
      throwsStateError,
    );
  });

  test('registerHandlers replaces the previous registration', () async {
    final first = RecordingHandler();
    final second = RecordingHandler();
    final dispatcher = DeepLinkDispatcher(handlers: {RawDeepLinkIntent: first});

    dispatcher.registerHandlers({RawDeepLinkIntent: second});
    await dispatcher.dispatch(
      intent: rawIntent('myapp://product/1'),
      context: contextOf(),
    );

    expect(first.handled, isEmpty);
    expect(second.handled, hasLength(1));
  });

  test('TypedDeepLinkHandler rejects an intent of another type', () {
    expect(RecordingHandler().canHandle(_OtherIntent()), isFalse);
    expect(RecordingHandler().canHandle(rawIntent('myapp://a')), isTrue);
  });
}

class _OtherIntent extends DeepLinkIntent {
  _OtherIntent() : super(sourceId: 'test', uri: Uri.parse('myapp://other'));
}
