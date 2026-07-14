import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import 'package:http/http.dart' as http;

class QueryPage extends StatefulWidget {
  const QueryPage({super.key});
  @override
  State<QueryPage> createState() => _QueryPageState();
}

class _QueryPageState extends State<QueryPage> {
  late final QueryResult<List<dynamic>> _posts;
  late final RxBool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = true.obs;
    _posts = useQuery<List<dynamic>>(
      queryKey: ['posts'],
      queryFn: (ctx) async {
        final res = await http.get(
          Uri.parse('https://jsonplaceholder.typicode.com/posts?_limit=10'),
        );
        return jsonDecode(res.body) as List;
      },
      enabled: _enabled,
      refetchOnMount: RefetchOnMount.always,
    );
  }

  @override
  void dispose() {
    _posts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('useQuery')),
      body: Obx(() {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _posts.isFetching ? null : _posts.refetch,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refetch'),
                  ),
                  const SizedBox(width: 16),
                  if (_posts.isFetching)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const Spacer(),
                  const Text('Enabled'),
                  Switch(
                    value: _enabled.value,
                    onChanged: (v) => _enabled.value = v,
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        );
      }),
    );
  }

  Widget _buildBody() {
    if (_posts.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error: ${_posts.error}'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _posts.refetch, child: const Text('Retry')),
          ],
        ),
      );
    }
    final posts = _posts.data ?? [];
    return ListView.builder(
      itemCount: posts.length,
      itemBuilder: (ctx, i) {
        final post = posts[i] as Map<String, dynamic>;
        return ListTile(
          leading: CircleAvatar(child: Text('${post['id']}')),
          title: Text(post['title'] as String),
        );
      },
    );
  }
}
