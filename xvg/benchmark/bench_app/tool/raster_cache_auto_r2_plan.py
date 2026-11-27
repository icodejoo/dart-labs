"""按清单和 Windows 原生特征冻结第二轮的按文件抽样计划。"""

import csv
import json
import random
from collections import Counter, defaultdict
from pathlib import Path

SEED = 20261127
WEB_SIZES = ("48", "200", "full")
LEGACY_SIZES = ("16", *WEB_SIZES)
SCREEN_TARGET = 200
MINIMUM_TARGET = 120
FEATURES = ("paths", "verbs", "points", "strokes", "gradients", "opacity",
            "clips", "masks", "blurs", "images", "patterns")


def load_json(path):
    """读取 UTF-8 JSON 或 PowerShell 写入的带 BOM JSON。"""
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def load_lines(path):
    """逐行读取原始记录。"""
    with Path(path).open(encoding="utf-8-sig") as source:
        return [json.loads(line) for line in source if line.strip()]


def save_json(path, value):
    """原子保存计划或检查点，避免进程终止后留下半份 JSON。"""
    path = Path(path)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")),
                    encoding="utf-8")
    temp.replace(path)


def manifest_rows(corpus):
    """保持源清单次序，让公开样本编号跨运行稳定。"""
    with (corpus / "manifest.csv").open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))
    assert len(rows) == 714 and len({row["file"] for row in rows}) == len(rows)
    for index, row in enumerate(rows, 1):
        row["id"] = f"web-{index:03d}"
        assert (corpus / "files" / row["file"]).is_file(), row["id"]
    return rows


def stratum(row, features):
    """以互斥特性优先级覆盖少见的渲染成本来源。"""
    size = int(row["bytes"])
    size_bin = ("<4KiB" if size < 4096 else "4–<32KiB" if size < 32768
                else "32–<256KiB" if size < 262144 else "≥256KiB")
    flag = lambda name: int(row[name] or 0) > 0
    if flag("image_count") or features["images"]:
        main = "bitmap"
    elif flag("has_blur") or features["blurs"]:
        main = "blur"
    elif flag("has_mask") or features["masks"]:
        main = "mask"
    elif flag("has_pattern") or features["patterns"]:
        main = "pattern"
    elif flag("text_count"):
        main = "text"
    elif features["paths"] >= 1000 or features["points"] >= 10000:
        main = "dense"
    elif flag("has_filter") or features["clips"] or features["gradients"] or features["opacity"]:
        main = "paint"
    else:
        main = "plain"
    return row["category"], size_bin, main


def make_plan(manifest, native, legacy_runs):
    """在任何设备计时前冻结全部候选、文件级组别和十个试跑样本。"""
    assert len(native) == len(manifest), (len(native), len(manifest))
    native_by_id = {row["id"]: row for row in native}
    table = []
    strata = defaultdict(list)
    for row in manifest:
        parsed = native_by_id[row["id"]]
        record = {**row, **parsed}
        table.append(record)
        if record["status"] == "ok":
            record["stratum"] = stratum(row, record["features"])
            strata[record["stratum"]].append(record["id"])
    assert sum(map(len, strata.values())) >= SCREEN_TARGET
    randomizer = random.Random(SEED)
    keys = sorted(strata)
    randomizer.shuffle(keys)
    for pool in strata.values():
        randomizer.shuffle(pool)
    selected = defaultdict(list)
    for _ in range(SCREEN_TARGET):
        # 覆盖各非空层，再按该层尚未抽取的比例分配额外配额。
        key = max((key for key in keys if strata[key]), key=lambda key: (
            not selected[key], len(strata[key]) / (len(selected[key]) + 1)))
        selected[key].append(strata[key].pop())

    holdouts = {
        key: (int(len(group) * 0.30) if len(group) > 2 else 0)
        for key, group in selected.items()
    }
    holdout_target = round(SCREEN_TARGET * 0.30)
    while sum(holdouts.values()) < holdout_target:
        key = max((key for key in keys if holdouts.get(key, 0) < len(selected[key])),
                  key=lambda key: len(selected[key]) * 0.30 - holdouts[key])
        holdouts[key] += 1
    web = []
    for key, group in selected.items():
        for index, sample in enumerate(group):
            web.append({
                "id": sample, "stratum": key,
                "split": "holdout" if index < holdouts[key] else "fit",
            })
    randomizer.shuffle(web)
    counts = Counter(group["split"] for group in web)
    assert counts == {"fit": 140, "holdout": 60}, counts
    pilot = []
    seen = [Counter(), Counter(), Counter(), Counter()]
    for _ in range(10):
        def novelty(row):
            """优先选择仍未出现的特性、类别及体积档。"""
            category, size, feature = row["stratum"]
            return (-seen[0][feature], -seen[1][category],
                    -seen[2][size], -seen[3][row["split"]])
        choice = max((row for row in web if row["id"] not in pilot), key=novelty)
        pilot.append(choice["id"])
        category, size, feature = choice["stratum"]
        for counter, key in zip(seen, (feature, category, size, choice["split"])):
            counter[key] += 1
    legacy = {}
    for run in legacy_runs:
        name = "legacy-014" if run["sample"] == "233KB" else run["sample"]
        legacy[name] = "holdout" if run["validation"] else "fit"
    assert len(legacy) == 38
    return {"seed": SEED, "corpus": table, "web": web, "pilot": pilot,
            "legacy": legacy}


def reduce_plan(web, pilot, target):
    """保留试跑样本和原组别，在两组内按原分层比例缩减样本。"""
    if target >= len(web):
        return web
    picked = set(pilot)
    for split, count in (("holdout", round(target * .30)),
                         ("fit", target - round(target * .30))):
        candidates = [row for row in web if row["split"] == split]
        key = lambda row: tuple(row["stratum"])
        totals = Counter(key(row) for row in candidates)
        used = Counter(key(row) for row in candidates if row["id"] in picked)
        for _ in range(count - sum(used.values())):
            item = max((row for row in candidates if row["id"] not in picked),
                       key=lambda row: count * totals[key(row)] / len(candidates)
                       - used[key(row)])
            picked.add(item["id"])
            used[key(item)] += 1
    assert len(picked) == target
    return [row for row in web if row["id"] in picked]
