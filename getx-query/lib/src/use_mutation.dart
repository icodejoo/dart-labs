// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter_query/flutter_query.dart'
    hide MutationResult, useQuery, useQueryClient, QueryResult,
        QueryClientProvider, useInfiniteQuery, useIsFetching, useIsMutating,
        useMutationState, useMutation;
import 'package:flutter_query/src/core/mutation_observer.dart';
import 'package:get/get.dart';

import 'mutation_result.dart';
import 'query_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// useMutation
// ─────────────────────────────────────────────────────────────────────────────

/// Perform create / update / delete operations with full reactive state.
///
/// Unlike [useQuery] which fetches automatically, the mutation is triggered
/// imperatively via [MutationResult.mutate] or [MutationResult.mutateAsync].
///
/// ```dart
/// final createDeposit = useMutation<Deposit, DepositRequest>(
///   (req, _) => DepositApi.create(req),
///   onSuccess: (data, _, __) {
///     useQueryClient().invalidateQueries(queryKey: ['deposit', 'list']);
///   },
/// );
///
/// // In widget:
/// Obx(() => ElevatedButton(
///   onPressed: createDeposit.isPending
///       ? null
///       : () => createDeposit.mutate(DepositRequest(...)),
///   child: const Text('Submit'),
/// ))
///
/// // Async form:
/// final deposit = await createDeposit.mutateAsync(DepositRequest(...));
/// ```
MutationResult<TData, TVariables>
    useMutation<TData, TVariables>(
  MutateFn<TData, TVariables> mutationFn, {
  QueryClient? client,
  MutationOnMutate<TVariables, dynamic>? onMutate,
  MutationOnSuccess<TData, TVariables, dynamic>? onSuccess,
  MutationOnError<dynamic, TVariables, dynamic>? onError,
  MutationOnSettled<TData, dynamic, TVariables, dynamic>? onSettled,
  List<Object?>? mutationKey,
  GcDuration? gcDuration,
  RetryResolver? retry,
  NetworkMode? networkMode,
  Map<String, dynamic>? meta,
}) {
  final resolvedClient = client ?? Get.find<QueryService>().client;

  final observer = MutationObserver<TData, dynamic, TVariables, dynamic>(
    resolvedClient,
    MutationOptions<TData, dynamic, TVariables, dynamic>(
      mutationFn:  mutationFn,
      onMutate:    onMutate,
      onSuccess:   onSuccess,
      onError:     onError,
      onSettled:   onSettled,
      mutationKey: mutationKey,
      gcDuration:  gcDuration,
      retry:       retry,
      networkMode: networkMode,
      meta:        meta,
    ),
  );

  observer.onMount();

  final result = MutationResult<TData, TVariables>();
  result.update(observer.result);
  result.mutateImpl      = observer.mutate;
  result.mutateAsyncImpl = observer.mutateAsync;
  result.resetImpl       = observer.reset;

  final unsubscribe = observer.subscribe(result.update);

  result.disposeCallback = () {
    unsubscribe();
    observer.onUnmount();
  };

  return result;
}
