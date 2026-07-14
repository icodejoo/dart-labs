import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import 'package:http/http.dart' as http;

class QueriesPage extends StatefulWidget {
  const QueriesPage({super.key});
  @override
  State<QueriesPage> createState() => _QueriesPageState();
}

class _QueriesPageState extends State<QueriesPage> {
  late List<QueryResult> _results;
  late VoidCallback _disposeQueries;
  late RxInt _isFetchingCount;
  late VoidCallback _disposeIsFetching;

  @override
  void initState() {
    super.initState();
    final (results, _, dispose) = useQueries([
      QueryOptions(
        ['users'],
        (ctx) async {
          final res = await http.get(
            Uri.parse('https://jsonplaceholder.typicode.com/users?_limit=5'),
          );
          return jsonDecode(res.body) as List;
        },
      ),
      QueryOptions(
        ['posts', 'top'],
        (ctx) async {
          final res = await http.get(
            Uri.parse('https://jsonplaceholder.typicode.com/posts?_limit=5'),
          );
          return jsonDecode(res.body) as List;
        },
      ),
    ]);
    _results = results;
    _disposeQueries = dispose;
    final (isFetching, disposeIsFetching) = useIsFetching();
    _isFetchingCount = isFetching;
    _disposeIsFetching = disposeIsFetching;
  }

  @override
  void dispose() {
    _disposeQueries();
    _disposeIsFetching();
    super.dispose();
  }

  void _invalidateAll() {
    useQueryClient().invalidateQueries(queryKey: ['users']);
    useQueryClient().invalidateQueries(queryKey: ['posts', 'top']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('useQueries')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Obx(() => Text(
                      'Fetching: ${_isFetchingCount.value}',
                      style: Theme.of(context).textTheme.bodySmall,
                    )),
                const Spacer(),
                FilledButton(
                  onPressed: _invalidateAll,
                  child: const Text('Invalidate all'),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final wide = constraints.maxWidth >= 500;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildUsersList()),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildPostsList()),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: _buildUsersList()),
                    const Divider(height: 1),
                    Expanded(child: _buildPostsList()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    final result = _results[0];
    return Obx(() {
      if (result.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (result.isError) {
        return Center(child: Text('Users error: ${result.error}'));
      }
      final users = (result.data as List? ?? []).cast<Map<String, dynamic>>();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Users',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (ctx, i) => ListTile(
                dense: true,
                leading: CircleAvatar(child: Text(users[i]['name'][0] as String)),
                title: Text(users[i]['name'] as String),
                subtitle: Text(users[i]['email'] as String),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildPostsList() {
    final result = _results[1];
    return Obx(() {
      if (result.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (result.isError) {
        return Center(child: Text('Posts error: ${result.error}'));
      }
      final posts = (result.data as List? ?? []).cast<Map<String, dynamic>>();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Top Posts',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (ctx, i) => ListTile(
                dense: true,
                leading: CircleAvatar(child: Text('${posts[i]['id']}')),
                title: Text(posts[i]['title'] as String),
              ),
            ),
          ),
        ],
      );
    });
  }
}
