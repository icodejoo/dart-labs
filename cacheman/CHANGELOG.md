## 0.1.0

Initial version — a `get_storage`-backed persistent tier (`ls`) plus a pure in-memory tier (`ss`),
sharing one engine: TTL & absolute expiry, sliding renewal, namespaces, pluggable serialization, an
optional `Codec` hook (no implementation shipped), batch get/set/remove, `raw`/`readonly` modes,
`fast`/`lazy`/`batchFast` key-bound accessors, a `debug()` snapshot helper, an optional `ss` capacity cap
(`cap`, FIFO eviction), and a generic `Jsonx` serializer round-tripping `DateTime`/`Duration`/`Set`/
`BigInt`/`Uri`/`RegExp`. The Dart/Flutter sibling of `@codejoo/storage`.
