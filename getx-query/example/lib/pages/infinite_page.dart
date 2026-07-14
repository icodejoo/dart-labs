import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import 'package:http/http.dart' as http;

class InfinitePage extends StatefulWidget {
  const InfinitePage({super.key});
  @override
  State<InfinitePage> createState() => _InfinitePageState();
}

class _InfinitePageState extends State<InfinitePage> {
  late final InfiniteQueryResult<List<dynamic>, int> _infinite;

  @override
  void initState() {
    super.initState();
    _infinite = useInfiniteQuery<List<dynamic>, int>(
      queryKey: ['posts', 'infinite'],
      initialPageParam: 1,
      queryFn: (ctx) async {
        final res = await http.get(Uri.parse(
          'https://jsonplaceholder.typicode.com/posts?_page=${ctx.pageParam}&_limit=5',
        ));
        return jsonDecode(res.body) as List;
      },
      nextPageParamBuilder: (data) =>
          data.pages.isEmpty || data.pages.last.isEmpty
              ? null
              : data.pages.length + 1,
    );
  }

  @override
  void dispose() {
    _infinite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('useInfiniteQuery')),
      body: Obx(() {
        if (_infinite.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_infinite.isError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Error: ${_infinite.error}'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _infinite.refetch,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final allPosts = [
          for (final page in _infinite.pages) ...page,
        ];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Pages loaded: ${_infinite.pages.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (_infinite.isFetching && !_infinite.isFetchingNextPage)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: allPosts.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == allPosts.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: _infinite.isFetchingNextPage
                          ? const Center(child: CircularProgressIndicator())
                          : FilledButton(
                              onPressed: _infinite.hasNextPage
                                  ? _infinite.fetchNextPage
                                  : null,
                              child: Text(
                                _infinite.hasNextPage
                                    ? 'Load more'
                                    : 'No more pages',
                              ),
                            ),
                    );
                  }
                  final post = allPosts[i] as Map<String, dynamic>;
                  return ListTile(
                    leading: CircleAvatar(child: Text('${post['id']}')),
                    title: Text(post['title'] as String),
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
