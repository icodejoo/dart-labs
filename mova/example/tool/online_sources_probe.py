#!/usr/bin/env python3
"""在线测试源批量复测：先 ffprobe 看元数据，再用 mova 裁剪版 libmpv 实际播放。

用法（务必加 -I，避免当前目录的同名模块被误导入）：
    python -I online_sources_probe.py                      # 测 online_sources.json 全部源
    python -I online_sources_probe.py --only hls-vod-mux   # 只测指定 id（可重复/逗号分隔）
    python -I online_sources_probe.py --kind live          # 只测直播
    python -I online_sources_probe.py --alternatives       # 主地址失败时依次试 alternatives
    python -I online_sources_probe.py --ffprobe-only       # 没有 dll 时退化为只用 ffprobe
    python -I online_sources_probe.py --json cand.json --out result.json --label r1

判定：
  - expect=play：首次拿到 time-pos 后 10 秒内至少推进 3 秒为可播；直播再隔 20 秒，
    至少再推进 10 秒（且未收到 END_FILE）才算通过。
  - expect=reject：必须在限时内收到 END_FILE(error)，且从未推进满 3 秒；不报错也不推进
    （挂起）算失败。
默认 dll 取仓库内 libmpv/windows-x86_64-whep/libmpv-2.dll；该文件是 Git LFS 指针时，
先 `git lfs fetch --include=...` 取对象，再用 --dll 指向复制出来的真实文件。
"""
import argparse
import concurrent.futures as cf
import ctypes
import json
import os
import subprocess
import sys
import time

# ---- 常量 ----
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_JSON = os.path.join(HERE, 'online_sources.json')
DEFAULT_DLL = os.path.normpath(os.path.join(HERE, '..', '..', 'libmpv', 'windows-x86_64-whep', 'libmpv-2.dll'))
# 与 lib/src/core/kernel/mpv_defaults.dart 的 movaProtocolWhitelist() 保持一致
MOVA_WHITELIST = ['udp', 'rtp', 'tcp', 'tls', 'data', 'file', 'http', 'https', 'crypto', 'dtls']
# 与 media_kit 1.2.6 注入的 demuxer-lavf-o 前缀保持一致
LAVF_BASE_OPTS = ['seg_max_retry=5', 'strict=experimental', 'allowed_extensions=ALL']
OPEN_TIMEOUT = 25.0     # 等到第一个 time-pos 的上限（秒）
WINDOW = 10.0           # 首个 time-pos 之后的观察窗口（秒）
NEED_ADVANCE = 3.0      # 窗口内需推进的播放秒数
LIVE_GAP = 20.0         # 直播二次确认间隔（秒）
LIVE_NEED = 10.0        # 直播二次确认期间需再推进的秒数
REJECT_TIMEOUT = 25.0   # 反例等待明确错误的上限（秒）
FFPROBE_TIMEOUT = 45.0  # ffprobe 子进程硬超时（秒）
POLL = 0.25             # time-pos 轮询间隔（秒）
MAX_LOG_LINES = 10      # 保留的 mpv warn 以上日志行数

EV_SHUTDOWN, EV_LOG, EV_START_FILE, EV_END_FILE, EV_FILE_LOADED = 1, 2, 6, 7, 8
END_REASONS = {0: 'eof', 2: 'stop', 3: 'quit', 4: 'error', 5: 'redirect'}
META_PROPS = ['file-format', 'current-tracks/video/codec', 'video-format', 'audio-codec-name', 'video-params/w', 'video-params/h',
              'duration', 'seekable', 'container-fps', 'hwdec-current']


class EvLog(ctypes.Structure):
    """mpv_event_log_message 的内存布局。"""
    _fields_ = [('prefix', ctypes.c_char_p), ('level', ctypes.c_char_p),
                ('text', ctypes.c_char_p), ('log_level', ctypes.c_int)]


class EvEnd(ctypes.Structure):
    """mpv_event_end_file 的内存布局。"""
    _fields_ = [('reason', ctypes.c_int), ('error', ctypes.c_int),
                ('playlist_entry_id', ctypes.c_int64), ('playlist_insert_id', ctypes.c_int64),
                ('playlist_insert_num_entries', ctypes.c_int)]


class Ev(ctypes.Structure):
    """mpv_event 的内存布局。"""
    _fields_ = [('event_id', ctypes.c_int), ('error', ctypes.c_int),
                ('reply_userdata', ctypes.c_uint64), ('data', ctypes.c_void_p)]


def load_mpv(dll_path):
    """加载 libmpv 并声明用到的函数原型，返回 ctypes 库对象。"""
    lib = ctypes.CDLL(os.path.abspath(dll_path))
    lib.mpv_create.restype = ctypes.c_void_p
    lib.mpv_initialize.argtypes = [ctypes.c_void_p]
    lib.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.mpv_command.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
    lib.mpv_get_property_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.mpv_get_property_string.restype = ctypes.c_void_p
    lib.mpv_free.argtypes = [ctypes.c_void_p]
    lib.mpv_wait_event.argtypes = [ctypes.c_void_p, ctypes.c_double]
    lib.mpv_wait_event.restype = ctypes.POINTER(Ev)
    lib.mpv_request_log_messages.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]
    lib.mpv_error_string.argtypes = [ctypes.c_int]
    lib.mpv_error_string.restype = ctypes.c_char_p
    return lib


def get_prop(lib, h, name):
    """读取 mpv 字符串属性；读不到返回 None。"""
    p = lib.mpv_get_property_string(h, name.encode())
    if not p:
        return None
    try:
        return ctypes.string_at(p).decode('utf-8', 'replace')
    finally:
        lib.mpv_free(p)


def to_float(s):
    """字符串转 float，失败返回 None。"""
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def try_sub_add(lib, h, sub_url):
    """给当前播放追加外挂字幕，最多等 6 秒看字幕轨是否出现，返回 {sub_codec / sub_error}。"""
    arr = (ctypes.c_char_p * 4)(b'sub-add', sub_url.encode(), b'select', None)
    rc = lib.mpv_command(h, arr)
    if rc < 0:
        return {'sub_error': 'sub-add: ' + lib.mpv_error_string(rc).decode()}
    end = time.monotonic() + 6.0
    while time.monotonic() < end:
        lib.mpv_wait_event(h, 0.2)
        codec = get_prop(lib, h, 'current-tracks/sub/codec')
        if codec:
            return {'sub_codec': codec}
    return {'sub_error': '6s 内未出现字幕轨'}


def entry_sub(sub_url):
    """该条目是否要求外挂字幕。"""
    return bool(sub_url)


def collect_meta(lib, h):
    """抓取容器/编码/分辨率等元信息。"""
    meta = {k: get_prop(lib, h, k) for k in META_PROPS}
    return {k: v for k, v in meta.items() if v is not None}


def play_once(dll, url, whitelist, expect, live, need_video=False, sub_url=None, open_timeout=OPEN_TIMEOUT,
              window=WINDOW, need=NEED_ADVANCE, live_gap=LIVE_GAP):
    """在当前进程里用裁剪版 libmpv 播放一次，返回结果字典（由 worker 子进程调用）。"""
    lib = load_mpv(dll)
    h = lib.mpv_create()
    if not h:
        return {'result': 'fail', 'reason': 'mpv_create 失败'}
    wl = '[' + ','.join(whitelist) + ']'
    lavf = ','.join(LAVF_BASE_OPTS + ['protocol_whitelist=' + wl])
    opts = {'vo': 'null', 'ao': 'null', 'audio-display': 'no', 'network-timeout': '15',
            'idle': 'yes', 'config': 'no', 'terminal': 'no',
            'demuxer-max-bytes': '33554432', 'demuxer-max-back-bytes': '33554432',
            'demuxer-lavf-o': lavf}
    for k, v in opts.items():
        rc = lib.mpv_set_option_string(h, k.encode(), v.encode())
        if rc < 0:
            return {'result': 'fail', 'reason': 'set option %s: %s' % (k, lib.mpv_error_string(rc).decode())}
    rc = lib.mpv_initialize(h)
    if rc < 0:
        return {'result': 'fail', 'reason': 'mpv_initialize: ' + lib.mpv_error_string(rc).decode()}
    lib.mpv_request_log_messages(h, b'warn')
    logs, out = [], {'result': 'fail'}
    t0 = time.monotonic()
    arr = (ctypes.c_char_p * 3)(b'loadfile', url.encode(), None)
    rc = lib.mpv_command(h, arr)
    if rc < 0:
        out['reason'] = 'loadfile: ' + lib.mpv_error_string(rc).decode()
        lib.mpv_terminate_destroy(h)
        return out

    first_pos = first_wall = None
    loaded = False
    max_pos = 0.0
    passed_pos = passed_wall = None
    end = None
    meta = {}
    budget = (REJECT_TIMEOUT if expect == 'reject' else open_timeout)
    deadline = t0 + budget
    live_deadline = None
    while True:
        now = time.monotonic()
        ev = lib.mpv_wait_event(h, POLL).contents
        if ev.event_id == EV_LOG and ev.data:
            m = ctypes.cast(ev.data, ctypes.POINTER(EvLog)).contents
            if len(logs) < MAX_LOG_LINES:
                txt = (m.text or b'').decode('utf-8', 'replace').strip()
                logs.append('[%s/%s] %s' % ((m.prefix or b'').decode(), (m.level or b'').decode(), txt[:200]))
        elif ev.event_id == EV_FILE_LOADED:
            out['file_loaded_ms'] = int((now - t0) * 1000)
            loaded = True
        elif ev.event_id == EV_END_FILE and ev.data:
            e = ctypes.cast(ev.data, ctypes.POINTER(EvEnd)).contents
            end = {'reason': END_REASONS.get(e.reason, str(e.reason)),
                   'error': lib.mpv_error_string(e.error).decode() if e.error < 0 else None,
                   'at_ms': int((now - t0) * 1000)}
            break
        elif ev.event_id == EV_SHUTDOWN:
            end = {'reason': 'shutdown', 'at_ms': int((now - t0) * 1000)}
            break

        pos = to_float(get_prop(lib, h, 'time-pos')) if loaded else None
        if pos is not None:
            max_pos = max(max_pos, pos)
            if first_pos is None:
                first_pos, first_wall = pos, now
                out['ttfp_ms'] = int((now - t0) * 1000)
            video_ready = (not need_video) or get_prop(lib, h, 'video-params/w') is not None
            if passed_pos is None and max_pos - first_pos >= need and video_ready:
                passed_pos, passed_wall = max_pos, now
                meta = collect_meta(lib, h)
                if sub_url:
                    meta.update(try_sub_add(lib, h, sub_url))
                if not live or expect == 'reject':
                    break
                live_deadline = now + live_gap
        if passed_pos is not None and live_deadline and now >= live_deadline:
            break
        if passed_pos is None:
            if first_wall is not None and now - first_wall > window:
                note = '（视频未解码，仅出声）' if need_video and max_pos - first_pos >= need else ''
                out['reason'] = '首个 time-pos 后 %.0fs 内仅推进 %.2fs%s' % (window, max_pos - first_pos, note)
                break
            if first_wall is None and now > deadline:
                out['reason'] = '%.0fs 内没有出现 time-pos（文件未加载完）' % budget
                break
            if expect == 'reject' and now > deadline:
                out['reason'] = '限时内无明确错误（疑似挂起）'
                break

    advance = (max_pos - first_pos) if first_pos is not None else 0.0
    out['advance_s'] = round(advance, 2)
    if not meta:
        meta = collect_meta(lib, h)
    out['meta'] = meta
    if end:
        out['end'] = end
    if live and passed_pos is not None:
        last = to_float(get_prop(lib, h, 'time-pos'))
        last = max_pos if last is None else max(last, max_pos)
        out['live_advance_s'] = round(last - passed_pos, 2)
    out['log'] = logs
    # ---- 判定 ----
    if expect == 'reject':
        ok = bool(end) and end['reason'] == 'error' and advance < need
        out['result'] = 'reject' if ok else 'fail'
        if not ok and 'reason' not in out:
            out['reason'] = '未被拒绝（end=%s, 推进 %.1fs）' % (end, advance)
    else:
        ok = passed_pos is not None
        if ok and live:
            ok = out.get('live_advance_s', 0) >= LIVE_NEED and not (end and end['reason'] in ('error', 'eof'))
            if not ok:
                out['reason'] = '直播 %.0fs 后仅再推进 %.1fs（end=%s）' % (live_gap, out.get('live_advance_s', 0), end)
        elif not ok and end and 'reason' not in out:
            out['reason'] = 'END_FILE %s %s' % (end['reason'], end.get('error') or '')
        if ok and entry_sub(sub_url) and 'sub_codec' not in meta:
            ok = False
            out['reason'] = meta.get('sub_error', '字幕未加载')
        # 短点播在窗口内播完但已推进足够：end 为 eof 也算通过
        out['result'] = 'play' if ok else 'fail'
    lib.mpv_terminate_destroy(h)
    return out


def run_proc(cmd, timeout):
    """带硬超时地运行子进程，超时后连同子孙进程一起杀掉（ffprobe 垫片会再拉子进程）。

    返回 (returncode, stdout, stderr)；超时抛 subprocess.TimeoutExpired。
    """
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = p.communicate(timeout=timeout)
        return p.returncode, out, err
    except subprocess.TimeoutExpired:
        if os.name == 'nt':
            subprocess.run(['taskkill', '/F', '/T', '/PID', str(p.pid)], capture_output=True)
        else:
            p.kill()
        try:
            p.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        raise


def run_ffprobe(url):
    """调用 ffprobe 取元数据，返回 {ok, format, streams, error}。"""
    cmd = ['ffprobe', '-v', 'error', '-rw_timeout', '15000000', '-show_format', '-show_streams', '-of', 'json', url]
    try:
        rc, pout, perr = run_proc(cmd, FFPROBE_TIMEOUT)
    except FileNotFoundError:
        return {'ok': False, 'error': '本机没有 ffprobe'}
    except subprocess.TimeoutExpired:
        return {'ok': False, 'error': 'ffprobe 超时'}
    if rc != 0:
        return {'ok': False, 'error': perr.decode('utf-8', 'replace').strip()[-300:]}
    try:
        j = json.loads(pout.decode('utf-8', 'replace'))
    except ValueError:
        return {'ok': False, 'error': 'ffprobe 输出无法解析'}
    fmt = j.get('format', {})
    streams = [{k: s.get(k) for k in ('codec_type', 'codec_name', 'profile', 'width', 'height',
                                      'avg_frame_rate', 'bit_rate', 'sample_rate', 'channels', 'disposition')
                if s.get(k) is not None} for s in j.get('streams', [])]
    return {'ok': True, 'format': {'format_name': fmt.get('format_name'), 'duration': fmt.get('duration'),
                                   'bit_rate': fmt.get('bit_rate')}, 'streams': streams}


def has_video(fp):
    """ffprobe 结果里是否有真正的视频流（不含封面图）。"""
    for st in fp.get('streams', []) if fp else []:
        if st.get('codec_type') == 'video' and not (st.get('disposition') or {}).get('attached_pic'):
            return True
    return False


def worker_cmd(args, url, whitelist, expect, live, need_video, sub_url=None):
    """拼出子进程命令行（子进程里才真正加载 dll，崩溃/挂起不会拖垮批处理）。"""
    payload = json.dumps({'dll': args.dll, 'url': url, 'whitelist': whitelist, 'expect': expect, 'live': live, 'need_video': need_video, 'sub_url': sub_url})
    return [sys.executable, '-I', os.path.abspath(__file__), '--worker', payload]


def run_mpv(args, url, whitelist, expect, live, need_video, sub_url=None):
    """在子进程里播放一次并回收结果，带硬超时。"""
    hard = (REJECT_TIMEOUT if expect == 'reject' else OPEN_TIMEOUT + WINDOW + LIVE_GAP) + 30
    try:
        rc, pout, perr = run_proc(worker_cmd(args, url, whitelist, expect, live, need_video, sub_url), hard)
    except subprocess.TimeoutExpired:
        return {'result': 'fail', 'reason': 'worker 超时被强杀（libmpv 疑似卡死）'}
    for line in pout.decode('utf-8', 'replace').splitlines():
        if line.startswith('RESULT:'):
            return json.loads(line[7:])
    tail = (perr or pout).decode('utf-8', 'replace').strip()[-200:]
    return {'result': 'fail', 'reason': 'worker 异常退出 code=%s %s' % (rc, tail)}


def probe_entry(args, entry):
    """测一个条目：ffprobe + libmpv；开启 --alternatives 时主地址失败依次试备选。"""
    expect = entry.get('expect', 'play')
    live = entry.get('kind') == 'live'
    wl = MOVA_WHITELIST + [x for x in entry.get('whitelist_add', []) if x not in MOVA_WHITELIST]
    urls = [entry['url']] + (entry.get('alternatives', []) if args.alternatives else [])
    res = {'id': entry['id'], 'kind': entry.get('kind'), 'expect': expect, 'label': args.label}
    for u in urls:
        res['url'] = u
        res['ffprobe'] = run_ffprobe(u) if not args.no_ffprobe else {'ok': None}
        if args.ffprobe_only or not os.path.isfile(args.dll):
            res['mpv'] = {'result': 'unverified'}
        else:
            res['mpv'] = run_mpv(args, u, wl, expect, live, has_video(res['ffprobe']), entry.get('sub_url'))
        good = res['mpv']['result'] in ('play', 'reject', 'unverified') and \
            (res['ffprobe']['ok'] in (True, None) or expect == 'reject')
        if good:
            break
    return res


def fmt_row(r):
    """把结果压成一行表格文本。"""
    m = r['mpv']
    meta = m.get('meta', {})
    verdict = {'play': 'PASS', 'reject': 'PASS(拒绝)', 'unverified': 'N/A'}.get(m['result'], 'FAIL')
    if r['expect'] == 'play' and r['ffprobe']['ok'] is False and verdict == 'PASS':
        verdict = 'PASS*'  # libmpv 能播但 ffprobe 失败，少见，标出来
    res = '%sx%s' % (meta.get('video-params/w', '-'), meta.get('video-params/h', '-'))
    note = m.get('reason') or ('sub=' + meta['sub_codec'] if 'sub_codec' in meta else '')
    return '%-26s %-5s %-10s ttfp=%-6s adv=%-6s live=%-6s %-12s %-18s %-8s %-10s %s' % (
        r['id'][:26], r['kind'], verdict, m.get('ttfp_ms', '-'), m.get('advance_s', '-'),
        m.get('live_advance_s', '-'), (meta.get('file-format') or '-')[:12],
        (meta.get('current-tracks/video/codec') or meta.get('video-format') or '-')[:18], (meta.get('audio-codec-name') or '-')[:8], res, note)


def dll_usable(path):
    """dll 是否存在且不是 Git LFS 指针（指针文件只有百余字节）。"""
    return os.path.isfile(path) and os.path.getsize(path) > 1024 * 1024


def main():
    """入口：解析参数，批量并发复测，输出 PASS/FAIL 表。"""
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--json', default=DEFAULT_JSON, help='源清单 JSON（默认 online_sources.json）')
    ap.add_argument('--dll', default=DEFAULT_DLL, help='裁剪版 libmpv-2.dll 路径')
    ap.add_argument('--only', action='append', default=[], help='只测这些 id（可重复，逗号分隔）')
    ap.add_argument('--kind', choices=['vod', 'live'], help='只测点播或直播')
    ap.add_argument('--jobs', type=int, default=3, help='并发数（4K 等高码率建议 1）')
    ap.add_argument('--alternatives', action='store_true', help='主地址失败时依次试 alternatives')
    ap.add_argument('--ffprobe-only', action='store_true', help='只跑 ffprobe（没有裁剪版 dll 时）')
    ap.add_argument('--no-ffprobe', action='store_true', help='跳过 ffprobe，只跑 libmpv')
    ap.add_argument('--out', help='把完整结果写入该 JSON 文件')
    ap.add_argument('--label', default='', help='结果标签（如 r1/r2，区分不同时刻的两轮）')
    ap.add_argument('--worker', help='内部用：子进程播放')
    args = ap.parse_args()
    if sys.stdout.encoding and sys.stdout.encoding.lower() != 'utf-8':
        sys.stdout.reconfigure(encoding='utf-8')

    if args.worker:
        w = json.loads(args.worker)
        try:
            r = play_once(w['dll'], w['url'], w['whitelist'], w['expect'], w['live'], w.get('need_video', False), w.get('sub_url'))
        except Exception as exc:  # 子进程里任何异常都转成失败结果
            r = {'result': 'fail', 'reason': 'worker 异常: %r' % exc}
        print('RESULT:' + json.dumps(r, ensure_ascii=False), flush=True)
        os._exit(0)  # 跳过解释器收尾，避免 dll 析构阶段卡住

    with open(args.json, encoding='utf-8') as f:
        entries = json.load(f)
    want = {x for s in args.only for x in s.split(',') if x}
    entries = [e for e in entries if (not want or e['id'] in want) and (not args.kind or e.get('kind') == args.kind)]
    if not args.ffprobe_only and not dll_usable(args.dll):
        print('警告：%s 不存在或只是 Git LFS 指针（先 git lfs fetch 并用 --dll 指向真实文件），'
              '退化为只用 ffprobe（结果标记为未经裁剪版验证）' % args.dll, file=sys.stderr)
        args.dll = ''
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        results = list(ex.map(lambda e: probe_entry(args, e), entries))
    for r in results:
        print(fmt_row(r))
    bad = [r for r in results if r['mpv']['result'] == 'fail' or r['ffprobe'].get('ok') is False and r['expect'] == 'play']
    print('\n共 %d 个，通过 %d，失败 %d，耗时 %.0fs' % (len(results), len(results) - len(bad), len(bad), time.time() - t0))
    if args.out:
        with open(args.out, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(results, f, ensure_ascii=False, indent=1)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
