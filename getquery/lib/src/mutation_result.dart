// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/foundation.dart';
import 'package:flutter_query/flutter_query.dart' as fq;
import 'package:get/get.dart';

/// Rx-backed wrapper around flutter_query's [fq.MutationResult].
///
/// Type params simplified to 2 (error and onMutate context are [dynamic]):
/// - [TData]      — type returned by the mutation on success.
/// - [TVariables] — type of the variables passed to [mutate]/[mutateAsync].
///
/// Use [Obx] to rebuild on state changes:
/// ```dart
/// Obx(() => ElevatedButton(
///   onPressed: mutation.isPending ? null : () => mutation.mutate(req),
///   child: mutation.isPending
///       ? const CircularProgressIndicator()
///       : const Text('Submit'),
/// ))
/// ```
class MutationResult<TData, TVariables> {
  MutationResult();

  final _rx =
      Rx<fq.MutationResult<TData, dynamic, TVariables, dynamic>?>(null);

  // ── Status ────────────────────────────────────────────────────────────────

  bool get isIdle    => _rx.value == null || _rx.value!.isIdle;
  bool get isPending => _rx.value?.isPending ?? false;
  bool get isSuccess => _rx.value?.isSuccess ?? false;
  bool get isError   => _rx.value?.isError   ?? false;
  bool get isPaused  => _rx.value?.isPaused  ?? false;

  // ── Data / Error ──────────────────────────────────────────────────────────

  TData?      get data         => _rx.value?.data;
  Object?     get error        => _rx.value?.error;
  TVariables? get variables    => _rx.value?.variables;
  int         get failureCount => _rx.value?.failureCount ?? 0;

  // ── Actions — wired to MutationObserver on mount ──────────────────────────

  /// Fire-and-forget. Errors are captured in [error], not thrown.
  late void Function(TVariables variables) mutate;

  /// Awaitable. Throws on failure.
  late Future<TData> Function(TVariables variables) mutateAsync;

  /// Reset mutation state back to idle.
  late void Function() reset;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @internal
  VoidCallback? disposeCallback;

  void dispose() => disposeCallback?.call();

  // ── Internal ──────────────────────────────────────────────────────────────

  @internal
  void update(fq.MutationResult<TData, dynamic, TVariables, dynamic> r) =>
      _rx.value = r;
}
