// Apple 版 libmpv 冒烟程序（macOS 本机 / iOS 模拟器共用）。
// 用法：
//   apple-smoke init                      连续 create/initialize/destroy 5 次
//   apple-smoke play <url> <秒数>          vo=null、ao=null 播放，每秒打印 time-pos，结束打印 RESULT
// 退出码：0 起播成功（time-pos 推进 > 1 秒）；1 没推进；2 初始化失败；64 参数错误。
// 版本取证：启动后打印 mpv-version / ffmpeg-version 属性，供 CI 核对是 v0.41.0 / n9.0.2。
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <mpv/client.h>

// 单调时钟毫秒
static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
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

// 读字符串属性并打印，失败打印 (n/a)
static void show_prop(mpv_handle *h, const char *n) {
    char *v = mpv_get_property_string(h, n);
    printf("PROP %s = %s\n", n, v ? v : "(n/a)");
    if (v) mpv_free(v);
}

// 把环境变量 SMOKE_OPTS（形如 "tls-verify=no;tls-ca-file=/x.pem"）逐项设为 mpv 选项，须在 initialize 之前调用
static void apply_env_opts(mpv_handle *h) {
    const char *e = getenv("SMOKE_OPTS");
    if (!e || !*e) return;
    char *dup = strdup(e), *save = NULL;
    for (char *tok = strtok_r(dup, ";", &save); tok; tok = strtok_r(NULL, ";", &save)) {
        char *eq = strchr(tok, '=');
        if (!eq) continue;
        *eq = 0;
        int r = mpv_set_option_string(h, tok, eq + 1);
        printf("OPT %s=%s -> %d\n", tok, eq + 1, r);
    }
    free(dup);
}

// 日志行是否值得打印（WHEP/RTCP/DTLS 相关）
static int interesting(const char *t) {
    static const char *k[] = {"whep", "WHEP", "RTCP", "RTP", "NACK", "PLI", "DTLS", "ICE", "STUN", "SRTP", "TLS", "hwdec", NULL};
    for (int i = 0; k[i]; i++) if (strstr(t, k[i])) return 1;
    return 0;
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
        printf("[%d] initialize=%d (%s)\n", i, r, r < 0 ? mpv_error_string(r) : "ok");
        if (r < 0) fails++;
        else if (i == 0) { show_prop(h, "mpv-version"); show_prop(h, "ffmpeg-version"); }
        mpv_terminate_destroy(h);
    }
    printf("init_loop done, fails=%d\n", fails);
    return fails;
}

// 播放 url 共 secs 秒；返回 0 表示 time-pos 推进超过 1 秒
static int play(const char *url, int secs) {
    mpv_handle *h = mpv_create();
    if (!h) return 2;
    mpv_set_option_string(h, "vo", "null");
    mpv_set_option_string(h, "ao", "null");
    mpv_set_option_string(h, "msg-level", "all=v");
    mpv_set_option_string(h, "idle", "yes");
    apply_env_opts(h);
    mpv_request_log_messages(h, "v");
    int r = mpv_initialize(h);
    if (r < 0) { printf("initialize failed %d\n", r); return 2; }
    show_prop(h, "mpv-version");
    show_prop(h, "ffmpeg-version");
    const char *cmd[] = {"loadfile", url, NULL};
    r = mpv_command(h, cmd);
    printf("loadfile -> %d\n", r);
    int log_all = getenv("SMOKE_LOG_ALL") != NULL;   // 失败场景排查用：打印全部 v 级日志
    long long t0 = now_ms(), last = 0;
    double first_pos = -1, pos = -1;
    int ended = 0, end_err = 0, dumped = 0;
    while (now_ms() - t0 < (long long)secs * 1000 && !ended) {
        mpv_event *e = mpv_wait_event(h, 0.1);
        while (e->event_id != MPV_EVENT_NONE) {
            if (e->event_id == MPV_EVENT_LOG_MESSAGE) {
                mpv_event_log_message *m = e->data;
                if (log_all || interesting(m->text) || m->log_level <= MPV_LOG_LEVEL_ERROR)
                    printf("LOG[%s/%s] %s", m->prefix, m->level, m->text);
            } else if (e->event_id == MPV_EVENT_START_FILE) printf("EVENT start-file\n");
            else if (e->event_id == MPV_EVENT_FILE_LOADED) printf("EVENT file-loaded\n");
            else if (e->event_id == MPV_EVENT_END_FILE) {
                mpv_event_end_file *ef = e->data;
                printf("EVENT end-file reason=%d error=%d (%s)\n", ef->reason, ef->error, ef->error < 0 ? mpv_error_string(ef->error) : "");
                end_err = ef->error;
                ended = 1;
            }
            e = mpv_wait_event(h, 0);
        }
        long long now = now_ms() - t0;
        if (now - last >= 1000) {
            last = now;
            pos = getd(h, "time-pos");
            if (first_pos < 0 && pos >= 0) first_pos = pos;
            printf("t=%4lldms time-pos=%.3f frames=%lld drop(dec)=%lld\n", now, pos, geti(h, "estimated-frame-number"), geti(h, "decoder-frame-drop-count"));
            if (!dumped && pos > 3) {   // 起播稳定后一次性取证
                dumped = 1;
                const char *props[] = {"video-format", "audio-codec-name", "width", "height", "audio-params/samplerate", "hwdec-current", NULL};
                for (int i = 0; props[i]; i++) show_prop(h, props[i]);
            }
        }
    }
    // stop 后排空事件，让 demuxer 关闭时的统计日志（RTP/RTCP）能打印出来
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
    printf("RESULT first_pos=%.3f last_pos=%.3f advanced=%.3f end_error=%d\n", first_pos, pos,
           (first_pos >= 0 && pos >= 0) ? pos - first_pos : -1.0, end_err);
    mpv_terminate_destroy(h);
    return (first_pos >= 0 && pos - first_pos > 1.0) ? 0 : 1;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc >= 2 && !strcmp(argv[1], "init")) return init_loop(5) ? 2 : 0;
    if (argc >= 4 && !strcmp(argv[1], "play")) return play(argv[2], atoi(argv[3]));
    fprintf(stderr, "usage: apple-smoke init | apple-smoke play <url> <secs>\n");
    return 64;
}
