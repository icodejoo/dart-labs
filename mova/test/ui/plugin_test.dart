import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/ui/scope/plugin.dart';
import 'package:mova/src/ui/scope/scope.dart';

import '../support/fake_api.dart';

/// A minimal [MovaPlugin] host: binds to [stream] in initState and records
/// every event, and captures the resolved [api] for assertions.
///
/// 最小 [MovaPlugin] 宿主：在 initState 绑定 [stream] 并记录每个事件，同时
/// 捕获解析出的 [api] 供断言。
class _Host extends StatefulWidget {
  const _Host({required this.stream, required this.received});
  final Stream<int> stream;
  final List<int> received;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with MovaPlugin<_Host> {
  MovaApi? seenApi;
  @override
  void initState() {
    super.initState();
    seenApi = api; // resolves via MovaScope.readOf — safe in initState
    bind(widget.stream, widget.received.add);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('bind receives events and api resolves from the enclosing scope',
      (t) async {
    final api = FakeMovaApi();
    final controller = StreamController<int>.broadcast();
    final received = <int>[];
    _HostState state() => t.state<_HostState>(find.byType(_Host));

    await t.pumpWidget(MovaScope(
      api: api,
      child: _Host(stream: controller.stream, received: received),
    ));

    expect(state().seenApi, same(api));
    expect(controller.hasListener, isTrue);

    controller.add(1);
    controller.add(2);
    await t.pump();
    expect(received, [1, 2]);

    await controller.close();
    await api.dispose();
  });

  testWidgets('dispose cancels every bound subscription', (t) async {
    final api = FakeMovaApi();
    final controller = StreamController<int>.broadcast();
    final received = <int>[];

    await t.pumpWidget(MovaScope(
      api: api,
      child: _Host(stream: controller.stream, received: received),
    ));
    expect(controller.hasListener, isTrue);

    // Replace the host with an empty tree → its State is disposed.
    // 用空树替换宿主 → 其 State 被 dispose。
    await t.pumpWidget(const SizedBox.shrink());

    expect(controller.hasListener, isFalse); // subscription was cancelled
    controller.add(99);
    await t.pump();
    expect(received, isEmpty); // nothing arrives after dispose

    await controller.close();
    await api.dispose();
  });
}
