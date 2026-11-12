# cacheman_example

Runnable demo app for the [`cacheman`](../README.md) package (0.7.0). It depends on the package
through `path: ..`.

```bash
flutter pub get
flutter run -d chrome   # or any other Flutter device
```

Pages: basic CRUD, TTL & expiry, batch & fast accessors, namespaces, debug & Jsonx, layered
storage (`Cacheman` + `AsyncCacheman` + `Cacheman.custom`), shared Hub (`watch`, `flushDelay`,
`flush`, `purgeOnInit`), and types & errors (`ValueAdapter`, `CachemanError`).
Everything runs offline; data persists through `get_storage` (localStorage on web).

/ cacheman 包的可运行示例（0.7.0），通过 `path: ..` 依赖本包；各页覆盖见上。全部离线可跑，
数据经 `get_storage` 持久化（web 为 localStorage）。
