"""生成可重读、定点追加的文档变更；不整文件覆盖共享仓库文档。"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent.parent
OPS = pathlib.Path(r'C:/ldq/devfin/document_edits.json')


def main():
    """从真实结果生成增补段落及矩阵行，保留所有历史记录。"""
    audit = json.loads((OUT / 'audit.json').read_text(encoding='utf-8'))
    result = json.loads((OUT / 'assessment.json').read_text(encoding='utf-8'))
    frames = json.loads((OUT / 'frame_assessment.json').read_text(encoding='utf-8'))['scenarios']
    summary = '；'.join(f'{key}：{value}' for key, value in result['frame_results'].items())
    cn = ('DEVFIN（2026-11-11）本次仅单台 vivo V2417 / Android 16：' + summary + '。'
          '冷push首帧增量wheel/grid/slot为38.087/10.520/0.245ms，'
          '新标定增量预算41.896/11.572/0.270ms；wheel/grid未达原4ms估算目标。'
          'CPU五项目各五次均0有效，不能提供可信百分比；wheel/grid冷帧主机汇总仅2/5、1/5成功，'
          '数值来自原始driver响应，失败标记保留。真机采集链路未通过，不把已标定写成达到设计目标。')
    operations = []
    def insert(path, anchor, text):
        """记录唯一锚点后的追加，拷回前重读目标内容。"""
        operations.append({'path': path, 'anchor': anchor, 'text': text, 'mode': 'after'})
    def append(path, text):
        """记录文末追加，不修改历史段落。"""
        operations.append({'path': path, 'text': text, 'mode': 'append'})
    insert('docs/RELEASE_CHECKLIST.md', '# 0.1.0 发布检查清单\n',
           '\n## DEVFIN 最新真机收尾结果\n\n' + cn + '\n\n'
           '包含pending入口的profile APK已构建并校验，原脚本实际因有效轮不足退出1；'
           '只续跑未启动项目，共53次启动，每项3–5次。四个帧时项目均完成三轮，'
           '固定MET2比较器独立复算；原始attempt、恢复值、全部窗口交付和新旧表见'
           '[本次报告](../tool/bench/results/pending/REPORT.md)。'
           '冷帧增量预算见budgets.status.json.devfin；旧绝对首帧信息字段仅为schema兼容，'
           '不得把增量门槛直接比较旧40.378ms。12ms/4ms、稳定性和RSS阈值未放宽。\n\n'
           '- [x] 新入口APK、型号/哈希、手机原设置记录与全部原始尝试落盘。\n'
           '- [x] blank/slot冷帧各3轮driver通过；wheel/grid原始FrameTiming全部保留并计算增量。\n'
           '- [ ] wheel/grid冷帧driver未各满3轮，主机TimelineSummary缺少完整Raster事件，验收不确定。\n'
           '- [ ] 五项目CPU均0/5有效，cpuinfo区间滞后/旧PID及top线程表问题，尚未标定。\n'
           '- [x] 四个帧时场景各3轮完成；结果按失败/不确定/已标定分别保留，不承诺性能全通过。\n\n'
           '以下MET2/PEND待真机清单及前三轮门禁均为历史记录，当前状态以本节和第四轮度量说明为准。\n')
    report = (OUT / 'REPORT.md').read_text(encoding='utf-8').split('\n', 1)[1]
    append('docs/METRIC_FIX_REPORT.md', '\n## 第四轮：真机收尾复测\n' + report)
    insert('docs/TEST_STRATEGY.md', '## 8. 摇树验证（需求 6）\n', '')
    operations.pop()
    operations.append({'path': 'docs/TEST_STRATEGY.md', 'mode': 'before',
                       'anchor': '## 8. 摇树验证（需求 6）\n',
                       'text': '### 7.7 DEVFIN 本次真机事实与有效增量预算\n\n' + cn + '\n\n'
                       '本次按原脚本每轮核对亮屏未锁屏、不修改设置；原脚本提前退出后只续跑未启动项目，'
                       '不清零计数。完整原始文件、主机失败、CPU统计区间、每窗口交付和新旧结果见'
                       '[DEVFIN报告](../tool/bench/results/pending/REPORT.md)。'
                       '有效首帧度量由绝对信息项转为同Scaffold外壳的玩法中位数−空白中位数；'
                       '按前三份完整设备FrameTiming固定顺序计算，不挑耗时；其×1.1向上取整到0.001ms为冻结增量预算。'
                       '现有MET2 schema不能表达grid/slot及空白差值，预算暂存budgets.status.json.devfin并由DEVFIN测试核验；'
                       'budgets.json旧绝对信息字段保留兼容。CPU缺测没有预算通过结论。'
                       '硬门禁仍为每未污染窗口合计P99≤12ms、UI P99≤4ms，至少两个未污染窗口；'
                       '正常compare不自动放宽预算。以上§7.4–7.6保留历史身份，不冒充本次全部采样通过。\n\n'})
    root = ['\n## DEVFIN 新证据与仍无法判定的代码根因\n', cn, '',
            '| 场景 | 本次未污染/全部 | 未污染合计/UI P99最大ms | 结论 |',
            '| --- | --- | --- | --- |']
    for key, row in frames.items():
        clean = [w for w in row['windows'] if not w['backpressure_contaminated']]
        combined = max((w['99th_percentile_build_plus_raster_millis'] for w in clean), default=None)
        ui = max((w['99th_percentile_frame_build_time_millis'] for w in clean), default=None)
        root.append(f"| {key} | {len(clean)}/{len(row['windows'])} | {combined}/{ui} | {result['frame_results'][key]} |")
    root += ['', '本次CPU五个项目各5次均在before阶段失败，原生cpuinfo统计区间不对应新启动进程，'
             '匹配不到当前PID或命中旧PID；top可出现0线程及S[%CPU]等列头。'
             '例如cpu_wheel_steady_1的cpuinfo区间为00:38:23.396–00:40:58.935，'
             '并非本次五秒窗口；cpu_capsule_mixing_1返回的区间结束于采样前216647ms。'
             '完整原文和错误见results/pending/cpu_*/cpu/与audit.json。'
             '这些是采样链路故障，不是CPU=0，不是luckdraw代码性能证据。', '',
             '冷首帧设备端测试成功且FrameTiming响应完整，但主机TimelineSummary在部分冷窗口没有闭合Raster事件，'
             '因此wheel/grid只有2/5、1/5次driver成功。恢复数据保留原始response及时间关联，不改runs.json失败状态。', '',
             '本次逐帧归因文件见[frames.json](../tool/bench/results/pending/frames.json)。'
             '硬余量失败的代码根因仍为「无法判定」：缺少可靠原生线程CPU及luckdraw函数采样栈，'
             '不能将GLES/Encode墙钟等待等同可避免的库内工作；本轮未改lib、parity或golden。'
             '本次仍有硬失败时按原值保留，不放宽12ms/4ms门禁。', '']
    append('docs/PERF_ROOTCAUSE_REPORT.md', '\n'.join(root))
    insert('docs/README.md', '# luckdraw 文档索引\n', '\n## DEVFIN 最新设备证据\n\n' + cn + '\n\n'
           '见[第四轮度量说明](METRIC_FIX_REPORT.md#第四轮真机收尾复测)、'
           '[本次原始结果](../tool/bench/results/pending/REPORT.md)及[发布检查清单](RELEASE_CHECKLIST.md)。'
           '下文第三轮/MET2表保留历史口径，不能作为本次CPU已完成的证明。\n')
    insert('README.zh-CN.md', '## 性能\n', '\n' + cn + '\n\n'
           '详见[本次报告](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/pending/REPORT.md)。'
           '全部持续动画窗口的交付结果与每轮硬门禁分别列出；CPU缺测与driver失败未隐去。\n\n'
           '以下为MET2历史基线与规则，当前复测四项以DEVFIN为准；其余场景没有重跑。\n')
    english = ('DEVFIN (2026-11-11) reran four scenes on one vivo V2417 (Android 16), three rounds each. '
               + '; '.join(f'{key}: {value}' for key, value in result['frame_results'].items())
               + '. The 12 ms combined and 4 ms UI p99 gates were not relaxed. '
               'Cold-push UI increments (wheel/grid/slot minus blank) were 38.087/10.520/0.245 ms; '
               'calibrated increment budgets are 41.896/11.572/0.270 ms. Wheel and grid miss the original 4 ms estimate. '
               'Wheel/grid driver summarization succeeded only 2/5 and 1/5 times; raw FrameTiming responses were retained separately. '
               'All five CPU projects had 0/5 valid attempts because native statistics referred to stale intervals/PIDs. '
               'CPU remains unmeasured, and collection did not pass. Calibration does not establish design-target compliance. '
               'See the [DEVFIN report](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/pending/REPORT.md).')
    english = english.replace('已标定未达设计目标', 'calibrated, original design targets unmet').replace('不确定', 'uncertain').replace('失败', 'failed').replace('通过', 'passed')
    insert('README.md', '## Performance\n', '\n' + english + '\n\n'
           'The following MET2 results are the historical baseline; DEVFIN supersedes only the four retested scenes. Other scenes were not rerun.\n')
    rows = [
        ('retains device identity fresh responses and every failed attempt', '设备身份、新数据及全部失败尝试可追溯'),
        ('freezes signed cold frame increments without claiming design success', '增量预算冻结，原设计差距独立保留'),
        ('keeps missing native CPU rounds uncertain instead of zero percent', 'CPU缺测不填零、不冒充通过'),
        ('reports every clean window headroom failure with frozen gates', '每个未污染窗口12/4ms硬失败保留'),
    ]
    matrix = ['\n## 需求和不变量\n', '| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |',
              '| --- | --- | --- | --- | --- | --- |']
    for index, (name, description) in enumerate(rows, 1):
        matrix.append(f'| DEVFIN-{index:02} | {description} | DEVFIN；TEST_STRATEGY §7.7 | '
                      f'`test/tool/bench_devfin_test.dart :: bench DEVFIN > {name}` | 工具 | 已落地 |')
    entries = [('新pending入口APK构建与arm64标记校验', '已落地'),
               ('blank冷push三轮', '已落地'),
               ('wheel冷push三轮driver验收', '不确定：2/5；原始FrameTiming已恢复'),
               ('grid冷push三轮driver验收', '不确定：1/5；原始FrameTiming已恢复'),
               ('slot冷push三轮', '已落地')]
    entries += [(scene + '原生CPU三轮', f"不确定：{row['valid_rounds']}/{row['attempts']}；统计区间/PID/线程表采样失败")
                for scene, row in audit['cpu'].items()]
    entries += [(scene + '三轮复测', '已落地' if value in ['通过', '已标定未达设计目标'] else value + '：数值与原因见DEVFIN报告')
                for scene, value in result['frame_results'].items()]
    entries += [('全部持续动画主/参照交付检查', '已落地' if result['delivery_passed'] else '失败：见delivery.json')]
    for index, (description, outcome) in enumerate(entries, 5):
        matrix.append(f'| DEVFIN-{index:02} | {description} | DEVFIN；TEST_STRATEGY §7.7 | '
                      '`tool/bench/integration_test/pending_bench_test.dart :: pending > selected device check`'
                      f' | 基准 | {outcome} |')
    append('test/ACCEPTANCE.md', '\n'.join(matrix) + '\n')
    for op in operations:
        path = ROOT / op['path']
        text = path.read_text(encoding='utf-8')
        if op['mode'] == 'append':
            text += op['text']
        else:
            assert text.count(op['anchor']) == 1, op['path']
            replacement = op['anchor'] + op['text'] if op['mode'] == 'after' else op['text'] + op['anchor']
            text = text.replace(op['anchor'], replacement, 1)
        path.write_text(text, encoding='utf-8', newline='\n')
    OPS.write_text(json.dumps(operations, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('document operations', len(operations), 'acceptance additions', len(rows) + len(entries))


if __name__ == '__main__':
    main()
