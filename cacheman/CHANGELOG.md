## 0.2.0

**Breaking:**

- `ss` in-memory tier removed; only the persistent `ls` tier remains. `Cacheman.create()` no
  longer accepts a `cap` parameter, and `Cacheman.ss`/`Memory` no longer exist.
- `Engine`'s core CRUD methods renamed: `get`/`getAll` → `read`/`readAll`, `set`/`setAll` →
  `write`/`writeAll`, `clear` → `erase`. `remove`/`removeAll` are unchanged.
- `Cacheman.ls` removed. `Cacheman` now exposes `Engine`'s whole public API directly at the top
  level (`read`/`readAll`, `write`/`writeAll`, `remove`/`removeAll`, `erase`, `key`/`keys`/`length`/
  `purge`/`namespace`) — call `cache.write(...)`/`cache.read(...)` etc. instead of
  `cache.ls.write(...)`/`cache.ls.read(...)`. `fast`/`lazy`/`batchFast`/`debug()` now take a
  `Cacheman` instead of an `Engine` (`fast<String>(cache, 'token')`, `debug(cache)`).

## 0.1.0

Initial version — a `get_storage`-backed persistent tier (`ls`) plus a pure in-memory tier (`ss`),
sharing one engine: TTL & absolute expiry, sliding renewal, namespaces, pluggable serialization, an
optional `Codec` hook (no implementation shipped), batch get/set/remove, `raw`/`readonly` modes,
`fast`/`lazy`/`batchFast` key-bound accessors, a `debug()` snapshot helper, an optional `ss` capacity cap
(`cap`, FIFO eviction), and a generic `Jsonx` serializer round-tripping `DateTime`/`Duration`/`Set`/
`BigInt`/`Uri`/`RegExp`. The Dart/Flutter sibling of `@codejoo/storage`.
