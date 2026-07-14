import 'dart:convert' show jsonDecode, jsonEncode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import 'package:http/http.dart' as http;

class MutationPage extends StatefulWidget {
  const MutationPage({super.key});
  @override
  State<MutationPage> createState() => _MutationPageState();
}

class _MutationPageState extends State<MutationPage> {
  late final MutationResult<Map<String, dynamic>, Map<String, dynamic>> _create;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _create = useMutation<Map<String, dynamic>, Map<String, dynamic>>(
      (vars, ctx) async {
        final res = await http.post(
          Uri.parse('https://jsonplaceholder.typicode.com/posts'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(vars),
        );
        return jsonDecode(res.body) as Map<String, dynamic>;
      },
      onSuccess: (data, vars, onMutateResult, ctx) {
        useQueryClient().invalidateQueries(queryKey: ['posts']);
      },
    );
  }

  @override
  void dispose() {
    _create.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) return;
    _create.mutate({'title': title, 'body': body, 'userId': 1});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('useMutation')),
      body: Obx(() {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Post title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              decoration: const InputDecoration(
                labelText: 'Post body',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  onPressed: _create.isPending ? null : _submit,
                  child: _create.isPending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Post'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _create.isIdle ? null : _create.reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildStatus(),
          ],
        );
      }),
    );
  }

  Widget _buildStatus() {
    if (_create.isIdle) {
      return const Text('Status: idle', style: TextStyle(color: Colors.grey));
    }
    if (_create.isPending) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Creating...'),
        ],
      );
    }
    if (_create.isError) {
      return Text(
        'Error: ${_create.error}',
        style: const TextStyle(color: Colors.red),
      );
    }
    final data = _create.data;
    if (data != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Created! id: ${data['id']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('Title: ${data['title']}'),
              if (data['body'] != null && (data['body'] as String).isNotEmpty)
                Text('Body: ${data['body']}'),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
