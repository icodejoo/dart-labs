## 0.1.0

- First release. A set of composable, self-contained [Dio] interceptor plugins,
  all extending a common `DioPlugin` base (a named `Interceptor` with `dispose`):
  - `EnvsPlugin` — per-environment `BaseOptions` applied at install time
  - `RepathPlugin` — path-variable substitution (`{id}` / `:id` / `[id]`)
  - `NormalizeRequestPlugin` — strip empty query/body fields
  - `BuildKeyPlugin` — compute a per-request key for cache/share
  - `NormalizePlugin` — unwrap `{code,data,message}` envelopes; reject on error
  - `CachePlugin` — TTL response cache with clone strategies
  - `SharePlugin` — dedup concurrent requests (`start`/`end`/`race`/`retry`)
  - `MockPlugin` — route-based mock with real-API fallback
  - `CancelPlugin` — inject `CancelToken`s and `cancelAll`
  - `LoadingPlugin` — in-flight counter for a global loading indicator
  - `AuthPlugin` — token injection + single-window 401 refresh/replay
  - `RetryPlugin` — retry network (and optionally business) failures
  - `LogPlugin` — dependency-free request/response/error logging
- Documented the recommended install order (Dio runs interceptors in forward
  order for all of onRequest/onResponse/onError) and its trade-offs.
