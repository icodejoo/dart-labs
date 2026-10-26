## Unreleased

- Add pluggable storage: `XlruStore` (sync) and `XlruAsyncStore` (async)
  interfaces, the in-memory `XlruMemoryStore`, and `XlruStoreAsAsync.asAsync()`
  to use a sync store as an async one.
- `XlruCache` accepts an optional `store`. Without one it behaves and performs
  as before.
- Add `XlruAsyncCache` for async stores: per-key ordering, `putIfAbsent` with
  concurrent-load deduplication, `onError` for store failures, and
  `XlruAsyncRemovalListener` with a lazy `loadValue`.
- Add `XlruStoreOperation` and `XlruStoreErrorListener`.

## 0.1.0

- Introduce a zero-dependency LRU cache (`XlruCache`, `XlruRemovalCause`, `XlruRemovalListener`). `XlruCache` is a `final class`.
- Add reason-aware, reentrant removal callbacks with batch error handling.
- Support reference-counted pins, immediate resizing, and non-promoting lookups.
- Provide ordered, fail-fast iteration and custom key equality.
- Protect the entry written by `set`/`putIfAbsent` from that call's eviction;
  opt into pure LRU order with `allowSelfEviction: true`.
- Add `usePinned`, a scoped pin that always unpins.
- Reserve `XlruRemovalCause.lost` for storage-backed caches, so adding backends
  later does not break exhaustive `switch`es.
- Skip removal bookkeeping when no `onRemove` listener is set.
- Store entries in slot arrays behind an open-addressing index: steady-state
  writes allocate nothing without a listener and hot paths carry no runtime type checks, keeping
  AOT, dart2js, and dart2wasm builds fast.
