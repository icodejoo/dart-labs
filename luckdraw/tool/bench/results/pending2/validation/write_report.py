"""生成本批报告及定点追加片段，历史文档前缀保留供共享仓库合并。"""

import json
import statistics
from pathlib import Path


OUT = Path(__file__).resolve().parent.parent
ROOT = OUT.parents[3]


def read(path):
    """读取本批已有 JSON，不推测缺少的设备值。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def values(rows, key):
    """按原顺序显示三轮；不足三轮明确缺测。"""
    return ' / '.join([f'{r[key]:.3f}' for r in rows] + ['缺测'] * (3 - len(rows)))


def main():
    """报告、README 与策略采用同一证据，完整逐事件原始统计保留 JSON。"""
    audit = read(OUT / 'audit.json')
    attribution = read(OUT / 'attribution.json')
    changes = read(OUT / 'validation/library_changes.json')
    lines = ['# INSTR 第五轮：冷首帧归因与 /proc CPU', '',
             '仅 vivo V2417 / Android16 / `10AE9K17UE0011S`，全部在 `C:/ldq/luckdraw` 副本执行。两个 APK 均启用 `LUCKDRAW_TIMELINE=true`。不升级依赖、不改 parity/golden 基线、不 add/commit/push。库候选修复位于副本；共享核心和各玩法的禁止覆盖规则优先，lib 以 `C:/ldq/core_patch.diff`、`C:/ldq/gameplay_patch.diff` 交主会话合并。真实仓库工具和文档落盘不表示库补丁已经合并。', '',
             '构建：`flutter build apk --profile --no-pub --target=integration_test/pending_bench_test.dart --dart-define=LUCKDRAW_TIMELINE=true`。Windows 根证书库、workers=2、单个活动构建；两次 Gradle 实测均32.5s。构建前 FreePhysicalMemory=11992920/9638392 KiB，均≥4GiB；临时 Gradle 属性已恢复。两个 APK SHA-256：', '',
             '- before：`35EEE3DEED78E8A4F777C1FA3262E5BE8C827B10ABF5F0F405539A99D4C797C5`。',
             '- after/CPU：`1FF4EACB243B3947AA0A829B1D61CE11A545ACFBC667DEDA57EA5C63FA8EC142`。', '',
             '可审核补丁：[core_patch.diff](validation/core_patch.diff)、[gameplay_patch.diff](validation/gameplay_patch.diff)、[核心矩阵与豁免追加](validation/core_acceptance_append.md)。主会话合并后需重跑真实仓库全量门禁。', '',
             '## 打点与数据完整性', '',
             '| 事件名 | 位置/边界 |', '| --- | --- |',
             '| `luckdraw.{wheel,grid,slot,capsule,number_wheel,lots,lotto}.layout` | 各 `lib/src/<game>/layout/<game>_layout.dart` 的 compute…Layout 函数，包含全部布局 |',
             '| `luckdraw.{上述七玩法}.record` | 各 painter 的构造/prepare/rebuildSegments 静态准备；Picture 缓存细分见公共 record |',
             '| `luckdraw.{上述七玩法}.paint` | 各 painter.paint，每次绘制成对；首帧内第一次即首次 paint，无默认构建的额外布尔状态 |',
             '| `luckdraw.text.layout` / `luckdraw.text.split` | core/text/text_line.dart、split_text.dart，总耗时；嵌套不重复相加 |',
             '| `luckdraw.text.painter.layout` | 所有直接 TextPainter.layout 调用；arguments.layouts=1，测量器、paint_helpers、lots/number_wheel/lotto |',
             '| `luckdraw.image.update` | LuckyImageResolver.update 的同步部分，不冒充异步解码总时长 |',
             '| `luckdraw.picture.record` | LuckyPictureCache.picture，缓存命中也有事件；实际录制见子调用与缓存计数 |',
             '| `luckdraw.raster.build` / `luckdraw.raster.prepare` / `luckdraw.raster.atlas` | picture_cache.raster 含 toImageSync；cached_picture 的回放参数准备；SlotAtlas.prepare |', '',
             '所有同步片段 try/finally 成对。包装函数保持 bool.fromEnvironment 编译期守卫、vm:prefer-inline；默认关闭不创建事件 arguments Map。没有新增可变全局状态或导出入口。COV-01 原调用/结束两行保留；参数 Map 格式化为独立行14，新增 COV-02仅豁免该行并逐行登记。默认渲染等价由全量测试和未更改的 parity/golden 复验；未额外构建关闭打点 APK 作二进制差异验证。', '',
             'driver 先保存完整 response，再保存全部原始 timeline，然后做汇总。只容忍冷首帧已测到正 buildDuration 且 SDK 精确报 “The TimelineSummary had no events to summarize.”；其它错误继续抛出。缺 Raster 不填零，保存 sdk_summary_status/error。CPU 路由显式记录没有独立 GC 参照，不伪造 GC 回归结论。', '',
             '## 冷首帧归因', '',
             'FrameTiming.buildDuration 是首帧结果指标；下表各阶段与占比的共同分母为**包含首次玩法 layout 的 Dart Frame b/e 墙钟区间**，两种边界不同。为避免各列独立中位数不能相加，每行选三轮中 FrameTiming 为中位数的那一轮。布局剔除文字；录制剔除文字/位图；文字包括录制期整形；其它是未打点区间（含框架），无法进一步归因。', '',
             '| 阶段/玩法 | FrameTiming / Dart Frame ms | 布局去文字 ms/% | 文字 ms/% | 录制去文字位图 ms/% | 位图 ms/% | 图片更新 ms/% | paint ms/% | 其它 ms/% |',
             '| --- | --- | --- | --- | --- | --- | --- | --- | --- |']
    stage_keys = ['layout_excluding_text', 'text', 'record_excluding_text_raster', 'raster', 'image_update', 'paint', 'other_uninstrumented']
    for phase in ('before', 'after'):
        for game, rows in attribution[phase].items():
            row = sorted(rows, key=lambda r: r['frame_timing_build_ms'])[1]
            cells = [f'{phase}/{game}', f'{row["frame_timing_build_ms"]:.3f} / {row["ui_frame_ms"]:.3f}']
            cells += [f'{row["stages_ms"][k]:.3f} / {row["stage_percent_of_ui_frame"][k]:.2f}%' for k in stage_keys]
            lines.append('| ' + ' | '.join(cells) + ' |')
    lines += ['', '全部12个有效冷窗口的每个 luckdraw 事件（含每次文字测量）绝对 start_us/end_us、相对起止、arguments、未配对事件及阶段原值见 [attribution.json](attribution.json)。各首帧内 luckdraw 事件均完整配对；窗口外裁断事件单独列示。可用 `python tool/bench/analyze_instr.py` 离线重算。以下为每轮原始统计：', '',
              '| 阶段/玩法/轮 | FrameTiming ms | Dart Frame起止 μs | layout/record含子事件 ms | TextPainter次数 / 总ms / 每次均ms |', '| --- | --- | --- | --- | --- |']
    for phase in ('before', 'after'):
        for game, rows in attribution[phase].items():
            for index, row in enumerate(rows, 1):
                lines.append(f'| {phase}/{game}/{index} | {row["frame_timing_build_ms"]:.3f} | {row["ui_frame_start_us"]}–{row["ui_frame_end_us"]} | {row["inclusive_layout_ms"]:.3f} / {row["inclusive_record_ms"]:.3f} | {row["text_painter_layout_calls"]} / {row["text_painter_layout_total_ms"]:.3f} / {row["text_painter_layout_mean_ms"]:.6f} |')
    lines += ['', '## 修复、复测和标定', '',
              '已定位的库内工作：相同样式和文本被反复完整整形。保持 splitLuckyText 的逐码点比较、回调顺序、负宽、超宽首字和 lineClamp 规则，未改成无法证明等价的二分或逐字宽相加；TextPainterMeasurer 只增加最多256项的精确宽度缓存，实例方向/缩放固定，dispose/样式缓存释放时清空。wheel 276→63次，grid128→22次。随机280组（70×方向2×缩放2）、多语言/组合字符/emoji、6种lineClamp 与旧完整整形逐位相同；另测缓存上限、命中避免 layout 和释放后重测。', '',
              '| 玩法 | before三轮ms / 中位数 | after三轮ms / 中位数 | 观测改善 | 减空白增量ms | ×1.1向上取整预算ms | 比原4ms多ms |', '| --- | --- | --- | --- | --- | --- | --- |']
    for game, row in audit['cold'].items():
        lines.append(f'| {game} | {" / ".join(f"{v:.3f}" for v in row["before_ms"])} / **{row["before_median_ms"]:.3f}** | {" / ".join(f"{v:.3f}" for v in row["after_ms"])} / **{row["after_median_ms"]:.3f}** | {row["improvement_fraction"]*100:.2f}% | {row["increment_ms"]:.3f} | {row["increment_budget_ms"]:.3f} | {row["gap_to_original_4ms"]:.3f} |')
    lines += ['', '空白使用用户指定 DEVFIN 历史中位数2.883ms，本批遵照仅测wheel/grid未新增空白启动，故不是同期空白重测。两玩法修复后均观测到改善，保留候选缓存；三轮极差仍大（wheel17.594ms，grid12.581ms），不是稳定性或跨设备保证。已标定不等于达到4ms目标；预算冻结到 budgets.status.json.instr，既有绝对信息 schema 与稳态12ms/4ms、GC、RSS阈值不变。', '',
              'wheel/grid before 各3/3，after wheel3/3、grid3/4；grid after首轮结束检查非亮屏未锁，标无效且原文保留，不按耗时挑轮。无独立采样栈的其它/异步解码/引擎与驱动成本仍无法判定，不据此继续修改渲染算法。', '',
              '## /proc CPU 原值与同轮帧时', '',
              '每窗口前 pidof 重新取PID；窗口外探测 shell/run-as/su，窗口内仅开始/结束各一次 adb。进程 stat 是进程合计，task/tid/stat 是单线程；读取 comm 保留空格/括号。差值÷主机两次读取开始的单调时刻差÷CLK_TCK×100，单核100%，不裁剪多核总值。请求稳定等待5秒；读取和握手开销使实际间隔更长，逐轮真实秒数和读取耗时如下，不伪称恰好5秒。', '',
              '实际 shell 可读；没有采用 dumpsys/top 百分比代替本轮CPU。grid第3次历史降级源于 CRLF 解析缺陷，原 permission 文案不准确，已修正解析并补LF/CRLF实机夹具；该轮无可信增量，从有效CPU统计剔除。快照读取由逐线程cat/逐字节read改为三次缓冲cat，仍是同一个 adb 调用。解析失败显式抛错，不再冒充权限问题或填零。', '',
              '当前 Flutter3.47 Android 默认 UI/platform 合并，/proc主线程名为 .luckdraw_bench（tid=pid），Raster名1.raster。下表 UI+platform 不是纯Dart UI CPU；依据 [Flutter官方架构说明](https://docs.flutter.dev/resources/architectural-overview) 与本轮线程原文，不能将两者拆开。CPU路由 lotto_draw 延续已有 helper 的搅拌阶段，未覆盖完整开奖过程，完整开奖CPU仍无法判定。', '',
              '| 场景 | 正式有效/启动 | 进程三轮% / 中位数 | UI+platform三轮% / 中位数 | Raster三轮% / 中位数 |', '| --- | --- | --- | --- | --- |']
    for scene, value in audit['cpu'].items():
        cells = [scene, f'{value["valid_rounds"]}/{value["attempts"]}']
        for key in ('process_percent', 'ui_platform_percent', 'raster_percent'):
            median = f'{value["medians"][key]:.3f}' if value['medians'] else '不足三轮不计算'
            cells.append(values(value['rounds'], key) + ' / **' + median + '**')
        lines.append('| ' + ' | '.join(cells) + ' |')
    lines += ['', '| 场景/尝试 | CPU真实秒数 | 首/尾读取ms | 同轮FrameTiming窗口秒数 / 帧数 / fps | UI均ms / Raster均ms |', '| --- | --- | --- | --- | --- |']
    for scene, value in audit['cpu'].items():
        for row in value['rounds']:
            frames = row['frame_timing']
            before = f'{row["before_read_micros"]/1000:.3f}' if row['before_read_micros'] is not None else '未分记'
            after = f'{row["after_read_micros"]/1000:.3f}' if row['after_read_micros'] is not None else '未分记'
            lines.append(f'| {scene}/{row["attempt"]} | {row["seconds"]:.6f} | {before}/{after} | {frames["elapsed_micros"]/1e6:.6f} / {frames["frame_count"]:g} / {frames["fps"]:.3f} | {frames["average_frame_build_time_millis"]:.6f} / {frames["average_frame_rasterizer_time_millis"]:.6f} |')
    lines += ['', '转盘第1/2次原始 CPU 可读但 driver 因缺GC参照失败，第5次 VM Service连接前卡住，四分钟采样器超时、五分钟终止自有drive进程树；正式仅第3/4次成功，2/5，未超上限补第六次。原始附加值如下，只作为失败产物证据，不混入三轮正式中位数：', '',
              '| 场景/尝试 | 进程 / UI+platform / Raster % | CPU秒数 |', '| --- | --- | --- |']
    for scene, value in audit['cpu'].items():
        for row in value['other_attempts']:
            if 'process_percent' in row:
                lines.append(f'| {scene}/{row["attempt"]}（driver失败） | {row["process_percent"]:.6f} / {row["ui_platform_percent"]:.6f} / {row["raster_percent"]:.6f} | {row["seconds"]:.6f} |')
    lines += ['', '全部线程、线程新建/退出、身份、命令失败和同轮FrameTiming见 [audit.json](audit.json) 与各 cpu_*/cpu_*/cpu/ 的 before/after/cpu.json。新建/退出线程单列，不填0；进程合计包含它们。线程采集非原子，统计边界的小偏差保留，不能把线程和与进程总值强行调成相等。', '',
              '## 本机门禁', '', '| 命令 | 实际输出摘要 |', '| --- | --- |']
    for name in ('analyze', 'bench_analyze', 'format', 'format_check', 'tools', 'instr-a', 'instr-b', 'instr-c', 'instr-d', 'coverage', 'imports', 'acceptance', 'acceptance_json', 'parity', 'publish'):
        path = OUT / f'validation/{name}.command.json'
        if path.exists():
            data = read(path)
            log = OUT / f'validation/{name}.stdout.log'
            tail = log.read_text(encoding='utf-8-sig', errors='replace').strip().splitlines()
            if name.startswith('instr-') or name == 'tools':
                detail = '真实JSON日志及test_summary.json，未使用登记数代替执行数'
            else:
                detail = ' / '.join(tail[-2:])[:260] if tail else '见原始stderr'
            lines.append(f'| {name} | exit={data["exit_code"]}，{data["seconds"]}s；{detail} |')
        else:
            lines.append(f'| {name} | 尚未执行，不计通过 |')
    if (OUT / 'validation/test_summary.json').exists():
        totals = read(OUT / 'validation/test_summary.json')
        lines += ['', '四组唯一执行计数：`' + json.dumps(totals, ensure_ascii=False) + '`。新增19条（工具17、文字等价2）；矩阵采用INSTR编号，D6代码行已落地，设备不足项单列。']
    lines += ['', '## 偏离、冲突与建议', '',
              '- 路径协议与打点要求冲突：任务要求七玩法/core打点，但副本协议禁止覆盖核心和其它玩法且未提供独占玩法路径。副本完成并验证全部lib改动，核心8文件与文字等价测试保存core_patch.diff；玩法15文件保存gameplay_patch.diff；真实仓库仅回拷工具、工具测试及共享文档定点追加。应用两补丁及核心矩阵追加后主会话需重跑门禁，不冒充已经合并。',
              '- 旧driver要求完整Raster/GC参照会误伤本批冷窗口和CPU窗口；现先保存原始response，仅对真实已测首帧的指定SDK错误降级，CPU明确未采GC参照。',
              '- 建议 ARCHITECTURE §8.3 的文字测量器缓存表补充“同一布局实例最多256项(text, style)精确宽度，dispose清空”。splitLuckyText 对n个码点调用约O(n)次前缀layout，总整形工作可近O(n²)，不应写成O(n²)次layout；本批没有改变换行公式、回调顺序或采用单字宽相加。',
              '- 首帧schema只支持旧wheel绝对信息，保持兼容，将有效增量与新预算追加instr字段；建议后续增加空白来源、增量/绝对指标类型，避免把26.612ms增量直接比到绝对首帧。',
              '- 不能从 Timeline 的1.ui标签推导Linux tid；当前UI/platform合并，按主线程原始stat归类。建议以后采样元数据显式记录线程角色与合并状态。',
              '- CPU窗口请求5秒，真实时长含首读开销，按真实主机间隔计算；同轮FrameTiming覆盖完整握手区间，不把两者边界说成完全相等。lotto本次仅搅拌阶段，完整开奖CPU未测。',
              '- 手机接手实测stay_on=2，中途实测变为0，来源未定位；本批未执行设置写入命令，已异步请求操作者恢复。最终值见device_final.json；若仍0则收尾目标未满足，不写成已恢复2。卸载命令返回DELETE_FAILED_INTERNAL_ERROR，但随后package列表与pm path均空，不把失败退出码写成0。',
              '- 原始DEVFIN/MET2报告与所有失败标记保留，不能把本轮首帧改善外推为稳态硬门禁已通过；未重测原slot_raster/lots等未通过项。', '',
              '### 修改的库文件（仅副本与补丁）', '']
    lines += ['- `' + row['path'] + '`（' + row['kind'] + '）。' for row in changes]
    (OUT / 'REPORT.md').write_text('\n'.join(lines) + '\n', encoding='utf8', newline='\n')
    short = ('INSTR（2026-11-11，副本候选实现）：wheel/grid带打点冷首帧中位数38.412→27.075ms、24.214→12.993ms，'
             '精确文字宽度缓存将首帧TextPainter.layout次数276→63、128→22；随机/多语言/emoji/lineClamp等价。'
             '减DEVFIN历史空白2.883ms后的增量24.192/10.110ms，新预算26.612/11.121ms，仍未达到原4ms目标，三轮波动大。'
             'CPU采用/proc累计节拍差，UI与平台合并标为UI+platform；wheel完整链路仅2/5，不能给三轮中位数；'
             '其余场景逐轮数值和有效性见本轮报告，lotto仅搅拌阶段。库改动以补丁交付，未覆盖并行共享lib，待主会话合并。')
    link = '../tool/bench/results/pending2/REPORT.md'
    sections = {
        'docs/PERF_ROOTCAUSE_REPORT.md': '\n## 冷首帧归因（INSTR，第五轮）\n\n' + short + '\n\n以上逐阶段去重表、每个事件起止、三轮原值、CPU与限制见[第五轮完整归因报告](' + link + ')及[attribution.json](../tool/bench/results/pending2/attribution.json)。首帧中位数代表轮中，wheel文字32.138→15.709ms（Dart Frame占81.69%→51.76%），grid文字16.345→4.774ms（63.12%→33.40%）；布局/文字/录制为嵌套片段，不直接相加。已定位重复整形、已在副本修复并观测改善；未打点区间及异步图片解码仍无法判定。\n',
        'docs/RELEASE_CHECKLIST.md': '\n## INSTR 第五轮实际结果\n\n' + short + '\n\n[逐轮证据、门禁和未完成项](' + link + ')；[命令与退出码](../tool/bench/results/pending2/validation/)。不能将副本库修复、已标定或14份有效CPU中的部分成功写成发布性能全部通过。原12ms/4ms、GC、RSS门槛和历史失败保持。\n',
        'docs/METRIC_FIX_REPORT.md': '\n## 第五轮：INSTR 冷首帧与线程CPU\n\n' + short + '\n\n[完整报告](' + link + ')。首帧阶段占比使用包含首次layout的Dart Frame，结果指标保持FrameTiming.buildDuration；相同边界去重后才求占比。CPU取stat的utime+stime增量/真实主机读取开始间隔/100Hz，实际窗口长度与两次读取耗时逐轮保留；UI/platform合并不当纯UI报。转盘两个GC汇总失败原值不冒充driver通过，第五次启动超时后没有第六次；grid CRLF解析错误造成的历史假权限降级已识别，原文保留、该轮剔除。默认打点包装编译期关闭，新增精确豁免仅COV-02第14行；共享库补丁待合并。\n',
        'docs/TEST_STRATEGY.md': '\n### 7.8 INSTR：函数级时间线与 /proc 差分\n\n' + short + '\n\n[报告](' + link + ')。每个同步事件成对、所有TextPainter.layout调用记录arguments.layouts=1；首帧各阶段按区间并集/差集统计，逐事件绝对起止保留attribution.json。CPU窗口只读两次adb，pidof和权限探测在窗口前；主机单调时刻差作分母；解析LF/CRLF、空格/括号comm、PID复用与计数倒退显式失败。driver先落盘原始响应，冷Raster缺失不伪造Raster指标；CPU未测GC参照单列。新增INSTR矩阵代码19条、设备7条，正式轮不足状态按实际；不降低覆盖、导入、矩阵、parity或发布预演门禁。\n',
        'docs/README.md': '\n## INSTR 第五轮入口\n\n' + short + '\n\n[原始数据和全部门禁](' + link + ')；[逐事件归因](../tool/bench/results/pending2/attribution.json)。前面DEVFIN/MET2条目保留其历史身份。\n',
        'README.zh-CN.md': '\n' + short + '\n\n见[INSTR第五轮报告](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/pending2/REPORT.md)。下文DEVFIN/MET2是历史记录；本批仅上述范围更新，未承诺性能全通过。\n',
        'README.md': '\nINSTR (2026-11-11, isolated candidate): exact text-width caching reduced cold wheel/grid TextPainter.layout calls from 276/128 to 63/22. Instrumented build-duration medians changed from 38.412/24.214 ms to 27.075/12.993 ms. Increments over the historical DEVFIN blank (2.883 ms) are 24.192/10.110 ms; calibrated increment budgets are 26.612/11.121 ms. Both still miss the original 4 ms target and the three-round spread is large. CPU uses /proc tick deltas and actual host intervals; UI and platform are reported together. Wheel has only 2/5 complete driver runs, so no three-run median; lotto CPU covers mixing only. Library changes are delivered as patches for the shared workspace, pending merge. See the [INSTR report](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/pending2/REPORT.md). The DEVFIN/MET2 text below remains historical and does not establish complete performance compliance.\n',
    }
    (OUT / 'validation/document_sections.json').write_text(json.dumps(sections, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    for relative, addition in sections.items():
        baseline = Path('C:/ldq/instr-baseline') / relative
        text = baseline.read_text(encoding='utf8')
        if relative.startswith('README'):
            heading = '## Performance\n' if relative == 'README.md' else '## 性能\n'
            text = text.replace(heading, heading + addition, 1)
        elif relative.endswith('TEST_STRATEGY.md'):
            marker = '## 8. 摇树验证（需求 6）'
            text = text.replace(marker, addition + '\n' + marker, 1)
        else:
            text += addition
        (ROOT / relative).write_text(text, encoding='utf8', newline='\n')


if __name__ == '__main__':
    main()
