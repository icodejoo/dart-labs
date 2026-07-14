// Myers bit-parallel edit distance — single-block path (qlen ≤ 64 codepoints).
//
// Myers 位并行编辑距离算法——单块（single-block）路径（查询长度 qlen ≤ 64 个码点）。
//
// References:
//   Gene Myers, "A Fast Bit-Vector Algorithm for Approximate String Matching
//   Based on Dynamic Programming", JACM 1999.
//   edlib (Martinsos/edlib, MIT) — calculateBlock inner loop formulation.
//   rapidfuzz-cpp (maxbachmann/rapidfuzz-cpp, MIT) — Unicode Peq strategy.
//
// 参考文献：
//   Gene Myers,《A Fast Bit-Vector Algorithm for Approximate String Matching
//   Based on Dynamic Programming》，JACM 1999。
//   edlib（Martinsos/edlib，MIT 协议）—— calculateBlock 内层循环的实现形式。
//   rapidfuzz-cpp（maxbachmann/rapidfuzz-cpp，MIT 协议）—— Unicode Peq（模式等价向量）策略。
//
// Both algorithms are always compiled together.
//
// 两种算法始终一起编译。
#include <stdint.h>
#include <stdlib.h>
#include "ffz_internal.h"
#include "ffz_alloc.h"

// ---------------------------------------------------------------------------
// Pattern-equivalence vector (Peq)
//
// 模式等价向量（Peq）
// ---------------------------------------------------------------------------
// One 64-bit word per distinct (normalised) codepoint in the query.
// ASCII codepoints [0,127] get a dense array; non-ASCII (≤ 64 distinct values,
// bounded by qlen ≤ 64) use parallel arrays searched linearly.
//
// 查询串中每个不同的（已归一化）码点对应一个 64 位字。
// ASCII 码点 [0,127] 使用稠密数组；非 ASCII 码点（至多 64 个不同取值，
// 受 qlen ≤ 64 限制）使用并行数组做线性查找。

typedef uint64_t Word;

typedef struct {
    Word ascii[128];               // ASCII fast path
    //
    // ASCII 快速路径。
    uint32_t nc_cp[64];            // non-ASCII codepoints
    //
    // 非 ASCII 码点。
    Word     nc_bits[64];          // corresponding Peq words
    //
    // 对应的 Peq 字（位向量）。
    int      nc_len;               // number of distinct non-ASCII entries
    //
    // 不同非 ASCII 条目的数量。
} ffz_peq;

static void peq_build(ffz_peq *peq, ffz_str q, const ffz_config *cfg) {
    memset(peq->ascii, 0, sizeof(peq->ascii));
    peq->nc_len = 0;

    for (size_t i = 0; i < q.len; i++) {
        uint32_t raw = ffz_at(q, i);
        uint32_t cp  = ffz_normalize_cp(raw, cfg);
        Word bit = (Word)1 << i;

        if (cp < 128) {
            peq->ascii[cp] |= bit;
        } else {
            // Linear scan: at most 64 entries (qlen ≤ 64).
            //
            // 线性扫描：最多 64 个条目（qlen ≤ 64）。
            int found = -1;
            for (int j = 0; j < peq->nc_len; j++) {
                if (peq->nc_cp[j] == cp) { found = j; break; }
            }
            if (found >= 0) {
                peq->nc_bits[found] |= bit;
            } else if (peq->nc_len < 64) {
                int j = peq->nc_len++;
                peq->nc_cp[j]   = cp;
                peq->nc_bits[j] = bit;
            }
        }
    }
}

static inline Word peq_get(const ffz_peq *peq, uint32_t cp) {
    if (cp < 128) return peq->ascii[cp];
    for (int j = 0; j < peq->nc_len; j++)
        if (peq->nc_cp[j] == cp) return peq->nc_bits[j];
    return (Word)0;
}

// ---------------------------------------------------------------------------
// Free-start scan — shared by the forward and backward passes of
// ffz_edit_window() below.
//
// 自由起点扫描（free-start scan）—— 由下方 ffz_edit_window() 的
// 正向与反向两趟扫描共用。
// ---------------------------------------------------------------------------
// Whole-string alignment (the old ffz_edit_distance) fixes D[0][j] = j: hay's
// prefix before the match must be paid for, one insertion per skipped
// character. Approximate SUBSTRING search instead needs D[0][j] = 0 for every
// j — the match may start anywhere in hay for free. The only recurrence
// change this takes is dropping the forced low bit on HP before it shifts
// into the next column (that forced bit is exactly what encodes "row 0 costs
// +1 per column"); everything else about Myers' bit-vector update is
// unchanged. Verified against a brute-force O(n*m) DP reference across tens
// of thousands of randomized cases before landing.
//
// 全串对齐（旧版 ffz_edit_distance）将 D[0][j] 固定为 j：匹配之前 hay 中的
// 前缀必须付出代价，每跳过一个字符就要计一次插入。近似子串搜索则需要
// 每个 j 都满足 D[0][j] = 0——匹配可以从 hay 中任意位置免费开始。这一
// 改动在递推公式上唯一的变化，就是在 HP 移入下一列之前去掉强制置低位
// （那个被强制置的位正是编码"第 0 行每列多付 +1 代价"的地方）；Myers
// 位向量更新的其余部分都不变。落地前已针对暴力 O(n*m) DP 参考实现，在
// 数万个随机用例上验证过正确性。
//
// Scans the whole of `hay` (no early Ukkonen cutoff — the running minimum can
// go back down after rising, unlike the monotone whole-string case, so a
// naive "can't possibly recover" bound doesn't apply) and returns the lowest
// D[qlen][j] seen, writing the column (1-based count of hay codepoints
// consumed) at which that minimum first occurred.
//
// 扫描整个 `hay`（不做 Ukkonen 提前截断——与单调的全串场景不同，这里的
// 运行时最小值在上升之后还可能再次下降，因此"不可能挽回"这种朴素的
// 下界判断并不适用），返回观察到的最小 D[qlen][j]，并写出该最小值
// 首次出现时所在的列号（从 1 开始计数的已消耗 hay 码点数）。
static int scan_free_start(const ffz_peq *peq, int qlen, ffz_str hay,
                            const ffz_config *cfg, size_t *out_pos) {
    Word VP = ~(Word)0;
    Word VN = (Word)0;
    int score = qlen;
    int best = score;
    size_t bestj = 0;
    Word mask = (Word)1 << (qlen - 1);

    for (size_t col = 0; col < hay.len; col++) {
        uint32_t cp = ffz_normalize_cp(ffz_at(hay, col), cfg);

        Word Eq = peq_get(peq, cp);
        Word X  = Eq | VN;
        Word D0 = (((X & VP) + VP) ^ VP) | X | VN;
        Word HP = VN | ~(D0 | VP);
        Word HN = D0 & VP;

        if (HP & mask) score++;
        if (HN & mask) score--;

        if (score < best) { best = score; bestj = col + 1; }
        if (best == 0) break;  // can't improve on an exact match
        //
        // 已无法优于精确匹配。

        HP = HP << 1;   // no `| 1`: row 0 stays free at every column
        //
        // 不做 `| 1`：第 0 行在每一列都保持免费。
        HN <<= 1;
        VP = HN | ~(D0 | HP);
        VN = HP & D0;
    }

    *out_pos = bestj;
    return best;
}

// ---------------------------------------------------------------------------
// Public functions
//
// 公共函数
// ---------------------------------------------------------------------------

// Whole-string Levenshtein distance between `query` and the FULL `hay` (both
// ends anchored). Kept for callers that genuinely want "how close is this
// entire string" rather than substring search — currently unused internally
// (ffz_corpus.c's approx family calls ffz_edit_window instead) but still part
// of the internal surface.
//
// 计算 `query` 与完整 `hay` 之间的全串 Levenshtein 距离（两端都锚定）。
// 保留给那些确实想知道"整个字符串有多接近"而非做子串搜索的调用方——
// 目前内部并未使用（ffz_corpus.c 的近似匹配一族改为调用 ffz_edit_window），
// 但仍属于内部接口的一部分。
int ffz_edit_distance(ffz_str query, ffz_str hay,
                      int max_dist, const ffz_config *cfg) {
    // Single-block path only. Compared as size_t, before any narrowing to
    // int, so an oversized query.len can't wrap into a small value and slip
    // past this guard (see ffz_edit_distance_substring/ffz_edit_window,
    // which already compare query.len this way).
    //
    // 仅支持单块（single-block）路径。以 size_t 比较，且在任何向 int 收窄
    // 之前完成，这样过大的 query.len 就不会因回绕成小值而绕过此检查
    // （参见 ffz_edit_distance_substring / ffz_edit_window，它们已经是
    // 按这种方式比较 query.len 的）。
    if (query.len > 64) return max_dist + 1;

    int qlen = (int)query.len;
    int hlen = (int)hay.len;

    // Trivial cases. Both are whole-string (anchored) distances: an empty
    // query costs one deletion per remaining hay codepoint, and vice versa.
    //
    // 平凡情形。两者都是全串（锚定）距离：空查询串对每个剩余的 hay 码点都要
    // 付出一次删除代价，反之亦然。
    if (qlen == 0) return hlen <= max_dist ? hlen : -1;
    if (hlen == 0) return qlen <= max_dist ? qlen : -1;

    // --- Common prefix strip ---
    //
    // --- 去除公共前缀 ---
    size_t pre = 0;
    while (pre < (size_t)qlen && pre < (size_t)hlen) {
        uint32_t qcp = ffz_normalize_cp(ffz_at(query, pre), cfg);
        uint32_t hcp = ffz_normalize_cp(ffz_at(hay,   pre), cfg);
        if (qcp != hcp) break;
        pre++;
    }
    // --- Common suffix strip ---
    //
    // --- 去除公共后缀 ---
    size_t suf = 0;
    while ((size_t)qlen - pre - suf > 0 &&
           (size_t)hlen - pre - suf > 0) {
        size_t qi = (size_t)qlen - 1 - suf;
        size_t hi = (size_t)hlen - 1 - suf;
        uint32_t qcp = ffz_normalize_cp(ffz_at(query, qi), cfg);
        uint32_t hcp = ffz_normalize_cp(ffz_at(hay,   hi), cfg);
        if (qcp != hcp) break;
        suf++;
    }

    // Reduced problem bounds.
    //
    // 缩减后问题的边界。
    int q0 = (int)pre;
    int q1 = qlen  - (int)suf;   // exclusive
    //
    // 不包含（exclusive，开区间右端点）。
    int h0 = (int)pre;
    int h1 = hlen  - (int)suf;   // exclusive
    //
    // 不包含（exclusive，开区间右端点）。

    int new_qlen = q1 - q0;
    int new_hlen = h1 - h0;

    // Free distance from the stripped characters (pure insertions/deletions
    // after the common prefix/suffix are removed).
    //
    // 剥离字符所贡献的自由距离（去除公共前缀/后缀之后，剩下的纯插入/删除）。
    int free_dist = abs(new_qlen - new_hlen);
    if (new_qlen == 0) {
        // All query chars matched in suffix/prefix; remaining hay chars = deletions.
        //
        // 查询串所有字符都已在前缀/后缀中匹配；剩余的 hay 字符即为删除操作。
        return new_hlen <= max_dist ? new_hlen : -1;
    }
    if (new_hlen == 0) {
        return new_qlen <= max_dist ? new_qlen : -1;
    }

    // Build a new query view for the reduced range.
    // Re-use a local codepoint buffer so we don't need heap allocation.
    //
    // 为缩减后的范围构建一个新的查询视图。
    // 复用一个局部码点缓冲区，从而无需堆分配。
    uint32_t qbuf[64];
    for (int i = 0; i < new_qlen; i++)
        qbuf[i] = ffz_at(query, (size_t)(q0 + i));

    // Build Peq over the reduced query.
    //
    // 在缩减后的查询上构建 Peq。
    ffz_peq peq;
    // We need a ffz_str over the reduced slice.
    //
    // 需要在缩减后的切片上构造一个 ffz_str。
    ffz_str qslice;
    qslice.b = NULL;
    qslice.u = qbuf;
    qslice.len = (size_t)new_qlen;

    peq_build(&peq, qslice, cfg);

    // Myers single-block DP.
    //
    // Myers 单块动态规划。
    Word VP = ~(Word)0;
    Word VN = (Word)0;
    int score = new_qlen;
    Word mask = (Word)1 << (new_qlen - 1);

    for (int col = h0; col < h1; col++) {
        int remaining = (h1 - 1) - col;  // columns still to process after this one
        //
        // 本列之后仍待处理的列数。

        uint32_t raw = ffz_at(hay, (size_t)col);
        uint32_t cp  = ffz_normalize_cp(raw, cfg);

        Word Eq = peq_get(&peq, cp);
        Word X  = Eq | VN;
        Word D0 = (((X & VP) + VP) ^ VP) | X | VN;
        Word HP = VN | ~(D0 | VP);
        Word HN = D0 & VP;

        if (HP & mask) score++;
        if (HN & mask) score--;

        // Ukkonen early termination: if even all remaining columns improve the
        // score by 1 each, we still can't reach max_dist.
        //
        // Ukkonen 提前终止：即使剩余的每一列都能把得分改善 1，也依然无法
        // 达到 max_dist。
        if (score - remaining > max_dist) return -1;

        HP = (HP << 1) | (Word)1;
        HN <<= 1;
        VP = HN | ~(D0 | HP);
        VN = HP & D0;
    }

    return score <= max_dist ? score : -1;
}

// Approximate SUBSTRING distance only (forward pass, no window recovery) —
// cheap, used for Pass 1 scoring of every corpus item. Callers that also need
// the matched window (for highlight indices) should use ffz_edit_window
// below instead, but only for the small surviving top-K set (Pass 2),
// mirroring how the fuzzy path defers ffz_pattern_match's index computation
// past the initial score-only scan.
//
// 仅计算近似子串（SUBSTRING）距离（正向扫描，不做窗口回溯）——开销小，
// 用于对语料库中每一项做第一轮（Pass 1）打分。如果调用方还需要匹配窗口
// （用于高亮下标），应改用下方的 ffz_edit_window，但仅对少量存活下来的
// top-K 结果（Pass 2）调用，这与模糊匹配路径把 ffz_pattern_match 的下标
// 计算推迟到初始纯打分扫描之后的做法是一致的。
int ffz_edit_distance_substring(ffz_str query, ffz_str hay, int max_dist,
                                const ffz_config *cfg) {
    // An empty query trivially matches (distance 0) anywhere, but that must
    // still respect the documented [0..max_dist]/-1 contract: a negative
    // max_dist means "no window qualifies", full stop.
    //
    // 空查询串在任意位置都能"免费"匹配（距离 0），但仍须遵守文档规定的
    // [0..max_dist] / -1 契约：max_dist 为负数就意味着"没有窗口满足条件"。
    if (query.len == 0) return max_dist >= 0 ? 0 : -1;
    if (query.len > 64) return -1;
    int qlen = (int)query.len;
    if (hay.len == 0) return qlen <= max_dist ? qlen : -1;

    ffz_peq peq;
    peq_build(&peq, query, cfg);
    size_t end;
    int dist = scan_free_start(&peq, qlen, hay, cfg, &end);
    return dist <= max_dist ? dist : -1;
}

// Approximate SUBSTRING search: finds the minimum-edit-distance window of
// `hay` that matches `query` (the window may start and end anywhere in hay),
// and writes that window's codepoint range [*out_start, *out_end). Returns
// the window's distance, or -1 if no window is within max_dist.
//
// Two-pass: a forward free-start scan over all of `hay` finds the distance
// and the window's end; a second free-start scan, on the reversed query
// against the reversed hay[0..end), finds the window's start. Both passes
// share scan_free_start() above — verified to recover a genuine witness
// window (re-checked against a whole-string distance computed on just that
// slice) across tens of thousands of randomized cases.
//
// 近似子串搜索：在 `hay` 中找出与 `query` 匹配、编辑距离最小的窗口
// （该窗口可以从 hay 中任意位置开始和结束），并写出该窗口的码点范围
// [*out_start, *out_end)。返回该窗口的距离；若没有窗口落在 max_dist 之内
// 则返回 -1。
//
// 分两趟：先对整个 `hay` 做一次正向自由起点扫描，得到距离和窗口终点；
// 再对反转后的 query 与反转后的 hay[0..end) 做第二次自由起点扫描，得到
// 窗口起点。两趟扫描都复用上面的 scan_free_start()——已在数万个随机
// 用例上验证过能恢复出真实的见证窗口（即在该切片上单独计算全串距离
// 进行复核）。
int ffz_edit_window(ffz_str query, ffz_str hay, int max_dist,
                     const ffz_config *cfg, size_t *out_start, size_t *out_end) {
    // Set on every path (including the early-return "no match" ones below) so
    // a caller that reads *out_start/*out_end without checking the return
    // value first never sees indeterminate values.
    //
    // 在每条路径上都会设置（包括下面提前返回"无匹配"的路径），这样调用方
    // 即使不先检查返回值就读取 *out_start/*out_end，也不会看到不确定的值。
    *out_start = 0;
    *out_end = 0;
    // Same empty-query contract as ffz_edit_distance_substring above: 0 is
    // only correct when max_dist can actually accommodate it.
    //
    // 与上面 ffz_edit_distance_substring 相同的空查询串契约：只有当
    // max_dist 确实能容纳它时，返回 0 才是正确的。
    if (query.len == 0) return max_dist >= 0 ? 0 : -1;
    if (query.len > 64) return -1;
    int qlen = (int)query.len;

    if (hay.len == 0) return qlen <= max_dist ? qlen : -1;

    ffz_peq peq;
    peq_build(&peq, query, cfg);

    size_t end;
    int dist = scan_free_start(&peq, qlen, hay, cfg, &end);
    if (dist > max_dist) return -1;

    // Backward pass: reverse both query and hay[0..end), then find how far
    // back from `end` the match extends the same way.
    //
    // 反向扫描：将 query 和 hay[0..end) 都反转，然后用同样的方法找出匹配
    // 从 `end` 向前能延伸多远。
    uint32_t qrev[64];
    for (int i = 0; i < qlen; i++) qrev[i] = ffz_at(query, (size_t)(qlen - 1 - i));
    ffz_str qrev_str;
    qrev_str.b = NULL;
    qrev_str.u = qrev;
    qrev_str.len = (size_t)qlen;

    if (end > SIZE_MAX / sizeof(uint32_t)) return -1;  // would overflow the byte-size multiply
    //
    // 否则字节大小乘法会溢出。
    uint32_t *hrev = (uint32_t *)malloc((end ? end : 1) * sizeof(uint32_t));
    if (!hrev) return -1;  // real OOM — report "no match" rather than crash
    //
    // 真正的内存不足（OOM）——报告"无匹配"而不是崩溃。
    for (size_t i = 0; i < end; i++) hrev[i] = ffz_at(hay, end - 1 - i);
    ffz_str hrev_str;
    hrev_str.b = NULL;
    hrev_str.u = hrev;
    hrev_str.len = end;

    ffz_peq peq_rev;
    peq_build(&peq_rev, qrev_str, cfg);
    size_t back_len;
    scan_free_start(&peq_rev, qlen, hrev_str, cfg, &back_len);
    free(hrev);

    *out_start = end - back_len;
    *out_end = end;
    return dist;
}
