#!/usr/bin/env python3
"""WHEP 丢包基线（NACK/PLI 尚未实现时的参照数字，供 T1.5 对比）。仅用标准库，在 WSL 里跑。

对每个 (丢包率, 序号) 起一个 whep_tamper_proxy.py（lossy 模式，只丢包，SWAP/DUP/CORRUPT 置 0，
每次随机种子不同且写进结果），再用带 whep 的 ffmpeg 拉 --duration 秒，收集：
  注入侧   中继 trace（每个 RTP 一行：序号,相对秒,seq,rtp时间戳,pt,marker,动作,长度）
  客户端   verbose 日志里的 "RTP video/audio ... packets/auth_fail/late/lost/frames/dropped_frames/before_keyframe"
  解码侧   ffmpeg 的 "N decode errors"、"corrupt decoded frame"、"concealing ... errors" 行数、解码帧数、音频采样数
  实测间隙 -c copy 的 framecrc：音频 pts 空洞、视频 pts 空洞（实际送到解码器的画面停顿）
  推断     按 trace 里的"丢了包的视频帧 + 按帧大小识别的 IDR"推算花屏/冻结窗口（到下一个完整 IDR 的时长）

用法（WSL）：
  python3 whep_loss_baseline.py --ffmpeg /root/w/ffb-plain2/ffmpeg --proxy ./whep_tamper_proxy.py \\
      --up-url http://127.0.0.1:18889 --media-port 18189 --out /root/w/whep-target-b/lossy-run
"""
import argparse
import json
import os
import re
import signal
import statistics
import subprocess
import time

AUDIO_PT, VIDEO_PT = 111, 102
MIX = dict(LOSS="2", SWAP="2", DUP="1", CORRUPT="1")   # rates 里写 mix 时的混合故障比例（百分数）
OPUS_SAMPLES = 960          # 20ms @ 48k
V_TICK = 90000


def parse_trace(path):
    """读 trace，返回按到达顺序的 [(idx, t, seq, ts, pt, marker, act, ln)]。"""
    rows = []
    for ln in open(path):
        p = ln.strip().split(",")
        if len(p) < 7:
            continue
        rows.append((int(p[0]), float(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5]), p[6],
                     int(p[7]) if len(p) > 7 else 0))
    return rows


def video_frames(rows):
    """把视频包按 rtp 时间戳聚成帧：{ts, pkts, bytes, lost(丢了几个包)}，按出现顺序。"""
    frames, cur = [], None
    for r in rows:
        if r[4] != VIDEO_PT:
            continue
        if cur is None or cur["ts"] != r[3]:
            cur = {"ts": r[3], "pkts": 0, "bytes": 0, "lost": 0}
            frames.append(cur)
        cur["pkts"] += 1
        cur["bytes"] += r[7]
        if r[6] in ("drop", "corrupt"):
            cur["lost"] += 1
    return frames


def model_windows(frames):
    """推断花屏窗口（按 trace 里的帧结构，不是解码器实测）。

    IDR = 帧字节数 > 3 倍中位数（载荷已加密，只能按大小认）。客户端起播后不再等 IDR（只有起播时
    seen_key 之前才丢 P 帧，对应 before_keyframe），所以起播后任何一个受损帧（含整帧丢光的
    单包帧）都会让后续 P 帧参考错位，直到下一个**完整**的 IDR：窗口 = 受损帧时间戳 -> 下一个完整 IDR
    的时间戳；窗口内再丢包不新开窗口，窗口内的 IDR 受损则窗口延长到再下一个。
    起播阶段（第一个完整 IDR 之前）单独统计 startup_frames，不算花屏。
    返回 dict，字段见代码。
    """
    if not frames:
        return {}
    med = statistics.median(f["bytes"] for f in frames)
    for f in frames:
        f["idr"] = f["bytes"] > 3 * med
    idrs = [f for f in frames if f["idr"]]
    state, start_ts, wins = "WAIT", 0, []
    startup_frames = 0
    for f in frames:
        if state == "WAIT":
            if f["idr"] and not f["lost"]:
                state = "OK"
            else:
                startup_frames += 1
            continue
        if state == "OK":
            if f["lost"]:
                state, start_ts = "GARBLED", f["ts"]
            continue
        if f["idr"] and not f["lost"]:
            wins.append(((f["ts"] - start_ts) & 0xffffffff) / V_TICK)
            state = "OK"
    open_s = ((frames[-1]["ts"] - start_ts) & 0xffffffff) / V_TICK if state == "GARBLED" else None
    lost = [f for f in frames if f["lost"]]
    return {
        "frames": len(frames), "idr_total": len(idrs),
        "idr_avg_pkts": round(statistics.mean(f["pkts"] for f in idrs), 1) if idrs else 0,
        "idr_with_loss": sum(1 for f in idrs if f["lost"]),
        "lost_frames": len(lost),
        "lost_whole_frames": sum(1 for f in lost if f["lost"] == f["pkts"]),
        "startup_frames": startup_frames,
        "garble_events": len(wins), "garbled_s": round(sum(wins), 3),
        "garble_avg_s": round(sum(wins) / len(wins), 3) if wins else 0.0,
        "garble_max_s": round(max(wins), 3) if wins else 0.0,
        "open_window_s": round(open_s, 3) if open_s is not None else None,
    }


def crc_gaps(path, tick, expect):
    """framecrc 里相邻包 pts 差大于 expect*1.5 的空洞：返回 (空洞数, 累计缺失秒, 最长缺失秒)。"""
    pts = []
    for ln in open(path):
        if ln.startswith("#") or not ln.strip():
            continue
        p = [x.strip() for x in ln.split(",")]
        pts.append(int(p[2]))
    pts.sort()
    gaps = [(b - a - expect) / tick for a, b in zip(pts, pts[1:]) if b - a > expect * 1.5]
    return len(pts), len(gaps), round(sum(gaps), 3), round(max(gaps), 3) if gaps else 0.0


def audio_runs(rows):
    """trace 里音频连续丢包的游程：(游程数, 最长连续丢包数)。"""
    best = cur = runs = 0
    for r in rows:
        if r[4] != AUDIO_PT:
            continue
        if r[6] in ("drop", "corrupt"):
            if cur == 0:
                runs += 1
            cur += 1
            best = max(best, cur)
        else:
            cur = 0
    return runs, best


def one_run(a, rate, k, seed, extra_env=None):
    d = os.path.join(a.out, "r%s_%d" % (str(rate).replace(".", "p"), k))
    prof = MIX if rate == "mix" else dict(LOSS=str(rate), SWAP="0", DUP="0", CORRUPT="0")
    os.makedirs(d, exist_ok=True)
    env = dict(os.environ, SEED=str(seed), **prof)
    env.update(
               UP_URL=a.up_url, MEDIA_PORT=str(a.media_port), RELAY_PORT=str(a.relay_port),
               SILENT_PORT=str(a.relay_port + 1), TRACE=os.path.join(d, "trace.csv"))
    px = subprocess.Popen(["python3", a.proxy, str(a.http_port)], env=env,
                          stdout=open(os.path.join(d, "proxy.log"), "w"), stderr=subprocess.STDOUT)
    time.sleep(1.0)
    url = "whep+http://127.0.0.1:%d/lossy/test/whep" % a.http_port
    cmd = [a.ffmpeg, "-hide_banner", "-nostats", "-v", "verbose", "-t", str(a.duration), "-f", "whep"] + a.ffopts.split() + ["-i", url,
           "-map", "0:v", "-vf", "null" if a.no_showinfo else "showinfo", "-f", "null", "-",
           "-map", "0:a", "-f", "null", "-",
           "-map", "0:v", "-c", "copy", "-f", "framecrc", os.path.join(d, "v.crc"),
           "-map", "0:a", "-c", "copy", "-f", "framecrc", os.path.join(d, "a.crc")]
    with open(os.path.join(d, "client.log"), "w") as lg:
        rc = subprocess.run(cmd, stdout=lg, stderr=subprocess.STDOUT, timeout=a.duration + 60).returncode
    px.send_signal(signal.SIGTERM)
    px.wait(timeout=10)
    log = open(os.path.join(d, "client.log"), errors="replace").read()
    rows = parse_trace(os.path.join(d, "trace.csv"))
    res = {"rate": rate, "run": k, "seed": seed, "exit": rc}
    final = re.findall(r"relay FINAL (\{.*\})", open(os.path.join(d, "proxy.log")).read())
    res["relay_final"] = final[-1] if final else None
    for kind in ("video", "audio"):
        m = re.search(r"RTP %s pt=\d+: packets=(\d+) auth_fail=(\d+) late/dup=(\d+) lost=(\d+) frames=(\d+) "
                      r"dropped_frames=(\d+) before_keyframe=(\d+)" % kind, log)
        res[kind + "_client"] = dict(zip(("packets", "auth_fail", "late", "lost", "frames", "dropped_frames",
                                          "before_keyframe"), map(int, m.groups()))) if m else None
        vt = VIDEO_PT if kind == "video" else AUDIO_PT
        res[kind + "_inject"] = {"seen": sum(1 for r in rows if r[4] == vt)}
        for act in ("drop", "corrupt", "dup", "swap"):
            res[kind + "_inject"][act] = sum(1 for r in rows if r[4] == vt and r[6] == act)
    m = re.search(r"Input stream #0:1 \(video\): (\d+) packets read.*?(\d+) frames decoded; (\d+) decode errors", log)
    res["video_decode"] = {"pkts_read": int(m.group(1)), "frames_decoded": int(m.group(2)),
                           "decode_errors": int(m.group(3))} if m else None
    m = re.search(r"Input stream #0:0 \(audio\): (\d+) packets read.*?(\d+) frames decoded; (\d+) decode errors "
                  r"\((\d+) samples\)", log)
    res["audio_decode"] = {"pkts_read": int(m.group(1)), "frames_decoded": int(m.group(2)),
                           "decode_errors": int(m.group(3)), "samples": int(m.group(4))} if m else None
    # T1.5：RTCP 反馈计数与起播计时（旧构建没有这些行，则为 None）
    for kind in ("video", "audio"):
        m2 = re.search(r"RTCP %s: nack=(\d+) pli_on=(\d+) nack_seqs_sent=(\d+) nack_msgs=(\d+) nack_giveup=(\d+) "
                      r"rtx_recovered=(\d+) rtx_late=(\d+) pli_sent=(\d+) rr_sent=(\d+)" % kind, log)
        res[kind + "_rtcp"] = dict(zip(("nack", "pli_on", "nack_seqs", "nack_msgs", "giveup", "rtx_recovered",
                                        "rtx_late", "pli_sent", "rr_sent"), map(int, m2.groups()))) if m2 else None
    m2 = re.search(r"First RTP packet \((\w+)\) at ([\d.]+)ms", log)
    res["first_pkt_ms"] = float(m2.group(2)) if m2 else None
    m2 = re.search(r"First video key frame out at ([\d.]+)ms", log)
    res["first_key_ms"] = float(m2.group(1)) if m2 else None
    res["corrupt_decoded_frame_lines"] = len(re.findall(r"corrupt decoded frame", log))
    res["concealing_lines"] = len(re.findall(r"concealing \d+ DC", log))
    res["other_error_lines"] = len([ln for ln in log.splitlines()
                                    if re.search(r"error|invalid|Invalid", ln, re.I) and "concealing" not in ln
                                    and "decode errors" not in ln and "auth_fail" not in ln and "RTP " not in ln
                                    and "Parsed_showinfo" not in ln and "a=" not in ln[:3]])
    ap, agaps, amiss, amax = crc_gaps(os.path.join(d, "a.crc"), 48000, OPUS_SAMPLES)
    res["audio_pts"] = {"pkts": ap, "gaps": agaps, "missing_s": amiss, "max_gap_s": amax}
    vp, vgaps, vmiss, vmax = crc_gaps(os.path.join(d, "v.crc"), V_TICK, 3600)
    res["video_pts"] = {"pkts": vp, "gaps": vgaps, "missing_s": vmiss, "max_gap_s": vmax}
    res["audio_drop_runs"], res["audio_drop_longest"] = audio_runs(rows)
    res["model"] = model_windows(video_frames(rows))
    keys = re.findall(r"n:\s*\d+ pts:\s*(\d+) .*? iskey:(\d)", log)
    res["showinfo_frames"] = len(keys)
    res["showinfo_keyframes"] = sum(1 for _, kf in keys if kf == "1")
    json.dump(res, open(os.path.join(d, "result.json"), "w"), indent=1)
    return res


def summarize(out):
    """读 all.json，按丢包档位求均值，打印 markdown 表。"""
    allres = json.load(open(os.path.join(out, "all.json")))
    groups = {}
    for r in allres:
        groups.setdefault(r["rate"], []).append(r)

    def avg(rs, fn):
        return sum(fn(r) for r in rs) / len(rs)

    cols = [
        ("档位", None),
        ("次数", lambda rs: len(rs)),
        ("注入丢(视频/音频)", lambda rs: "%.1f / %.1f" % (avg(rs, lambda r: r["video_inject"]["drop"]),
                                                      avg(rs, lambda r: r["audio_inject"]["drop"]))),
        ("客户端 lost(视频/音频)", lambda rs: "%.1f / %.1f" % (avg(rs, lambda r: r["video_client"]["lost"]),
                                                           avg(rs, lambda r: r["audio_client"]["lost"]))),
        ("auth_fail", lambda rs: "%.1f" % avg(rs, lambda r: r["video_client"]["auth_fail"] + r["audio_client"]["auth_fail"])),
        ("late/dup", lambda rs: "%.1f" % avg(rs, lambda r: r["video_client"]["late"] + r["audio_client"]["late"])),
        ("丢弃不完整帧", lambda rs: "%.1f" % avg(rs, lambda r: r["video_client"]["dropped_frames"])),
        ("受损帧(trace)", lambda rs: "%.1f" % avg(rs, lambda r: r["model"]["lost_frames"])),
        ("整帧丢光", lambda rs: "%.1f" % avg(rs, lambda r: r["model"]["lost_whole_frames"])),
        ("解码 errors", lambda rs: "%.1f" % avg(rs, lambda r: r["video_decode"]["decode_errors"] + r["audio_decode"]["decode_errors"])),
        ("corrupt 帧行", lambda rs: "%.1f" % avg(rs, lambda r: r["corrupt_decoded_frame_lines"])),
        ("concealing 行", lambda rs: "%.1f" % avg(rs, lambda r: r["concealing_lines"])),
    ]
    print("| " + " | ".join(c for c, _ in cols) + " |")
    print("|" + "---|" * len(cols))
    for rate, rs in groups.items():
        print("| %s%% | " % rate + " | ".join(str(fn(rs)) for _, fn in cols[1:]) + " |")
    print()
    cols2 = [
        ("档位", None),
        ("起播丢帧(model)", lambda rs: "%.1f" % avg(rs, lambda r: r["model"]["startup_frames"])),
        ("before_keyframe", lambda rs: "%.1f" % avg(rs, lambda r: r["video_client"]["before_keyframe"])),
        ("花屏事件", lambda rs: "%.1f" % avg(rs, lambda r: r["model"]["garble_events"])),
        ("花屏累计 s", lambda rs: "%.2f" % avg(rs, lambda r: r["model"]["garbled_s"])),
        ("花屏均长 s", lambda rs: "%.2f" % avg(rs, lambda r: r["model"]["garble_avg_s"])),
        ("花屏最长 s", lambda rs: "%.2f" % max(r["model"]["garble_max_s"] for r in rs)),
        ("IDR 平均包数", lambda rs: "%.1f" % avg(rs, lambda r: r["model"]["idr_avg_pkts"])),
        ("带损 IDR/总 IDR", lambda rs: "%.1f / %.1f" % (avg(rs, lambda r: r["model"]["idr_with_loss"]),
                                                       avg(rs, lambda r: r["model"]["idr_total"]))),
        ("视频 pts 空洞数/累计 s/最长 s", lambda rs: "%.1f / %.2f / %.2f" % (
            avg(rs, lambda r: r["video_pts"]["gaps"]), avg(rs, lambda r: r["video_pts"]["missing_s"]),
            max(r["video_pts"]["max_gap_s"] for r in rs))),
        ("音频 pts 空洞数/累计 s/最长 s", lambda rs: "%.1f / %.2f / %.2f" % (
            avg(rs, lambda r: r["audio_pts"]["gaps"]), avg(rs, lambda r: r["audio_pts"]["missing_s"]),
            max(r["audio_pts"]["max_gap_s"] for r in rs))),
        ("解码帧数(视频)", lambda rs: "%.0f" % avg(rs, lambda r: r["video_decode"]["frames_decoded"])),
        ("音频采样数", lambda rs: "%.0f" % avg(rs, lambda r: r["audio_decode"]["samples"])),
    ]
    print("| " + " | ".join(c for c, _ in cols2) + " |")
    print("|" + "---|" * len(cols2))
    for rate, rs in groups.items():
        print("| %s%% | " % rate + " | ".join(str(fn(rs)) for _, fn in cols2[1:]) + " |")
    print()
    # T1.5：RTCP 反馈计数（客户端 verbose 日志里的真实计数器）与起播计时
    def rt(r, k):
        x = r.get("video_rtcp")
        return x[k] if x else 0

    cols3 = [
        ("档位", None),
        ("NACK 序号数(视频)", lambda rs: "%.1f" % avg(rs, lambda r: rt(r, "nack_seqs"))),
        ("NACK 报文数", lambda rs: "%.1f" % avg(rs, lambda r: rt(r, "nack_msgs"))),
        ("重传恢复", lambda rs: "%.1f" % avg(rs, lambda r: rt(r, "rtx_recovered"))),
        ("重传迟到", lambda rs: "%.1f" % avg(rs, lambda r: rt(r, "rtx_late"))),
        ("放弃缺口", lambda rs: "%.1f" % avg(rs, lambda r: rt(r, "giveup"))),
        ("最终仍丢(视频)", lambda rs: "%.1f" % avg(rs, lambda r: r["video_client"]["lost"])),
        ("PLI 发出", lambda rs: "%.1f" % avg(rs, lambda r: rt(r, "pli_sent"))),
        ("RR 发出(视频)", lambda rs: "%.1f" % avg(rs, lambda r: rt(r, "rr_sent"))),
        ("首包 ms", lambda rs: "%.0f" % avg(rs, lambda r: r.get("first_pkt_ms") or 0)),
        ("首个关键帧 ms", lambda rs: "%.0f" % avg(rs, lambda r: r.get("first_key_ms") or 0)),
        ("首包到关键帧 ms", lambda rs: "%.0f" % avg(rs, lambda r: (r.get("first_key_ms") or 0) - (r.get("first_pkt_ms") or 0))),
    ]
    print("| " + " | ".join(c for c, _ in cols3) + " |")
    print("|" + "---|" * len(cols3))
    for rate, rs in groups.items():
        print("| %s%% | " % rate + " | ".join(str(fn(rs)) for _, fn in cols3[1:]) + " |")
    print()
    print("seeds:", {str(k): [r["seed"] for r in v] for k, v in groups.items()})


def reanalyze(out):
    """只用已落盘的 trace 重算 model / audio 游程（改了推断算法后不用重跑），并重写 result.json 与 all.json。"""
    allres = json.load(open(os.path.join(out, "all.json")))
    for r in allres:
        d = os.path.join(out, "r%s_%d" % (str(r["rate"]).replace(".", "p"), r["run"]))
        rows = parse_trace(os.path.join(d, "trace.csv"))
        r["model"] = model_windows(video_frames(rows))
        r["audio_drop_runs"], r["audio_drop_longest"] = audio_runs(rows)
        json.dump(r, open(os.path.join(d, "result.json"), "w"), indent=1)
    json.dump(allres, open(os.path.join(out, "all.json"), "w"), indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summarize", action="store_true", help="只读 --out/all.json 打印汇总表")
    ap.add_argument("--reanalyze", action="store_true", help="用已落盘的 trace 重算推断部分")
    ap.add_argument("--no-showinfo", action="store_true", help="ffmpeg 没编 showinfo 滤镜时用（ASan 构建）")
    ap.add_argument("--ffmpeg")
    ap.add_argument("--proxy")
    ap.add_argument("--up-url", default="http://127.0.0.1:8889")
    ap.add_argument("--media-port", type=int, default=8189)
    ap.add_argument("--http-port", type=int, default=28100)
    ap.add_argument("--relay-port", type=int, default=28201)
    ap.add_argument("--duration", type=int, default=30)
    ap.add_argument("--rates", default="0,0.5,2,5")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--ffopts", default="", help="加在 -i 之前的额外输入选项，如 '-rtcp_nack 0'")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    if a.reanalyze:
        reanalyze(a.out)
        return
    if a.summarize:
        summarize(a.out)
        return
    os.makedirs(a.out, exist_ok=True)
    allres = []
    for tok in a.rates.split(","):
        rate = "mix" if tok == "mix" else float(tok)
        for k in range(1, (1 if rate == 0 else a.runs) + 1):
            seed = (777 if rate == "mix" else int(rate * 100) * 100) + k * 7 + 1000
            r = one_run(a, rate, k, seed)
            allres.append(r)
            print(json.dumps(r), flush=True)
    json.dump(allres, open(os.path.join(a.out, "all.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
