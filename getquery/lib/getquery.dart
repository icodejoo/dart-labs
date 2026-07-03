/// getquery — TanStack-Query-style data fetching for GetX.
///
/// A thin, [Rx]-backed bridge over [`flutter_query`](https://pub.dev/packages/flutter_query):
/// use `useQuery` / `useMutation` from **any** function — no `HookWidget`, no
/// `BuildContext` — and render with `Obx`. Also ships `BaseViewModel` /
/// `GetBaseViewModel` that auto-track and dispose their subscriptions.
///
/// This barrel re-exports `flutter_query`'s public types (QueryClient,
/// StaleDuration, RetryResolver, ...) so you only import `getquery`. The
/// Hook-based symbols that getquery replaces are hidden.
library;

export 'package:flutter_query/flutter_query.dart'
    hide
        QueryResult,
        MutationResult,
        useQuery,
        useMutation,
        useQueryClient,
        useIsFetching,
        useIsMutating,
        useInfiniteQuery,
        useMutationState,
        QueryClientProvider;

export 'src/query_service.dart';
export 'src/query_result.dart';
export 'src/mutation_result.dart';
export 'src/use_query.dart';
export 'src/use_mutation.dart';
export 'src/watch.dart';
export 'src/base_view_model.dart' show BaseViewModel, GetBaseViewModel;
