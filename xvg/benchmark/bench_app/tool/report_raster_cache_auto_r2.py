"""校验第二轮结果并生成可复算的原始 JSON 和对比报告。"""

import argparse
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path

import report_raster_cache_auto as first
from raster_cache_auto_r2_plan import (
    FEATURES, LEGACY_SIZES, WEB_SIZES, load_json, load_lines, reduce_plan, save_json,
)
from raster_cache_auto_r2_rules import (
    AREA_GRID, CAP_GRID, EFFECT_GRID, MIB, POINT_GRID, aggregate, case_geometry,
    evaluate, fit, is_icon, predict,
)
from run_raster_cache_auto_r2 import LEGACY_ID, LIB_HASH, sha256

OUTCOME_FIELDS = ("total", "opened", "hit", "false", "weak", "miss", "closed", "icon_open")
OUTCOME_HEAD = ("组", "组合", "启用", "命中 >1ms", "误开 ≤0", "微利 (0,1]ms",
                "漏开 >1ms", "其余关闭", "图标启用")
ORIGINAL_ID = "233KB"


def markdown_table(headers, rows):
    """生成带有完整表头的 Markdown 表，转义数据中的竖线。"""
    cell = lambda value: str(value).replace("|", "&#124;").replace("\n", " ")
    return "\n".join(
        "| " + " | ".join(map(cell, row)) + " |"
        for row in (headers, ["---"] * len(headers), *rows)
    )


def ms(value):
    """按统一精度显示微秒换算后的毫秒。"""
    return f"{value / 1000:.3f}"


def elapsed(value):
    """将持续时间写为小时、分钟和秒。"""
    minutes, seconds = divmod(round(value), 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours} 小时 {minutes:02d} 分 {seconds:02d} 秒"


def rule_text(rule):
    """显示可以直接实现的数值门槛。"""
    if rule is None:
        return "保持向量"
    area = f"在屏内容面积 ≥ {rule['area']:,} px²" if rule["area"] else "在屏内容面积 > 0"
    cost = f"点数 ≥ {rule['points']:,}"
    if rule["blur_area"]:
        cost = f"（{cost}，或模糊绘制数 × 在屏内容面积 ≥ {rule['blur_area']:,}）"
    return f"内容在框内，{area}，{cost}，预计单图纹理 ≤ {rule['cap'] // MIB} MiB"


def expected_matrix(web, legacy, confirmation):
    """还原每个样本尺寸在各轮次的预期组合。"""
    expected = {
        (row["id"], size, number)
        for row in web for size in WEB_SIZES
        for number in ((1, 2, 3) if size in confirmation.get(row["id"], []) else (1,))
    }
    expected.update(
        (sample, size, number) for sample in legacy for size in LEGACY_SIZES
        for number in (1, 2, 3)
    )
    return expected


def collect(plan, web, confirmation, batches):
    """验证计划数据齐全，单列跳过和少于安排轮数的组合。"""
    actual = {}
    for batch in batches:
        for row in batch["accepted"]:
            if row["type"] == "baseline":
                continue
            key = row["sample"], row["size"], batch["round"]
            assert key not in actual, key
            actual[key] = row
    target = expected_matrix(web, plan["legacy"], confirmation)
    if set(actual) != target:
        raise ValueError(f"Matrix incomplete: {len(target - actual.keys())} missing, "
                         f"{len(actual.keys() - target)} unexpected")
    skips = [{"round": key[2], **row} for key, row in actual.items() if row["type"] == "skip"]
    incomplete = {(row["sample"], row["size"]) for row in skips}
    all_cases = aggregate(batches)
    cases = [row for row in all_cases if (row["sample"], row["size"]) not in incomplete]
    assert all(len(row["rounds"]) in {1, 3} for row in cases)
    return cases, skips, len(actual)


def paired_results(first_data, cases):
    """对齐第一轮主矩阵的同样本、同尺寸及同物理像素结果。"""
    old_rows = first.aggregate(first_data["runs"])
    by_key = {(c["sample"], c["size"]): c for c in cases if c["split"] == "legacy"}
    result = []
    for old in old_rows:
        name = LEGACY_ID if old["sample"] == ORIGINAL_ID else old["sample"]
        new = by_key.get((name, old["size"]))
        if new is None:
            continue
        assert len(new["rounds"]) == 3
        assert new["width_dp"] == old["width_dp"] and new["height_dp"] == old["height_dp"]
        assert new["visible_px"] == old["visible_px"]
        result.append({
            "sample": name, "size": old["size"], "contained": new["contained"],
            "old_enabled": first.recommend(old), "covers_clip": new["covers_clip"],
            "old_vector_us": old["vector"], "old_cached_us": old["cached"],
            "old_gain_us": old["benefit"], "old_bytes": old["bytes"],
            "new_vector_us": new["vector_us"], "new_cached_us": new["cached_us"],
            "new_gain_us": new["gain_us"], "new_bytes": new["bytes"],
        })
    return result


def check_skipped_eligibility(skips, by_id, rule, baseline):
    """用 PC 元数据检查候选是否会启用无真机收益标签的公开组合。"""
    result = {}
    for skip in skips:
        sample, size = skip["sample"], skip["size"]
        if (sample, size) in result or sample not in by_id:
            continue
        features = by_id[sample].get("features")
        if features is None:
            continue
        width = (baseline["screen_width_px"] / baseline["dpr"] if size == "full"
                 else float(size))
        case = {
            "features": features, "width_dp": width,
            "height_dp": width * features["picture_height"] / features["picture_width"],
        }
        if predict({**case, **case_geometry(case, baseline)}, rule):
            result[sample, size] = {key: skip[key] for key in
                                    ("sample", "size", "split", "stage", "reason")}
    return list(result.values())


def stage_report(plan, web, time_budget, confirmation, batches, sessions, cases,
                 skips, pair, analysis, total, windows_dll_sha256, initial_recovery):
    """把覆盖率、规则评估、首次修复对比及逐文件表汇成报告。"""
    by_id = {row["id"]: row for row in plan["corpus"]}
    split_name = {"fit": "拟合", "holdout": "留出"}
    successful = {c["sample"] for c in cases}
    web_success = successful & {row["id"] for row in web}
    legacy_success = successful & set(plan["legacy"])
    by_file = Counter(c["sample"] for c in cases)
    complete_web = sum(by_file[sample] == len(WEB_SIZES) for sample in web_success)
    complete_legacy = sum(by_file[sample] == len(LEGACY_SIZES) for sample in legacy_success)
    case_counts = Counter(c["split"] for c in cases)
    confirm_count = sum(map(len, confirmation["sizes_by_sample"].values()))
    actual_seconds = sum(session["elapsed_s"] for session in sessions)
    thermal_pauses = sum(b["status"] == "thermal_pause" for b in batches)
    thermal_seconds = sum(b["cool_s"] for b in batches)
    discards = sum(len(b["discarded_after_last_cool"]) for b in batches)
    process_exits = Counter(b.get("exit_reason") for b in batches if b["status"] == "process_exit")
    base = next(r for b in batches for r in b["accepted"] if r["type"] == "baseline")
    final = analysis["rule"]
    scores = analysis["groups"]
    valid = (final is not None and scores["holdout"]["hit"] > 0
             and not scores["holdout"]["false"] and not scores["holdout"]["icon_open"]
             and not analysis["eligible_skips"])
    release_text = rule_text(final) if valid else "保守地保持向量，候选门槛见下文"
    lines = [
        "# 自动位图缓存阈值第二轮真机测量", "",
        f"**推荐**。{release_text}。由库在内部判断，沿用已有的网格稳定、预算和重绘条件。",
        f"留出组 {scores['holdout']['hit']} 个命中、{scores['holdout']['false']} 个误开、"
        f"{scores['holdout']['weak']} 个微利启用、{scores['holdout']['miss']} 个漏开，"
        f"图标启用 {scores['holdout']['icon_open']} 个。", "",
        f"上机计划 {len(web)} 个网上 SVG 和 {len(plan['legacy'])} 个第一轮样本，"
        f"至少一个有效尺寸的文件分别为 {len(web_success)}、{len(legacy_success)} 个，"
        f"全部尺寸有效的文件分别为 {complete_web}、{complete_legacy} 个。"
        f"真机总耗时 {elapsed(actual_seconds)}，含推送、启动、冷却和清理。", "",
        "## 方法", "",
        f"- Samsung SM-A566B，序列号 `{sessions[-1]['device']}`，Android 17，"
        f"{base['screen_width_px']:.0f} × {base['screen_height_px']:.0f} px，"
        f"DPR {base['dpr']}，{base['display_hz']:.0f} Hz。Flutter 3.50.1，"
        "engine `4d35714800b9266b6693a58e1225ecd7e9e45ed7`，arm64 profile，Impeller Vulkan。",
        f"- APK 内 `lib/arm64-v8a/libxvg.so` SHA-256 为 `{LIB_HASH}`。"
        "使用 `XVG_BENCH_JNI_DIR` 在构建时替换插件 JNI 输入目录。",
        f"- PC 显式加载同一工作区 Windows release DLL，SHA-256 为 `{windows_dll_sha256}`。"
        "逐文件解析 SVG 并记录实际场景。唯一声明 ISO-8859-1 的输入按其 XML 声明解码。"
        "原 SVG 均经运行时输入，公开语料沿用随附清单的来源和许可证。",
        "- 固定视口内左上对齐、等比缩放，图静止，独立 spinner 持续出帧。"
        "网上语料测 48dp、200dp、满宽，第一轮样本另测 16dp。"
        "每批一个 spinner 基线。每场景在首帧或分块齐备后预热 300ms，采样至少 650ms 且至少 18 帧，"
        "校验窗口内块持续就绪。模式和尺寸顺序用固定种子打散。",
        "- 每轮取 raster p50，三轮组合分别取向量、缓存 p50 的中位数。"
        "净收益 = 向量 − 缓存，减去同一批基线后差值相同。"
        "主列表点数包含曲线控制点，图案计数按实际填充／描边引用，"
        "透明度、裁剪用显示列表入栈计数，遮罩、模糊计路径和图片实例。"
        "内容面积是保守包围盒面积，面积比分母为固有插画框。",
        f"- 按清单类别 × 体积（<4、4–<32、32–<256、≥256 KiB）× 主要特性分层，"
        f"种子 `{plan['seed']}`。特性优先级为位图、模糊、遮罩、图案、文字、密集路径、其他画笔效果、普通。"
        "密集路径为原生路径 ≥1,000 或点数 ≥10,000。先覆盖可抽取的层，再按剩余比例加样。"
        "计时前整张文件划分，同一图的尺寸始终在同一组。",
        f"- 十图试跑 {elapsed(time_budget['pilot_wall_s'])}，"
        f"平均 {time_budget['seconds_per_web_sample']:.1f}s/图。"
        f"按 200 图、每组合都测三轮的上界估计 {time_budget['projected_200_upper_s'] / 3600:.2f} 小时，"
        + ("保留 200 个。" if len(web) == 200 else f"高于 4 小时，按原分层比例缩至 {len(web)} 个。"),
        f"- 全部网上样本先测一次。以拟合组筛选轮定候选阈值，再对 [0.3, 3]ms "
        f"或离候选阈值约 20% 的 {confirm_count} 个网上尺寸组合各补两轮。"
        f"第一轮样本的四档各测三轮。全程登记 {total} 个尺寸轮次（含跳过）。",
        f"- 每约 2 秒读取系统热状态。出现 >0 就停应用，丢弃上次确认热状态为 0 后才完成的窗口。"
        f"共 {thermal_pauses} 次停测，冷却等待 {elapsed(thermal_seconds)}，"
        f"丢弃 {discards} 条记录。热状态、轮次和基线均可在原始数据复算。",
        (f"- 真机进程异常退出 {sum(process_exits.values())} 次，"
         + "、".join(f"`{reason}` {count} 次" for reason, count in process_exits.items())
         + "。已落盘且符合温控的组合继续使用，卡点以独立进程重试。"
         if process_exits else "- 完成计时的批次中，基准进程均正常结束。"),
        f"- 试跑样本编号 `{' '.join(plan['pilot'])}`。拟合和留出分别有 "
        f"{sum(row['split'] == 'fit' for row in web)}、{sum(row['split'] == 'holdout' for row in web)} 个文件，"
        f"最终计分尺寸组合 {case_counts['fit']}、{case_counts['holdout']} 个。",
        "", "## 规则和命中", "",
        f"筛选轮候选为 **{rule_text(confirmation['rule'])}**。"
        f"确认后仅用拟合计时重选，最终候选为 **{rule_text(final)}**。"
        "候选要求内容边界已知且在框内，使用实际裁剪与内容交集的物理面积，"
        "预估 512px 分块、64px 预取和 RGBA8 采样边的纹理占用。"
        "有 ColorFilter 或几何／网格不稳定时走向量。"
        "路径、命令和图片特征每张 Picture 线性遍历一次，几何判定为常数时间。", "",
        "拟合排除任何图标启用、净收益 ≤0 或任一重复轮变慢的候选。"
        "每个命中计 +1，每个微利启用计 −2，其后按命中数、微利数、内存上限、"
        "是否省去模糊项和收益总和比较。图标对照包括 MDI 和清单的 small、emoji、logo。"
        "组别固定，留出结果仅评价。", "",
        markdown_table(OUTCOME_HEAD, [
            (split_name[group], *(scores[group][field] for field in OUTCOME_FIELDS))
            for group in ("fit", "holdout")
        ]), "",
    ]
    if not valid:
        lines += [
            "发布门槛要求留出组有命中、误开和图标启用均为零，且候选没有启用缺少稳态计时的组合。"
            "表内保留预先拟合的候选，供独立样本继续验证。", "",
        ]
    if initial_recovery:
        lines += [
            f"首次筛选在 `{initial_recovery['sample']}/{initial_recovery['size']}` "
            f"遇到 Android `{initial_recovery['exit_reason']}`。"
            f"当批有 {initial_recovery['discarded_completed_cases']} 个已落盘组合，"
            "温控日志未落盘，整批从冻结名单重测。首次会话耗时计入真机总耗时。", "",
        ]
    score_alternatives = []
    for label, variant in analysis["alternatives"].items():
        for group in ("fit", "holdout"):
            metrics = variant["groups"][group]
            score_alternatives.append((label, split_name[group], rule_text(variant["rule"]),
                                       *(metrics[field] for field in OUTCOME_FIELDS[1:])))
    lines += [
        markdown_table(("规则族", "组", "独立拟合的门槛", *OUTCOME_HEAD[2:]), score_alternatives),
        "",
        "“限制满宽”仍使用内容在框内的快路径，但只允许横向铺满。"
        "“双轴兜底”额外允许边界溢出／未知且插画框覆盖整个裁剪的旧快路径。"
        "保守规则可删除第一轮的仅横轴覆盖分支。"
        "满宽版本在拟合组多命中的组合未带来额外留出命中，双轴兜底也未增加命中。"
        "内容溢出且仅横轴覆盖的个别大图仍有收益，现阶段统一拒绝这类自动启用。", "",
    ]
    for group in ("fit", "holdout"):
        false = scores[group]["false_cost"]
        if false:
            lines += [
                f"**{split_name[group]}误开代价**", "",
                markdown_table(("样本", "尺寸", "净收益 ms", "纹理字节"), [
                    (r["sample"], r["size"], ms(r["gain_us"]), f"{r['bytes']:,.0f}")
                    for r in false
                ]), "",
            ]
    lines += report_diagnostics(by_id, web, cases, skips, analysis)
    lines += report_pairs(pair, cases)
    lines += report_sample_lists(plan, web)
    lines += [
        "", "## 局限与复算", "",
        "- 数据来自单台、单后端、连续出帧的静态单图场景。"
        "没有测滚动、多个图同时争预算、低刷新率设备和不触发重放的页面。"
        "新阈值的输入还需满足库已有的缓存条件。来源里存在相近图形，文件级留出仍可能弱化跨来源验证。",
        "- 位图纹理字节按库的 RGBA8 账本计算，GPU 驱动分配、上传峰值和 SVG 原有图片占用另外计算。"
        "齐备时间使短驻留场景的收益偏低。系统热状态 0 期间仍可能发生频率变化。",
        "- 文字、图案和复杂滤镜在清单里按 SVG 源码分类，计分采用实际解析出来的原生场景。"
        "字体、复杂滤镜和图案的支持程度会影响源 SVG 与实际绘制成本的对应关系。",
        "- 采样前冻结的候选文件、原始逐帧数组、基线、温控、各组合估计、"
        "评价和失败原因见 [原始 JSON](raster_cache_auto_r2_raw.json)。",
        "- 复算入口见 [报告脚本](bench_app/tool/report_raster_cache_auto_r2.py)。"
        "推送与采集见 [真机脚本](bench_app/tool/run_raster_cache_auto_r2.py)。",
        "",
        "在 `benchmark/bench_app` 运行。先将指定工作区 so 暂存到构建覆盖目录的 "
        "`arm64-v8a/libxvg.so`，将 `XVG_BENCH_JNI_DIR` 指向该目录。"
        "用本机变量 `$LegacySvg` 指定运行时匿名输入。", "",
        "```powershell",
        "flutter build apk --profile --no-pub --android-skip-build-dependency-validation --target-platform android-arm64 -t lib/raster_cache_auto_r2_main.dart",
        "python tool/run_raster_cache_auto_r2.py verify-apk",
        "python tool/run_raster_cache_auto_r2.py inputs",
        "$Scratch = '.dart_tool/raster_cache_auto_r2'",
        "dart --packages=.dart_tool/package_config.json tool/raster_cache_auto_r2_features.dart `",
        "  ../../rust/target/x86_64-pc-windows-msvc/release/xvg.dll `",
        "  \"$Scratch/windows_inputs.json\" \"$Scratch/windows_features.jsonl\"",
        "python tool/run_raster_cache_auto_r2.py plan",
        "python tool/run_raster_cache_auto_r2.py measure --legacy-svg $LegacySvg",
        "python tool/report_raster_cache_auto_r2.py",
        "```",
    ]
    return "\n".join(lines) + "\n"


def report_diagnostics(by_id, web, cases, skips, analysis):
    """汇总边界溢出、估计误差、跳过状态和确认组敏感性。"""
    lines = ["## 内容边界、面积和内存", ""]
    corpus_groups = [
        ("PC 全集", list(by_id.values())),
        ("上机网上样本", [by_id[row["id"]] for row in web]),
    ]
    bounds_rows = []
    for label, rows in corpus_groups:
        counts = Counter(r.get("features", {}).get("content_overflow") for r in rows)
        bounds_rows.append((label, len(rows), counts[True],
                            f"{100 * counts[True] / len(rows):.1f}%", counts[False], counts[None]))
    legacy = {c["sample"]: c["features"] for c in cases if c["split"] == "legacy"}
    counts = Counter(f["content_overflow"] for f in legacy.values())
    bounds_rows.append(("第一轮复测", len(legacy), counts[True],
                        f"{100 * counts[True] / max(1, len(legacy)):.1f}%", counts[False], counts[None]))
    lines += [markdown_table(("样本集", "文件", "溢出", "占比", "框内", "未知"), bounds_rows), ""]
    web_cases = [c for c in cases if c["split"] != "legacy"]
    checked_files = {c["sample"] for c in web_cases}
    native_differences = {c["sample"] for c in web_cases
                          if c["features"] != by_id[c["sample"]]["features"]}
    lines += [
        f"PC DLL 与 Android so 对 {len(checked_files)} 个有有效计时的文件分别提取特征，"
        f"其中 {len(native_differences)} 个存在字段差异。"
        "规则拟合使用 Android 的实际原生场景特征。", "",
    ]
    lines += [markdown_table(
        ("组", "组合", ">1ms", "≤0ms", "缓存驻留中位 MiB", "齐备中位 ms"),
        [(label, len(subset), sum(c["gain_us"] > 1000 for c in subset),
          sum(c["gain_us"] <= 0 for c in subset),
          f"{statistics.median(c['bytes'] for c in subset) / MIB:.2f}",
          ms(statistics.median(c["generation_us"] for c in subset)))
         for label, subset in (
             ("框内", [c for c in web_cases if c["contained"]]),
             ("溢出或未知", [c for c in web_cases if not c["contained"]]),
         ) if subset]), ""]
    errs = [abs(c["estimated_bytes"] - c["bytes"]) for c in web_cases]
    lines += [
        f"纹理估算与设备账本完全一致 {sum(error == 0 for error in errs)}/{len(errs)} 个组合，"
        f"绝对误差中位 {statistics.median(errs):,.0f} B，最大 {max(errs):,.0f} B。"
        "运行时应在分块预留前执行硬上限。全局账本维持 32 MiB 上限，"
        "单图上限只计算当前视口及预取需要的块。", "",
    ]
    if analysis["rule"] is not None:
        opened = [c for c in web_cases if predict(c, analysis["rule"])]
        non_full_hits = Counter(c["split"] for c in opened
                                if not c["occupies_width"] and c["gain_us"] > 1000)
        non_full_gain = Counter(c["split"] for c in web_cases
                                if not c["occupies_width"] and c["contained"]
                                and c["gain_us"] > 1000)
        icon_count = Counter(c["split"] for c in web_cases if is_icon(c, by_id))
        opened_files = {c["sample"] for c in opened if c["split"] == "holdout"}
        unstable = Counter(c["split"] for c in opened if min(c["paired_gain_us"]) <= 0)
        plain = analysis["alternatives"]["取消面积下限"]
        lines += [
            f"候选单图上限为 {analysis['rule']['cap'] // MIB} MiB。"
            f"启用组合实际最高 {max((c['bytes'] for c in opened), default=0) / MIB:.2f} MiB。",
            f"框内且未铺满横轴的网上尺寸有拟合 {non_full_gain['fit']}、"
            f"留出 {non_full_gain['holdout']} 个收益超过 1ms，最终规则启用了其中 "
            f"{non_full_hits['fit']}、{non_full_hits['holdout']} 个。"
            "内容在框内的稳态路径只需覆盖内容与裁剪的交集，"
            "本轮门槛对较小尺寸仍留有明显收益空间。",
            f"拟合和留出分别覆盖 {icon_count['fit']}、{icon_count['holdout']} 个图标对照组合。"
            "外溢、未知或颜色滤镜仍走旧覆盖逻辑，自动条件统一关闭。",
            f"留出组启用覆盖 {len(opened_files)} 个不同文件。"
            f"拟合和留出启用组合中，至少一轮净收益 ≤0 的分别为 {unstable['fit']}、"
            f"{unstable['holdout']} 个。",
            (f"保留候选面积下限 {analysis['rule']['area']:,} px²。"
             f"去掉面积下限重新拟合时，留出命中 {plain['groups']['holdout']['hit']}、"
             f"误开 {plain['groups']['holdout']['false']}、漏开 {plain['groups']['holdout']['miss']}。"
             if analysis["rule"]["area"] else
             "候选只要求在屏内容面积大于 0，当前拟合未选出额外的固定面积下限。"),
            "",
        ]
    for group in ("fit", "holdout"):
        subset = [c for c in web_cases if c["split"] == group and len(c["rounds"]) == 3]
        if subset:
            metrics = evaluate(subset, analysis["rule"], by_id)
            lines += [
                f"{'拟合' if group == 'fit' else '留出'}三轮子集有 {len(subset)} 个尺寸组合，"
                f"命中 {metrics['hit']}、误开 {metrics['false']}、微利启用 {metrics['weak']}、"
                f"漏开 {metrics['miss']}。补测按收益区间和候选边界选取，统计代表该子集。", "",
            ]
    if skips:
        lines += [
            "各尺寸需完成安排的全部轮次才参与计分。以下为设备跳过记录。", "",
            markdown_table(("样本", "尺寸", "轮", "阶段", "原因"), [
                (r["sample"], r["size"], r["round"], r["stage"], r["reason"]) for r in skips
            ]), "",
            f"用 PC 场景几何检查了跳过的公开组合，候选会启用其中 "
            f"{len(analysis['eligible_skips'])} 个。这些组合缺少收益标签，独立于命中表。", "",
        ]
    else:
        lines += ["设备轮次均取得完整稳态计时。", ""]
    return lines


def report_pairs(pair, cases):
    """展示同尺寸配对和新增的 16dp 对照。"""
    lines = ["## 第一轮同样本同尺寸对比", ""]
    groups = [
        ("全部", pair),
        ("框内，图未铺满整个裁剪", [r for r in pair if r["contained"] and not r["covers_clip"]]),
        ("溢出或未知", [r for r in pair if not r["contained"]]),
        ("上一轮规则启用", [r for r in pair if r["old_enabled"]]),
    ]
    lines += [
        f"共有 {len(pair)}/120 个主矩阵组合可按相同尺寸配对。"
        "以下差值按组合计算后取中位数，缓存时间为新减旧，净收益为新减旧。", "",
        markdown_table(("分组", "配对", "缓存时间 Δms", "收益 Δms", "上一轮 >1ms", "本轮 >1ms"),
                       [(label, len(rows),
                         ms(statistics.median(r["new_cached_us"] - r["old_cached_us"] for r in rows)),
                         ms(statistics.median(r["new_gain_us"] - r["old_gain_us"] for r in rows)),
                         sum(r["old_gain_us"] > 1000 for r in rows),
                         sum(r["new_gain_us"] > 1000 for r in rows))
                        for label, rows in groups if rows]), "",
    ]
    highlights = { (row["sample"], row["size"]): row for row in pair }
    for sample, size in (("aurora", "200"), (LEGACY_ID, "48")):
        row = highlights.get((sample, size))
        if row:
            lines += [
                f"- `{sample}` {size}dp 的缓存耗时从 {ms(row['old_cached_us'])} 降到 "
                f"{ms(row['new_cached_us'])}ms，净收益从 {ms(row['old_gain_us'])} 到 "
                f"{ms(row['new_gain_us'])}ms。",
            ]
    lines += [
        "",
        markdown_table(
            ("样本", "尺寸", "边界", "向量旧/新 ms", "缓存旧/新 ms",
             "收益旧/新 ms", "纹理旧/新 B"),
            [(r["sample"], r["size"], "框内" if r["contained"] else "兜底",
              f"{ms(r['old_vector_us'])} / {ms(r['new_vector_us'])}",
              f"{ms(r['old_cached_us'])} / {ms(r['new_cached_us'])}",
              f"{ms(r['old_gain_us'])} / {ms(r['new_gain_us'])}",
              f"{r['old_bytes']:,.0f} / {r['new_bytes']:,.0f}") for r in pair]), "",
    ]
    matched = {(r["sample"], r["size"]) for r in pair}
    added = [r for r in cases if r["split"] == "legacy" and (r["sample"], r["size"]) not in matched]
    if added:
        lines += ["### 补充的第一轮样本尺寸", "",
                  markdown_table(("样本", "尺寸", "缓存 ms", "收益 ms", "纹理 B"),
                                 [(r["sample"], r["size"], ms(r["cached_us"]),
                                   ms(r["gain_us"]), f"{r['bytes']:,.0f}") for r in added]), ""]
    return lines


def report_sample_lists(plan, web):
    """列出冻结的分层抽样，以及每个公开 SVG 的原生特征。"""
    by_id = {row["id"]: row for row in plan["corpus"]}
    chosen = {row["id"]: row["split"] for row in web}
    by_category = defaultdict(Counter)
    for row in plan["corpus"]:
        counts = by_category[row["category"]]
        counts["all"] += 1
        if row["id"] in chosen:
            counts[chosen[row["id"]]] += 1
    selected = [by_id[sample] for sample in chosen]
    native = Counter({
        key: sum(row["features"][key] > 0 for row in selected)
        for key in ("masks", "blurs", "patterns", "images")
    })
    maximum_text = max(int(row["text_count"] or 0) for row in selected)
    maximum_paths = max(row["features"]["paths"] for row in selected)
    lines = [
        "## 分层抽样清单", "",
        f"覆盖 {len({row['category'] for row in selected})} 个类别、"
        f"{len({tuple(row['stratum']) for row in web})} 个分层。"
        f"抽到的原生场景中，遮罩 {native['masks']}、模糊 {native['blurs']}、"
        f"图案 {native['patterns']}、内嵌位图 {native['images']} 张。"
        f"单文件最多 {maximum_paths:,} 条原生路径，最多 {maximum_text} 个源文字节点。", "",
        markdown_table(("类别", "全集", "拟合", "留出"),
                       [(category, r["all"], r["fit"], r["holdout"])
                        for category, r in sorted(by_category.items())]), "",
        markdown_table(("编号", "划分", "类别", "体积档", "主要特性", "文件", "来源 / 许可证"), [
            (r["id"], "拟合" if r["split"] == "fit" else "留出", *r["stratum"],
             by_id[r["id"]]["file"], f"[来源]({by_id[r['id']]['source_url']}) / {by_id[r['id']]['license']}")
            for r in sorted(web, key=lambda row: row["id"])
        ]), "", "## PC 全集特征表", "",
    ]
    counts = Counter(r["status"] for r in plan["corpus"])
    lines += [
        "解析状态。 " + "，".join(f"`{status}` {count}" for status, count in counts.items())
        + f"。复杂度预算拒绝 {counts['complexity_budget']} 个。", "",
        markdown_table(("编号", "公开文件", "类别", "源字节", "原生状态", "P/V/点/描/渐/透/裁/遮/糊/图/案",
                        "固有框 W×H", "保守内容框 L/T/R/B", "面积 px²", "占比", "溢出"),
                       [corpus_row(row) for row in plan["corpus"]]),
    ]
    return lines


def corpus_row(row):
    """紧凑显示一条全量原生特征，完整精度留在 JSON。"""
    head = (row["id"], row["file"], row["category"], row["bytes"], row["status"])
    f = row.get("features")
    if f is None:
        return (*head, "—", "—", "—", "—", "—", "—")
    box = f["content_bounds"]
    return (*head, "/".join(str(f[key]) for key in FEATURES),
            f"{f['picture_width']:.2f} × {f['picture_height']:.2f}",
            "/".join(f"{value:.2f}" for value in box) if box else "—",
            f"{f['content_area']:,.2f}" if box else "—",
            f"{f['content_area_ratio']:.5f}" if f["content_area_ratio"] is not None else "—",
            "是" if f["content_overflow"] else "否" if box else "—")


def pack_output(destination, value):
    """保留逐帧列表的紧凑性，同时给顶层数组每项单独一行。"""
    destination = Path(destination)
    temp = destination.with_suffix(".tmp")
    with temp.open("w", encoding="utf-8", newline="\n") as sink:
        sink.write("{\n")
        for index, (key, content) in enumerate(value.items()):
            if index:
                sink.write(",\n")
            sink.write(json.dumps(key) + ":")
            encode = lambda obj: json.dumps(obj, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
            if isinstance(content, list):
                sink.write("[\n")
                sink.write(",\n".join(map(encode, content)))
                sink.write("\n]")
            else:
                sink.write(encode(content))
        sink.write("\n}\n")
    temp.replace(destination)


def main():
    """验证所有预期数据，冻结最终拟合后才计算留出成绩。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", type=Path, default=Path(".dart_tool/raster_cache_auto_r2"))
    parser.add_argument("--first", type=Path, default=Path("../raster_cache_auto_raw.json"))
    parser.add_argument("--dll", type=Path,
                        default=Path("../../rust/target/x86_64-pc-windows-msvc/release/xvg.dll"))
    parser.add_argument("--report", type=Path, default=Path("../raster_cache_auto_threshold_r2.md"))
    parser.add_argument("--raw", type=Path, default=Path("../raster_cache_auto_r2_raw.json"))
    arg = parser.parse_args()
    plan = load_json(arg.scratch / "plan.json")
    time_budget = load_json(arg.scratch / "time_budget.json")
    confirmation = load_json(arg.scratch / "confirmation.json")
    batches = load_lines(arg.scratch / "batches.jsonl")
    sessions = load_lines(arg.scratch / "sessions.jsonl")
    recovery_path = arg.scratch / "initial_recovery.json"
    initial_recovery = load_json(recovery_path) if recovery_path.exists() else None
    assert sessions[-1]["cleanup"] and sessions[-1]["stay_awake_restored"]
    assert all(s["apk_so_sha256"] == LIB_HASH for s in sessions)
    web = reduce_plan(plan["web"], plan["pilot"], time_budget["target"])
    cases, skips, total = collect(plan, web, confirmation["sizes_by_sample"], batches)
    by_id = {row["id"]: row for row in plan["corpus"]}
    train = [c for c in cases if c["split"] == "fit"]
    holdout = [c for c in cases if c["split"] == "holdout"]
    rule = fit(train, by_id)
    alternatives = {
        "限制满宽": fit(train, by_id, "full_width"),
        "双轴兜底": fit(train, by_id, "legacy_fallback"),
        "取消面积下限": fit(train, by_id, fixed_area=0),
        "仅点数": fit(train, by_id, allow_blur=False),
    }
    save_json(arg.scratch / "frozen_final_rules.json", {"rule": rule, "alternatives": alternatives})
    groups = lambda candidate: {
        "fit": evaluate(train, candidate, by_id), "holdout": evaluate(holdout, candidate, by_id),
    }
    baseline = next(r for b in batches for r in b["accepted"] if r["type"] == "baseline")
    analysis = {"rule": rule, "groups": groups(rule),
                "eligible_skips": check_skipped_eligibility(skips, by_id, rule, baseline),
                "alternatives": {key: {"rule": alt, "groups": groups(alt)}
                                 for key, alt in alternatives.items()}}
    pairs = paired_results(load_json(arg.first), cases)
    dll_hash = sha256(arg.dll)
    report = stage_report(plan, web, time_budget, confirmation, batches, sessions,
                          cases, skips, pairs, analysis, total, dll_hash, initial_recovery)
    pack_output(arg.raw, {
        "metadata": {"seed": plan["seed"], "flutter": "3.50.1",
                     "engine": "4d35714800b9266b6693a58e1225ecd7e9e45ed7",
                     "windows_dll_sha256": dll_hash, "apk_so_sha256": LIB_HASH,
                     "time_budget": time_budget, "pilot": plan["pilot"], "legacy": plan["legacy"],
                     "area_grid": AREA_GRID, "point_grid": POINT_GRID, "blur_area_grid": EFFECT_GRID,
                     "byte_cap_grid": CAP_GRID},
        "sessions": sessions, "confirmation": confirmation, "frozen_web_plan": plan["web"],
        "initial_recovery": initial_recovery,
        "measured_web_plan": web, "corpus": plan["corpus"], "batches": batches,
        "cases": cases, "skips": skips, "paired_round_one": pairs, "analysis": analysis,
    })
    arg.report.write_text(report, encoding="utf-8", newline="\n")
    print(json.dumps(analysis, ensure_ascii=False))


if __name__ == "__main__":
    main()
