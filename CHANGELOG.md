## 1.0.6

Breaking changes, so this should ship as a major version.

### Breaking

- `DeepLinkDeduplicationStrategy` now owns its state. `fingerprintOf` is
  replaced by `shouldProcess`, `forget`, and `reset`. Previously the
  orchestrator held a single fingerprint slot, so
  `DefaultDeepLinkDeduplicationStrategy` only ever remembered the most recent
  link despite documenting session-long deduplication: opening A, then B, then
  A again re-opened A.
- The default strategy is now a one-second
  `TimeWindowDeepLinkDeduplicationStrategy`. It absorbs platform double-fires
  without permanently blocking a link the user opens again later. Pass
  `DefaultDeepLinkDeduplicationStrategy()` to keep the previous behaviour.

### Added

- `TypedDeepLinkHandler<T>`, a handler bound to one intent type. Implement
  `onHandle(T intent, context)` and the type check and cast are handled.
- `DeepLinkIntent.dedupeKey`, the identity used for debouncing and
  deduplication. Override it to change what counts as the same link.
- `NoopDeepLinkDeduplicationStrategy` for apps that want every intent through.
- `DeepLinkValidator` gained `allowedSubdomains`, `additionalHosts`, and
  `allowRootPath`, and its `isSupportedHost` and `isSupportedPath` are now
  `@protected` rather than private. Widening the validator no longer requires
  copying its implementation.
- A test suite covering the pipeline, pending store lifecycle, deduplication,
  validation, and dispatch.

### Fixed

- Concurrent links are no longer dropped. A link arriving while another was
  being processed was previously discarded with a warning; links are now
  queued and processed in arrival order.
- `handleIntent` and `checkInitialIntent` return futures that complete once
  the intent has actually been processed, rather than once it has been
  scheduled.
- `dispose` completes any caller awaiting a debounced intent instead of
  leaving it hanging, and is safe to call more than once.
- An exception thrown from a custom policy no longer poisons the pipeline for
  every subsequent link.
- Dispatch logging no longer serialises every intent to JSON on the hot path.

## 1.0.1

- Fixed pubspec description length to comply with pub.dev requirements (60–180 characters).
- Added dartdoc comments to 100% of the public API surface across all library files.

## 1.0.0

- Initial release.
- Handler-based deep link orchestration with pluggable architecture.
- Abstract `DeepLinkIntent` base class for typed intent hierarchies.
- Optional `DeepLinkIntentResolver` to convert raw intents into concrete subtypes.
- Built-in `AppLinksDeepLinkSource` wrapping `app_links` v7.
- Debounce, deduplication, validation, and per-handler authentication gating.
- Extensible via `DeepLinkSource`, `DeepLinkHandler`, and policy interfaces.
