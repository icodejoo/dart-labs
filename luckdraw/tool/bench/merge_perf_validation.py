"""合并分组串行测试产物；只重编号事件 ID，不修改测试名称、状态或断言结果。"""

import argparse
import json
from pathlib import Path


def remap(value, offset):
    """为每个独立 JSON reporter 运行分配独立 ID 区间。"""
    if not isinstance(value, dict):
        return value
    result = {}
    for key, item in value.items():
        if key in ("id", "suiteID", "parentID", "testID") and isinstance(item, int):
            result[key] = item + offset
        elif key == "groupIDs":
            result[key] = [identifier + offset for identifier in item]
        elif isinstance(item, dict):
            result[key] = remap(item, offset)
        else:
            result[key] = item
    return result


def main():
    """要求每组完整成功，合并 LCOV 行命中，保留全部原始分组文件。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", default="coverage/perf_logs")
    parser.add_argument("--groups", nargs="+", default=["core", "games", "parity", "tools"])
    args = parser.parse_args()
    directory = Path(args.directory)
    merged = []
    counts = {"passed": 0, "skipped": 0, "groups": {}}
    elapsed = 0
    coverage = {}
    for number, group in enumerate(args.groups):
        events = [json.loads(line) for line in (directory / f"{group}.jsonl").read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        done = [event for event in events if event.get("type") == "done"]
        if len(done) != 1 or done[0].get("success") is not True:
            raise ValueError(f"分组失败或未完成：{group}")
        passed = skipped = 0
        for event in events:
            kind = event.get("type")
            if kind == "testDone" and not event.get("hidden"):
                if event.get("skipped"):
                    skipped += 1
                elif event.get("result") == "success":
                    passed += 1
                else:
                    raise ValueError(f"分组包含失败：{group}")
            if kind in ("start", "allSuites", "done"):
                continue
            transformed = remap(event, number * 1000000)
            if isinstance(transformed.get("time"), int):
                transformed["time"] += elapsed
            merged.append(transformed)
        elapsed += done[0].get("time", 0)
        counts["passed"] += passed
        counts["skipped"] += skipped
        counts["groups"][group] = {"passed": passed, "skipped": skipped,
                                   "json_id_offset": number * 1000000}
        source = None
        for line in Path(f"coverage/PERF_{group}.lcov").read_text(encoding="utf-8").splitlines():
            if line.startswith("SF:"):
                path = line[3:].replace("\\", "/")
                prefix = Path.cwd().resolve().as_posix() + "/"
                if path.startswith(prefix):
                    path = path[len(prefix):]
                source = path if path.startswith("lib/") else None
                if source is not None:
                    coverage.setdefault(source, {})
            elif line.startswith("DA:") and source is not None:
                line_number, hits, *_ = line[3:].split(",")
                records = coverage[source]
                records[int(line_number)] = records.get(int(line_number), 0) + int(hits)
            elif line == "end_of_record":
                source = None
    merged.append({"type": "done", "success": True, "time": elapsed})
    (directory / "merged.jsonl").write_text("".join(json.dumps(event, ensure_ascii=False) + "\n" for event in merged), encoding="utf-8", newline="\n")
    (directory / "summary.json").write_text(json.dumps(counts, indent=2) + "\n", encoding="utf-8", newline="\n")
    lines = []
    for source, records in sorted(coverage.items()):
        lines.append(f"SF:{source}")
        lines.extend(f"DA:{line},{hits}" for line, hits in sorted(records.items()))
        lines.extend((f"LF:{len(records)}", f"LH:{sum(hits > 0 for hits in records.values())}", "end_of_record"))
    Path("coverage/PERF.lcov").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"PASS: {counts['passed']} passed / {counts['skipped']} skipped; merged {len(coverage)} lib records")


if __name__ == "__main__":
    main()
