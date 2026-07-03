## 0.1.0

- First release. An [Rx]-backed bridge that brings
  [`flutter_query`](https://pub.dev/packages/flutter_query) to GetX:
  - `useQuery` / `useQueries` / `useQueryClient` — call from any function, render with `Obx`
  - `useMutation` — imperative create/update/delete with reactive `isPending`/`isSuccess`/`isError`
  - Reactive params: pass `Rx` values in `queryKey` or `enabled` for auto re-fetch
  - `QueryResult` / `MutationResult` — `Rx`-backed result wrappers
  - `watchQuery` (record API) and `QueryScope` (grouped lifecycle)
  - `BaseViewModel` (constructor-injected client) and `GetBaseViewModel`
    (GetxController) that auto-track and dispose subscriptions
  - `QueryService` — a `GetxService` `QueryClient` wired to `connectivity_plus`
    for `refetchOnReconnect`
  - Barrel re-exports `flutter_query`'s public types (single import).
