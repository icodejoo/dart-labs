## 0.1.0

- Introduce a zero-dependency, hash-map and doubly linked list LRU cache.
- Add reason-aware, reentrant removal callbacks with batch error handling.
- Support reference-counted pins, immediate resizing, and non-promoting lookups.
- Provide ordered, fail-fast iteration and custom key equality.
- Protect the entry written by `set`/`putIfAbsent` from that call's eviction;
  opt into strict LRU with `allowSelfEviction: true`.
- Skip removal bookkeeping when no `onRemove` listener is set.
- Store entries in slot arrays behind an open-addressing index: steady-state
  writes allocate nothing and hot paths carry no runtime type checks, keeping
  AOT, dart2js, and dart2wasm builds fast.
