/* Offline RFC 7741 regression / 直接包含已打补丁的 whep.c，验证真实组帧路径。
 * See whep_vp8_regress.sh for build/run instructions. */
#include <assert.h>
#define av_random_bytes whep_test_random_bytes
#include "libavformat/whep.c"
#undef av_random_bytes
#include "libavutil/avassert.h"
/* FFmpeg may define NDEBUG / 测试断言必须在 release 配置下仍执行。 */
#undef assert
#define assert av_assert0

/* Reproducible SDP / 固定随机数，便于逐字节对照未编 VP8 的 offer。 */
int whep_test_random_bytes(uint8_t *buf, size_t len)
{
    memset(buf, 0x42, len);
    return 0;
}

#if WHEP_HAVE_VP8
static void expect_packet(AVFormatContext *s, const uint8_t *data, int size, int key)
{
    WHEPContext *w = s->priv_data;
    AVPacket pkt = { 0 };
    assert(ff_packet_list_get(&w->out, &pkt) == 0);
    assert(pkt.size == size && !memcmp(pkt.data, data, size));
    assert(!!(pkt.flags & AV_PKT_FLAG_KEY) == key);
    av_packet_unref(&pkt);
    assert(!w->out.head);
}
#endif

int main(int argc, char **argv)
{
    AVFormatContext *s = avformat_alloc_context();
    WHEPContext *w = av_mallocz(sizeof(*w));
    WhepMedia m = { .type = AVMEDIA_TYPE_VIDEO, .nb_pts = 2, .pts = {105, 102},
                    .nb_codec = 2, .codec = {{.pt=105, .name="VP8"}, {.pt=102, .name="H264"}} };
    assert(s && w);
    s->priv_data = w;
    assert(whep_generate_offer(s) == 0);
    if (argc > 1) {
        FILE *f = fopen(argv[1], "wb");
        assert(f);
        assert(fwrite(w->sdp_offer, 1, strlen(w->sdp_offer), f) == strlen(w->sdp_offer));
        fclose(f);
    }
    whep_select_codec(&m);
    assert(m.sel == 1);                           /* H264 wins despite answer order */
    m.nb_pts = 1;
    whep_select_codec(&m);
#if WHEP_HAVE_VP8
    assert(m.sel == 0);
    w->answer.nb_media = 1;
    w->answer.media[0] = m;
    assert(whep_create_streams(s) == 0);
    assert(s->streams[0]->codecpar->codec_id == AV_CODEC_ID_VP8);
    assert(strstr(w->sdp_offer, "102 103 104 105 112 113 114 115\r\n"));
    {
        /* VP8 frame tag + sync + 640x360 / 构造关键帧头与跨包载荷。 */
        const uint8_t key[] = {0x10,0,0,0x9d,1,0x2a,0x80,2,0x68,1,0xaa,0xbb};
        const uint8_t delta[] = {1,0,0,0x55};
        uint8_t rtp[128] = {0x80, 0x80 | 105};
        WhepRx *rx = &w->rx[0];
        uint16_t seq = 1;
        uint32_t ts = 0;
        int start;
        rx->is_video = rx->vp8 = 1;
        rx->pt = 105;
        rx->clock = 90000;
        /* Full RTP headers -> actual reorder/deliver/descriptor/emit path. */
#define SEND(desc, dn, data, n, mark, advance) do { \
    AV_WB16(rtp + 2, seq++); AV_WB32(rtp + 4, ts); \
    rtp[1] = ((mark) ? 0x80 : 0) | 105; \
    memcpy(rtp + 12, desc, dn); memcpy(rtp + 12 + (dn), data, n); \
    whep_rx_push(s, rx, rtp, 12 + (dn) + (n), av_gettime_relative()); \
    ts += (advance); \
} while (0)
        const uint8_t simple[] = {0x10}, cont[] = {0}, part[] = {0x11};
        const uint8_t ext[] = {0x90,0xf0,0x80,0x42,0x23,0x61};
        const uint8_t shortid[] = {0x90,0x80,0x42};
        const uint8_t tk[] = {0x90,0x30,0x61};
        const uint8_t truncated[] = {0x90,0xf0,0x80};
        const uint8_t part8[] = {0x18}, badpart[] = {0x19};
        assert(whep_vp8_desc(part8,1,&start) == 1 && !start);
        assert(whep_vp8_desc(badpart,1,&start) < 0);
        SEND(simple,1,delta,4,1,3600);              /* Pre-key delta rejected */
        assert(rx->n_nokey == 1 && !w->out.head);
        SEND(simple,1,key,5,0,0);
        SEND(cont,1,key+5,7,1,3600);
        expect_packet(s,key,12,1);
        assert(s->streams[0]->codecpar->width == 640);
        assert(s->streams[0]->codecpar->height == 360);
        SEND(ext,6,delta,2,0,0);
        SEND(part,1,delta+2,2,1,3600);              /* Later partition start != frame start */
        expect_packet(s,delta,4,0);
        SEND(shortid,3,key,12,1,3600);
        expect_packet(s,key,12,1);
        SEND(tk,3,delta,4,1,3600);
        expect_packet(s,delta,4,0);
        assert(whep_vp8_desc(truncated,3,&start) < 0);
        for (int n = 0; n < 6; n++)
            assert(whep_vp8_desc(ext,n,&start) < 0);
        SEND(truncated,3,key,0,1,3600);            /* Truncated descriptor resets gate */
        assert(!rx->seen_key && !w->out.head);
        SEND(simple,1,delta,4,1,3600);
        assert(!w->out.head);
        SEND(cont,1,key,12,1,3600);                /* Missing frame start */
        assert(!w->out.head);
        SEND(simple,1,key,5,0,3600);               /* Missing marker/tail */
        SEND(simple,1,delta,4,1,3600);
        assert(!rx->seen_key && !w->out.head);
        SEND(simple,1,key,12,1,3600);
        expect_packet(s,key,12,1);
        seq += WHEP_REORDER_MAX;                  /* Entire frame lost between markers */
        SEND(simple,1,delta,4,1,3600);
        assert(!rx->seen_key && !w->out.head);
        SEND(simple,1,key,12,1,3600);
        expect_packet(s,key,12,1);
        SEND(simple,1,key,5,0,0);
        seq += WHEP_REORDER_MAX;                  /* Real unrecoverable sequence gap */
        SEND(cont,1,key+5,7,1,3600);
        assert(rx->n_lost && !rx->seen_key && !w->out.head);
        SEND(simple,1,delta,4,1,3600);
        assert(!w->out.head);
        SEND(simple,1,key,12,1,3600);
        expect_packet(s,key,12,1);
        SEND(simple,1,key,5,0,0);
        SEND(simple,1,key,12,1,3600);              /* Duplicate start */
        assert(!w->out.head);
        uint8_t badkey[12];
        memcpy(badkey,key,12); badkey[3] = 0;
        SEND(simple,1,badkey,12,1,3600);
        assert(!w->out.head);
        memcpy(badkey,key,12); badkey[6] = badkey[7] = 0;
        SEND(simple,1,badkey,12,1,3600);
        assert(!w->out.head);
        SEND(simple,1,key,12,1,3600);
        expect_packet(s,key,12,1);
        av_freep(&rx->au);
        printf("PASS VP8: RTP fragments, I/L/T/K, partitions, key gate, malformed headers, loss/recovery; lost=%"PRIu64" dropped=%"PRIu64"\n", rx->n_lost,rx->n_drop_au);
    }
#else
    assert(m.sel == -1);
    assert(!strstr(w->sdp_offer, "VP8/90000"));
    puts("PASS no-VP8: H264 preference, VP8 rejected, original offer");
#endif
    av_freep(&w->sdp_offer);
    s->priv_data = NULL;
    av_free(w);
    avformat_free_context(s);
    return 0;
}
