// Windows libmpv-2.dll 冒烟程序：create/initialize/terminate_destroy 循环 + 可选播放一个 URL。
// 编译（MSYS2 mingw64，OUT 为 build-windows.sh 的 out 目录，MPV_INC 为 mpv 源码 include 目录的上一级）：
//   gcc smoke-windows.c -I<mpv>/include -L$OUT -lmpv-2 -o smoke.exe   （链接 gendef/dlltool 生成的 libmpv.dll.a，须与 libmpv-2.dll 同目录运行）
// 用法：
//   smoke.exe init                       连续 create/initialize/destroy 5 次
//   smoke.exe play <url> <秒数> [vo]     播放并每秒打印 time-pos 与已显示帧数；vo 缺省为 null；
//                                         日志级别 v，含 whep/rtcp/nack/pli/rtp 的行原样输出
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mpv/client.h>
#include <windows.h>

// 判断日志行是否值得打印（WHEP/RTCP 相关）
static int interesting(const char *t) {
    static const char *k[] = {"whep", "WHEP", "RTCP", "RTP", "NACK", "nack", "pli", "PLI", "DTLS", "ICE", "STUN", "SRTP", NULL};
    for (int i = 0; k[i]; i++) if (strstr(t, k[i])) return 1;
    return 0;
}

// 读 double 属性，失败返回 -1
static double getd(mpv_handle *h, const char *n) {
    double v = -1;
    if (mpv_get_property(h, n, MPV_FORMAT_DOUBLE, &v) < 0) return -1;
    return v;
}

// 读 int64 属性，失败返回 -1
static long long geti(mpv_handle *h, const char *n) {
    int64_t v = -1;
    if (mpv_get_property(h, n, MPV_FORMAT_INT64, &v) < 0) return -1;
    return v;
}

// create/initialize/terminate_destroy 循环，返回失败次数
static int init_loop(int n) {
    int fails = 0;
    for (int i = 0; i < n; i++) {
        mpv_handle *h = mpv_create();
        if (!h) { printf("[%d] mpv_create FAILED\n", i); fails++; continue; }
        mpv_set_option_string(h, "vo", "null");
        mpv_set_option_string(h, "ao", "null");
        int r = mpv_initialize(h);
        printf("[%d] mpv_create ok, initialize=%d (%s)\n", i, r, r < 0 ? mpv_error_string(r) : "ok");
        if (r < 0) fails++;
        mpv_terminate_destroy(h);
    }
    printf("init_loop done, fails=%d\n", fails);
    return fails;
}

// 播放 url 共 secs 秒，期间每秒打印进度；返回 0 表示 time-pos 有推进
static int play(const char *url, int secs, const char *vo) {
    mpv_handle *h = mpv_create();
    if (!h) return 2;
    mpv_set_option_string(h, "vo", vo);
    mpv_set_option_string(h, "ao", "null");
    const char *ml = getenv("SMOKE_MSG_LEVEL");   // 可用环境变量调日志级别，默认 all=v
    mpv_set_option_string(h, "msg-level", ml ? ml : "all=v");
    mpv_set_option_string(h, "idle", "yes");
    mpv_request_log_messages(h, getenv("SMOKE_MSG_LEVEL") ? "trace" : "v");
    int r = mpv_initialize(h);
    if (r < 0) { printf("initialize failed %d\n", r); return 2; }
    const char *cmd[] = {"loadfile", url, NULL};
    r = mpv_command(h, cmd);
    printf("loadfile -> %d\n", r);
    ULONGLONG t0 = GetTickCount64(), last = 0;
    double first_pos = -1, pos = -1;
    int ended = 0;
    while (GetTickCount64() - t0 < (ULONGLONG)secs * 1000 && !ended) {
        mpv_event *e = mpv_wait_event(h, 0.1);
        while (e->event_id != MPV_EVENT_NONE) {
            if (e->event_id == MPV_EVENT_LOG_MESSAGE) {
                mpv_event_log_message *m = e->data;
                if (interesting(m->text) || m->log_level <= MPV_LOG_LEVEL_ERROR)
                    printf("LOG[%s/%s] %s", m->prefix, m->level, m->text);
            } else if (e->event_id == MPV_EVENT_START_FILE) printf("EVENT start-file\n");
            else if (e->event_id == MPV_EVENT_FILE_LOADED) printf("EVENT file-loaded\n");
            else if (e->event_id == MPV_EVENT_VIDEO_RECONFIG) printf("EVENT video-reconfig\n");
            else if (e->event_id == MPV_EVENT_END_FILE) {
                mpv_event_end_file *ef = e->data;
                printf("EVENT end-file reason=%d error=%d (%s)\n", ef->reason, ef->error, ef->error < 0 ? mpv_error_string(ef->error) : "");
                ended = 1;
            }
            e = mpv_wait_event(h, 0);
        }
        ULONGLONG now = GetTickCount64() - t0;
        if (now - last >= 1000) {
            last = now;
            pos = getd(h, "time-pos");
            if (first_pos < 0 && pos >= 0) first_pos = pos;
            printf("t=%4llums time-pos=%.3f frames(estimated)=%lld drop(dec)=%lld drop(vo)=%lld vcodec=%s\n",
                   now, pos, geti(h, "estimated-frame-number"), geti(h, "decoder-frame-drop-count"),
                   geti(h, "frame-drop-count"), "-");
        }
    }
    // 先 stop 再排空事件，让 demuxer 关闭时的统计日志（RTP/RTCP/pli_sent 等）能打印出来
    { const char *stop[] = {"stop", NULL}; mpv_command(h, stop); }
    for (int i = 0; i < 30; i++) {
        mpv_event *e = mpv_wait_event(h, 0.1);
        while (e->event_id != MPV_EVENT_NONE) {
            if (e->event_id == MPV_EVENT_LOG_MESSAGE) {
                mpv_event_log_message *m = e->data;
                if (interesting(m->text)) printf("LOG[%s/%s] %s", m->prefix, m->level, m->text);
            }
            e = mpv_wait_event(h, 0);
        }
    }
    printf("RESULT first_pos=%.3f last_pos=%.3f advanced=%.3f\n", first_pos, pos, (first_pos >= 0 && pos >= 0) ? pos - first_pos : -1.0);
    mpv_terminate_destroy(h);
    return (first_pos >= 0 && pos - first_pos > 1.0) ? 0 : 1;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc >= 2 && !strcmp(argv[1], "init")) return init_loop(5) ? 1 : 0;
    if (argc >= 4 && !strcmp(argv[1], "play")) return play(argv[2], atoi(argv[3]), argc > 4 ? argv[4] : "null");
    fprintf(stderr, "usage: smoke init | smoke play <url> <secs> [vo]\n");
    return 64;
}
