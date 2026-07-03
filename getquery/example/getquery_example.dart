import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getquery/getquery.dart';

// A fake API for the example.
class Api {
  static int _n = 0;
  static Future<List<String>> todos(String filter) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.generate(3, (i) => '$filter todo #$i');
  }

  static Future<String> addTodo(String title) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return 'added: $title (#${++_n})';
  }
}

void main() {
  runApp(
    GetMaterialApp(
      // Register the shared QueryClient (wired to connectivity_plus).
      initialBinding: BindingsBuilder(() {
        Get.put<QueryService>(QueryService(), permanent: true);
      }),
      home: const TodoPage(),
    ),
  );
}

// ── ViewModel ──────────────────────────────────────────────────────────────
// GetBaseViewModel auto-disposes every useQuery / useMutation on onClose.
class TodoViewModel extends GetBaseViewModel {
  final filter = 'all'.obs;

  // Rx in the queryKey → auto-refetches when `filter` changes.
  late final QueryResult<List<String>> todos = useQuery(
    ['todos', filter],
    (_) => Api.todos(filter.value),
    staleDuration: StaleDuration(minutes: 5),
    placeholder: const [],
  );

  // Imperative mutation with reactive state; refresh the list on success.
  late final MutationResult<String, String> addTodo = useMutation(
    (title, _) => Api.addTodo(title),
    onSuccess: (_, __, ___, ____) => invalidateQueries(queryKey: ['todos']),
  );
}

// ── UI ─────────────────────────────────────────────────────────────────────
class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = Get.put(TodoViewModel());

    return Scaffold(
      appBar: AppBar(title: const Text('getquery example')),
      body: Obx(() {
        if (vm.todos.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.todos.isError) {
          return Center(child: Text('Error: ${vm.todos.error}'));
        }
        final items = vm.todos.data ?? const [];
        return RefreshIndicator(
          onRefresh: vm.todos.refetch,
          child: ListView(
            children: [
              for (final t in items) ListTile(title: Text(t)),
            ],
          ),
        );
      }),
      floatingActionButton: Obx(() => FloatingActionButton(
            onPressed: vm.addTodo.isPending
                ? null
                : () => vm.addTodo.mutate('new'),
            child: vm.addTodo.isPending
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.add),
          )),
    );
  }
}
