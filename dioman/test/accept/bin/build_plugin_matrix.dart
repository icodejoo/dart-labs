// ignore_for_file: avoid_relative_lib_imports
// test/accept/lib 是仓库内执行器源码，按目标目录使用相对导入。
import '../lib/literals.dart';
import 'dart:convert';
import 'dart:io';
import '../lib/common.dart';
import '../lib/pairwise.dart';

/// B7 共用字面量。
const _b7Literal0 = 'normal@http';

/// B7 共用字面量。
const _b7Literal1 = 'normal@business';

/// main 的测试辅助入口。
/// 人读矩阵和中立场景共用的源清单，生成过程不连接服务。
void main() {
  final names = capabilities.toList()..sort();
  final cases = <Map<String, dynamic>>[];
  final manifest = <Map<String, dynamic>>[];

  /// 同时登记场景与方法归属，防止文档列数和执行计划分离。
  /// add 的测试辅助入口。
  void add(String id, String method, Map<String, dynamic> plugins,
      List<dynamic> steps, Map<String, dynamic> expect,
      {List<String> networks = const [tkNormal], String? purpose}) {
    final scenarioId = 'plugins.$id';
    cases.add({
      tkId: scenarioId,
      tkTitle: purpose ?? id,
      tkWhy: purpose ?? '验证 $method 下插件组合的真实响应及资源释放。',
      tkRequires: {
        ...plugins.keys,
        if (usesScenarioCancellation(steps)) tkCancel,
        if (id.startsWith('single-') && !plugins.containsKey(tkNormalize))
          rawBusinessCodeCapability,
      }.toList(),
      tkNetworks: networks,
      tkClient: {tkPlugins: plugins},
      tkSteps: steps,
      tkExpect: expect,
      tkTimeoutMs: 40000,
    });
    manifest.add({
      tkScenario: scenarioId,
      tkMethod: method,
      tkPlugins: plugins.keys.toList(),
      tkNetworks: networks,
      'purpose': purpose ?? id,
    });
  }

  /// 普通回显请求使用服务端负载作为独立成功证据。
  /// echo 的测试辅助入口。
  Map<String, dynamic> echo(String id,
          {Map<String, dynamic>? query,
          Map<String, dynamic>? options,
          int? cancel}) =>
      {
        tkRequest: {
          tkId: id,
          tkPath: tkTEcho,
          tkQuery: {
            tkData: jsonEncode({tkMatrix: true}),
            ...?query
          },
          tkOptions: {tkMock: false, ...?options},
          if (cancel != null) tkCancelAfterMs: cancel,
        },
      };

  /// 成功断言同时核对负载；全局解释器另检查 loading 和在途资源。
  /// success 的测试辅助入口。
  Map<String, dynamic> success(String id) => {
        id: {
          tkOk: true,
          tkData: {
            tkPayload: {tkMatrix: true}
          }
        },
      };

  for (final name in names) {
    add(
        'single-$name',
        '单体',
        {name: <String, dynamic>{}},
        [
          echo(tkOk, options: {tkKey: name == tkKey}),
          echo(tkError,
              query: {tkStatus: 500, tkCode: 500},
              options: {tkKey: false, tkCache: false}),
          echo(tkCancel,
              query: {tkDelayMs: 300},
              cancel: 10,
              options: {tkKey: false, tkCache: false}),
        ],
        {
          tkNormal: {
            tkResults: {
              ...success(tkOk),
              // 只有 normalize 转换一般业务失败；其余单开依赖业务码透传能力。
              tkCancel: {tkOk: false, tkError: tkCanceled},
            }
          },
          _b7Literal0: {
            tkResults: {
              tkError: {tkOk: false, tkError: tkStatus500}
            }
          },
          _b7Literal1: {
            tkResults: {
              tkError: name == tkNormalize
                  ? {tkOk: false, tkError: tkStatus500}
                  : {tkOk: true},
            }
          },
        },
        purpose: '$name 单独启用：成功、500、主动取消；不代表全部公开选项已覆盖。');
    if (name != tkNormalize) {
      final business = cases.last;
      final http = <String, dynamic>{
        ...business,
        tkId: '${business[tkId]}-http',
        tkStyles: [tkHttp],
        tkRequires: (business[tkRequires] as List)
            .where((cap) => cap != rawBusinessCodeCapability)
            .toList(),
        tkExpect: {...business[tkExpect] as Map}..remove(_b7Literal1),
      };
      business[tkStyles] = [tkBusiness];
      (business[tkExpect] as Map).remove(_b7Literal0);
      manifest.last[tkStyles] = [tkBusiness];
      manifest.add({
        ...manifest.last,
        tkScenario: http[tkId],
        tkStyles: [tkHttp]
      });
      cases.add(http);
    }
  }

  final rows = binaryPairs(names.length);
  for (var row = 0; row < rows.length; row++) {
    final plugins = <String, dynamic>{
      for (var i = 0; i < names.length; i++)
        if (rows[row][i]) names[i]: <String, dynamic>{},
    };
    add(
        'pair-$row',
        '配对',
        plugins,
        [
          echo(tkPair, options: {tkKey: plugins.containsKey(tkKey)})
        ],
        {
          tkNormal: {
            tkResults: success(tkPair),
            tkServer: {
              tkTotal: {tkEq: 1}
            }
          },
        },
        purpose: '二元正交数组第 $row 行；17 个开关（含全部关闭基线）。');
    manifest.last['switches'] = {
      for (var i = 0; i < names.length; i++) names[i]: rows[row][i]
    };
    // 关闭状态也是配对方法中该插件的一格。
    manifest.last[tkPlugins] = names;
  }

  // 中立映射可表达的数值边界；未映射的原生公开选项另列为待补，不能伪造不适用。
  final boundaries = <String, Map<String, List<dynamic>>>{
    tkRetry: {
      tkMax: [0, 1, 5],
      tkDelayMs: [0, 1],
      tkMethods: [
        <String>[],
        [tkGET]
      ]
    },
    tkCache: {
      tkTtlMs: [0, 1, 2147483647],
      tkMax: [0, 1, 64],
      tkMethods: [
        <String>[],
        [tkGET]
      ]
    },
    tkLoading: {
      tkDelayMs: [0, 1],
      tkDelayCloseMs: [0, 1]
    },
    tkTimeout: {
      tkConnectMs: [1, 2147483647],
      tkReceiveMs: [1, 2147483647]
    },
    tkBreaker: {
      tkThreshold: [1, 64],
      tkOpenMs: [0, 1, 2147483647]
    },
  };
  for (final plugin in boundaries.entries) {
    for (final option in plugin.value.entries) {
      for (var index = 0; index < option.value.length; index++) {
        final value = option.value[index];
        final tinyTimeout = plugin.key == tkTimeout && value == 1;
        add(
            'boundary-${plugin.key}-${option.key.replaceAll(tkUnderscore, '-')}-$index',
            '边界',
            {
              plugin.key: {option.key: value},
            },
            [echo(tkBoundary)],
            {
              tkNormal: {
                tkResults: tinyTimeout
                    ? {
                        // 极短真实传输预算允许抢先超时，成功时仍须校验真实负载。
                        tkBoundary: {
                          tkError: [tkTimeout]
                        },
                      }
                    : success(tkBoundary)
              },
            },
            purpose: '${plugin.key}.${option.key} = $value');
        if (tinyTimeout) {
          cases.last[tkSteps] = [
            echo(tkBoundary, query: {tkDelayMs: 50})
          ];
          if (option.key == tkConnectMs) {
            // 本地 TCP 通常在 1ms 内建立，不能用服务处理延迟断言连接超时。
            cases.last[tkExpect] = {
              tkNormal: {tkResults: success(tkBoundary)}
            };
          }
        }
      }
    }
  }

  final all = {for (final name in names) name: <String, dynamic>{}};
  all[tkRetry] = {tkMax: 3, tkDelayMs: 50};
  all[tkBreaker] = {tkThreshold: 64};
  final requests = [
    {
      tkLogin: {tkUser: 'plugin-matrix'}
    },
    {
      tkRequest: {
        tkId: tkAccess,
        tkPath: tkTPrivateMe,
        tkOptions: {tkMock: false}
      }
    },
    {tkExpireLocal: <String, dynamic>{}},
    {
      tkRequest: {
        tkId: tkRefresh,
        tkPath: tkTPrivateMe,
        tkOptions: {tkMock: false, tkCache: false}
      }
    },
    echo(tkRetry, query: {tkKey: 'matrix-retry', tkFailTimes: 1}),
    echo(tkCacheFirst,
        query: {tkKey: tkMatrixCache}, options: {tkKey: tkMatrixCache}),
    echo(tkCacheHit,
        query: {tkKey: tkMatrixCache}, options: {tkKey: tkMatrixCache}),
    {
      tkParallel: [
        echo(tkShareA,
            query: {tkKey: tkMatrixShare, tkDelayMs: 100},
            options: {tkKey: tkMatrixShare, tkCache: false}),
        echo(tkShareB,
            query: {tkKey: tkMatrixShare, tkDelayMs: 100},
            options: {tkKey: tkMatrixShare, tkCache: false}),
      ]
    },
    echo(tkCancel,
        query: {tkDelayMs: 300},
        cancel: 10,
        options: {tkCache: false, tkKey: false}),
    echo(tkNotify,
        query: {tkStatus: 400, tkCode: 400},
        options: {tkCache: false, tkKey: false}),
  ];
  final flow = <String, dynamic>{
    tkResults: {
      tkAccess: {tkOk: true},
      tkRefresh: {tkOk: true},
      ...success(tkRetry),
      ...success(tkCacheFirst),
      ...success(tkCacheHit),
      ...success(tkShareA),
      ...success(tkShareB),
      tkCancel: {tkOk: false, tkError: tkCanceled},
      tkNotify: {tkOk: false, tkError: 'status:400'},
    },
    tkServer: {
      tkByKey: {
        tkMatrixCache: {tkEq: 1},
        tkMatrixShare: {tkEq: 1}
      }
    },
    tkClient: {
      tkRefresh: {tkEq: 1},
      tkNotify: {tkEq: 1},
      tkPendingAfter: {tkEq: 0}
    },
  };
  add(
      'full-workflow',
      tkEmpty4,
      all,
      requests,
      {
        tkNormal: flow, tkWeak: flow,
        // 先观测真实 flap 拒绝，再恢复网络开展业务流；离线阶段由 offline 插件拒绝。
        tkFlap: {
          ...flow,
          tkResults: {
            ...flow[tkResults] as Map,
            tkDuringFlap: {tkOk: false, tkError: tkOffline}
          },
          tkClient: {
            tkRefresh: {tkEq: 1},
            // 此中立预期排除 offline 早期失败；outer notify 的设计差异单独报告。
            tkNotify: {tkEq: 1},
            tkPendingAfter: {tkEq: 0}
          }
        },
      },
      networks: [tkNormal, tkWeak, tkFlap],
      purpose: '17 插件全开：登录→访问→刷新→重试→缓存→共享→取消→通知。');
  // 三个网络共用业务流；flap 在前置阶段以独立场景执行，避免 normal 平白断网。
  final full = cases.removeLast();
  final fullManifest = manifest.removeLast();
  final flapExpect = (full[tkExpect] as Map).remove(tkFlap);
  full[tkNetworks] = [tkNormal, tkWeak];
  cases.add(full);
  manifest.add({
    ...fullManifest,
    tkNetworks: [tkNormal, tkWeak]
  });
  add(
      'full-flap-workflow',
      tkEmpty4,
      all,
      [
        echo(tkDuringFlap),
        {tkWait: 1600},
        ...requests,
      ],
      {tkFlap: flapExpect},
      networks: [tkFlap],
      purpose: '17 插件全开：flap 离线失败后恢复，再执行完整业务流。');

  // 两组配置在当前中立执行器中完全等价，显式保留两个零值选项。
  const aliases = {
    'plugins.boundary-retry-delay-ms-0': tkPluginsBoundaryRetryMax0,
    'plugins.boundary-loading-delay-close-ms-0':
        tkPluginsBoundaryLoadingDelayMs0,
  };
  cases.removeWhere((item) => aliases.containsKey(item[tkId]));
  manifest.removeWhere((item) => aliases.containsKey(item[tkScenario]));
  for (final item in cases) {
    if (item[tkId] == tkPluginsBoundaryRetryMax0) {
      obj(obj(item[tkClient])[tkPlugins])[tkRetry][tkDelayMs] = 0;
      item[tkTitle] =
          item[tkWhy] = 'retry.max = 0、retry.delay_ms = 0（合并等价缺省配置）';
    }
    if (item[tkId] == tkPluginsBoundaryLoadingDelayMs0) {
      obj(obj(item[tkClient])[tkPlugins])[tkLoading][tkDelayCloseMs] = 0;
      item[tkTitle] = item[tkWhy] =
          'loading.delay_ms = 0、loading.delay_close_ms = 0（合并等价缺省配置）';
    }
  }
  final root = Directory(tkEWorkspacesApiWsDemoTestkit);
  final encoder = const JsonEncoder.withIndent(tkJsonIndent);
  final domains = <String, List<dynamic>>{};
  for (final file
      in Directory('${root.path}/scenarios').listSync().whereType<File>()) {
    if (!file.path.endsWith(tkJson)) continue;
    final filename = file.uri.pathSegments.last;
    domains[filename] = (jsonDecode(file.readAsStringSync()) as List)
        .where((item) => !'${obj(item)[tkId]}'.startsWith(tkPlugins2))
        .toList();
  }
  for (final item in cases) {
    final required = item[tkRequires] as List;
    final plugin = required.length == 1 ? required.single as String : tkPlugins;
    final domain = const {
          tkEnvs: tkBasic,
          tkLog: tkBasic,
          tkKey: tkRepathKeyFilter,
          tkRepath: tkRepathKeyFilter,
          tkFilter: tkRepathKeyFilter,
          tkNormalize: tkNotifyNormalize,
          tkNotify: tkNotifyNormalize,
        }[plugin] ??
        plugin;
    (domains['$domain.json'] ??= []).add(item);
  }
  for (final domain in domains.entries) {
    File('${root.path}/scenarios/${domain.key}')
        .writeAsStringSync('${encoder.convert(domain.value)}\n');
  }
  File(tkAcceptResultsPluginMatrixPlanJson)
      .writeAsStringSync('${encoder.convert(manifest)}\n');
  stdout
      .writeln('生成 ${cases.length} 场景，归入对应领域；配对 ${rows.length} 行；实际执行以结果文件为准。');
}
