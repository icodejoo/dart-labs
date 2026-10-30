import 'package:dioman/dioman.dart';
import 'client.dart';

/// 核对阶段单调及名称唯一；固定阶段替代旧拓扑约束。
List<String> verifyPluginRules(ScenarioClient client) {
  final layers = client.api.inspect();
  final names = <String>{};
  var stage = DiomanStage.outer;
  for (final (current, name) in layers) {
    if (!names.add(name)) throw StateError('插件名重复：$name');
    if (current.index < stage.index) throw StateError('阶段逆序：$name');
    stage = current;
  }
  return [for (final (stage, name) in layers) '${stage.name}:$name'];
}
