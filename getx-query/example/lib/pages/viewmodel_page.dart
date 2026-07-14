import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import 'package:http/http.dart' as http;

class PostsViewModel extends GetBaseViewModel {
  late final QueryResult<List<dynamic>> posts;
  late final MutationResult<Map<String, dynamic>, String> deletePost;
  final selectedId = RxnInt();

  @override
  void onInit() {
    super.onInit();
    posts = useQuery<List<dynamic>>(
      queryKey: ['vm', 'posts'],
      queryFn: (ctx) async {
        final res = await http.get(
          Uri.parse('https://jsonplaceholder.typicode.com/posts?_limit=8'),
        );
        return jsonDecode(res.body) as List;
      },
    );
    deletePost = useMutation<Map<String, dynamic>, String>(
      (id, ctx) async {
        await http.delete(
          Uri.parse('https://jsonplaceholder.typicode.com/posts/$id'),
        );
        return {'id': id, 'deleted': true};
      },
      onSuccess: (data, vars, onMutateResult, ctx) =>
          invalidateQueries(queryKey: ['vm', 'posts']),
    );
  }
}

class ViewModelPage extends StatefulWidget {
  const ViewModelPage({super.key});
  @override
  State<ViewModelPage> createState() => _ViewModelPageState();
}

class _ViewModelPageState extends State<ViewModelPage> {
  @override
  void initState() {
    super.initState();
    Get.put(PostsViewModel());
  }

  @override
  void dispose() {
    Get.delete<PostsViewModel>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = Get.find<PostsViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('GetBaseViewModel')),
      body: Obx(() {
        if (vm.posts.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.posts.isError) {
          return Center(
            child: Text('Error: ${vm.posts.error}'),
          );
        }
        final items = vm.posts.data ?? [];
        return Column(
          children: [
            if (vm.deletePost.isPending)
              const LinearProgressIndicator(),
            if (vm.deletePost.isSuccess)
              MaterialBanner(
                content: Text('Deleted id: ${vm.deletePost.data?['id']}'),
                actions: [
                  TextButton(
                    onPressed: vm.deletePost.reset,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            if (vm.deletePost.isError)
              MaterialBanner(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                content: Text('Delete failed: ${vm.deletePost.error}'),
                actions: [
                  TextButton(
                    onPressed: vm.deletePost.reset,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final post = items[i] as Map<String, dynamic>;
                  final id = post['id'].toString();
                  return ListTile(
                    leading: CircleAvatar(child: Text(id)),
                    title: Text(post['title'] as String),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: vm.deletePost.isPending
                          ? null
                          : () => vm.deletePost.mutate(id),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}
