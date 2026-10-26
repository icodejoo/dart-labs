// ffz_corpus — resident multi-key index with a transliteration hook.
//
// This is the "index layer" that sits above the matcher. Each item can carry
// several *search keys* in addition to its display text — e.g. a Chinese name
// "张三" indexed alongside its pinyin "zhangsan" and initials "zs", so the user
// can find it by typing latin. The matcher itself stays tiny and Unicode-only;
// the transliteration dictionary lives entirely in the HOST via a callback.
//
//   item 0: display "张三"
//           keys: [ {ORIGINAL,"张三"}, {PINYIN,"zhangsan"}, {INITIALS,"zs"} ]
//
// On query, every key of every item is matched; the item takes its best key's
// score, and the hit reports WHICH key matched (kind + index) plus the matched
// codepoint indices *within that key* — so the UI knows whether/how to
// highlight (you usually only highlight when the matched key is ORIGINAL).
#ifndef FFZ_CORPUS_H
#define FFZ_CORPUS_H

#include "ffz.h"

#ifdef __cplusplus
extern "C" {
#endif

// Semantic tag for a generated key (extend freely; values are opaque to ffz).
typedef enum {
    FFZ_KEY_ORIGINAL = 0,  // the display text itself (always key 0)
    FFZ_KEY_PINYIN = 1,    // full pinyin, e.g. "zhongwen"
    FFZ_KEY_INITIALS = 2,  // initial letters, e.g. "zw"
    FFZ_KEY_ROMAJI = 3,    // japanese romaji
    FFZ_KEY_CUSTOM = 100   // host-defined kinds start here
} ffz_key_kind;

// One alternate search key emitted by the transliteration hook.
typedef struct {
    const char *text;  // UTF-8; ffz copies it, so host-owned/temporary is fine
    size_t len;        // byte length
    int kind;          // ffz_key_kind or a host-defined value
} ffz_key;

// Transliteration hook: called once per item at insert time. The host fills
// `out` (capacity `max_out`) with alternate keys for `item` and returns how
// many it wrote (clamped to `max_out`). Return 0 for "no extra keys". The
// ORIGINAL key is added by ffz automatically — do NOT emit it here.
//
// `ctx` is the user pointer registered with ffz_corpus_set_transliterator.
typedef size_t (*ffz_transliterator)(const char *item, size_t item_len,
                                     void *ctx, ffz_key *out, size_t max_out);

typedef struct ffz_corpus ffz_corpus;

// Create an empty corpus that matches with `cfg`.
ffz_corpus *ffz_corpus_new(ffz_config cfg);
void ffz_corpus_free(ffz_corpus *c);

// Register the transliteration hook BEFORE adding items (applies to subsequent
// adds). `max_keys_per_item` caps how many alternate keys are requested.
void ffz_corpus_set_transliterator(ffz_corpus *c, ffz_transliterator fn,
                                    void *ctx, size_t max_keys_per_item);

/**
 * 新增条目，并使用已注册的转写回调生成附加键。
 * @param c 有效语料库。
 * @param item 条目 UTF-8 字节；len 非零时必须可读。
 * @param len 条目字节数。
 * @return 成功返回真；分配或容量检查失败返回假，条目数及已有键不变。
 * @example bool ok = ffz_corpus_add(c, "abc", 3);
 */
bool ffz_corpus_add(ffz_corpus *c, const char *item, size_t len);

/**
 * 新增原始键和显式附加键，绕过转写回调。
 * @param c 有效语料库。
 * @param item 条目 UTF-8 字节；len 非零时必须可读。
 * @param len 条目字节数。
 * @param keys 附加键数组，文本会被复制；nkeys 为零时允许为空。
 * @param nkeys 附加键数量，不含自动加入的原始键。
 * @return 成功返回真；分配或容量检查失败返回假，条目数及已有键不变。
 * @example bool ok = ffz_corpus_add_keyed(c, "abc", 3, NULL, 0);
 */
bool ffz_corpus_add_keyed(ffz_corpus *c, const char *item, size_t len,
                          const ffz_key *keys, size_t nkeys);

size_t ffz_corpus_len(const ffz_corpus *c);
void ffz_corpus_clear(ffz_corpus *c);

// One search result.
typedef struct {
    uint32_t item_index;   // index into the corpus (insertion order)
    int32_t score;         // best score across the item's keys
    int matched_kind;      // kind of the key that produced the best score
    uint32_t matched_key;  // index of that key within the item
    ffz_indices indices;   // matched codepoint positions WITHIN the matched key
} ffz_hit;

typedef struct {
    ffz_hit *hits;
    size_t len;
    size_t cap;
    // Set true only on an ffz_results* that was itself heap-allocated (the
    // ffi shim's ffz_ffi_filter*() family). false on an ffz_results embedded
    // by value elsewhere (e.g. ffz_dual_results.seq/edit) — those must be
    // released by freeing their *owner*, never individually. FFI callers:
    // this is what lets ffz_ffi_results_free() refuse to free() a pointer
    // that was never malloc'd, instead of crashing.
    bool owned;
} ffz_results;

void ffz_results_free(ffz_results *r);

// Multi-threading control for the (CPU-bound) scoring pass. Off by default.
// When `parallel` is true:
//   threads == 0  -> auto: half the logical CPUs, default-capped at 8.
//   threads  > 0  -> explicit; may exceed 8.
// A global hard ceiling of (cpu_count - 1) is ALWAYS enforced and cannot be
// exceeded by any value (leaves one core free). Also clamped to the item count;
// corpora < 512 items run single-threaded. Results are identical and
// deterministically ordered regardless of thread count.
typedef struct {
    bool parallel;
    int threads;
} ffz_parallel;

ffz_parallel ffz_parallel_off(void);             // {false, 0}
ffz_parallel ffz_parallel_auto(void);            // {true, 0}  -> half CPUs
ffz_parallel ffz_parallel_with(int threads);     // {true, threads}

// Filter the corpus with `query` (parsed with `cm`/`nm`). Results are sorted by
// score descending (ties broken by item index). If `limit > 0`, at most
// `limit` hits are returned. `mode` selects the match algorithm for the query.
// `scoring` overrides the corpus-wide default for this call.
//
// `out` is reset (any prior hits freed) unconditionally at the start of every
// call — do NOT hold pointers into a previous result across a filter call on
// the same `out`. Must be zero-initialised before the very first call:
//   ffz_results r = {0};
void ffz_corpus_filter(ffz_corpus *c, const char *query, size_t query_len,
                       ffz_case_matching cm, ffz_normalization nm,
                       ffz_mode mode, ffz_parallel par, size_t limit,
                       ffz_scoring_mode scoring,
                       ffz_results *out);

// Like ffz_corpus_filter but skips Pass 2 (index computation). All hit.indices
// will be empty (len=0). Faster when only item identity/order is needed.
void ffz_corpus_filter_raws(ffz_corpus *c, const char *query, size_t query_len,
                             ffz_case_matching cm, ffz_normalization nm,
                             ffz_mode mode, ffz_parallel par, size_t limit,
                             ffz_scoring_mode scoring,
                             ffz_results *out);

// Return the corpus-level scoring mode (stored in its ffz_config).
ffz_scoring_mode ffz_corpus_scoring(const ffz_corpus *c);

/**
 * 近似子串搜索，按距离升序返回，分数为距离的相反数，高亮为命中窗口码点。
 * @param c 有效语料库。
 * @param query 非空的查询 UTF-8 字节指针，允许零字节查询。
 * @param query_len 查询字节数，最多六十四码点；空查询匹配全部条目。
 * @param cm 大小写规则。
 * @param nm 归一化规则。
 * @param max_distance 最大编辑距离，须为非负数。
 * @param par 并行选项。
 * @param limit 结果数量上限，零表示不限。
 * @param out 结果容器，首次调用前须清零，调用后由调用方释放。
 * @return 语料库或查询为空指针、距离为负、查询超长或内部分配失败时返回假并清空结果；否则返回真。
 * @example ffz_results r = {0};
 *          bool ok = ffz_corpus_filter_edit(c, "abc", 3, FFZ_CASE_SMART, FFZ_NORM_SMART, 1, ffz_parallel_off(), 10, &r);
 *          ffz_results_free(&r);
 */
bool ffz_corpus_filter_edit(ffz_corpus *c,
                            const char *query, size_t query_len,
                            ffz_case_matching cm, ffz_normalization nm,
                            int max_distance,
                            ffz_parallel par, size_t limit,
                            ffz_results *out);

/**
 * 近似子串搜索，按距离升序返回，不填充高亮。
 * @param c 有效语料库。
 * @param query 非空的查询 UTF-8 字节指针，允许零字节查询。
 * @param query_len 查询字节数，最多六十四码点；空查询匹配全部条目。
 * @param cm 大小写规则。
 * @param nm 归一化规则。
 * @param max_distance 最大编辑距离，须为非负数。
 * @param par 并行选项。
 * @param limit 结果数量上限，零表示不限。
 * @param out 结果容器，首次调用前须清零，调用后由调用方释放。
 * @return 语料库或查询为空指针、距离为负、查询超长或内部分配失败时返回假并清空结果；否则返回真。
 * @example ffz_results r = {0};
 *          bool ok = ffz_corpus_filter_edit_raws(c, "abc", 3, FFZ_CASE_SMART, FFZ_NORM_SMART, 1, ffz_parallel_off(), 10, &r);
 *          ffz_results_free(&r);
 */
bool ffz_corpus_filter_edit_raws(ffz_corpus *c,
                                 const char *query, size_t query_len,
                                 ffz_case_matching cm, ffz_normalization nm,
                                 int max_distance,
                                 ffz_parallel par, size_t limit,
                                 ffz_results *out);

/**
 * 合并搜索；子序列命中在前，仅近似命中在后，后者分数为负的距离加一。
 * @param c 有效语料库。
 * @param query 非空的查询 UTF-8 字节指针，允许零字节查询。
 * @param query_len 查询字节数，最多六十四码点；空查询匹配全部条目。
 * @param cm 大小写规则。
 * @param nm 归一化规则。
 * @param max_distance 最大编辑距离，须为非负数。
 * @param scoring 子序列评分方式。
 * @param par 并行选项。
 * @param limit 结果数量上限，零表示不限。
 * @param out 结果容器，首次调用前须清零，调用后由调用方释放。
 * @return 语料库或查询为空指针、距离为负、查询超长或内部分配失败时返回假并清空结果；否则返回真。
 * @example ffz_results r = {0};
 *          bool ok = ffz_corpus_filter_merge(c, "abc", 3, FFZ_CASE_SMART, FFZ_NORM_SMART, 1, FFZ_SCORE_FAST, ffz_parallel_off(), 10, &r);
 *          ffz_results_free(&r);
 */
bool ffz_corpus_filter_merge(ffz_corpus *c,
                              const char *query, size_t query_len,
                              ffz_case_matching cm, ffz_normalization nm,
                              int max_distance, ffz_scoring_mode scoring,
                              ffz_parallel par, size_t limit,
                              ffz_results *out);

/**
 * 优先子序列搜索，无命中时返回近似子串搜索结果。
 * @param c 有效语料库。
 * @param query 非空的查询 UTF-8 字节指针，允许零字节查询。
 * @param query_len 查询字节数，最多六十四码点；空查询匹配全部条目。
 * @param cm 大小写规则。
 * @param nm 归一化规则。
 * @param max_distance 最大编辑距离，须为非负数。
 * @param scoring 子序列评分方式。
 * @param par 并行选项。
 * @param limit 结果数量上限，零表示不限。
 * @param out 结果容器，首次调用前须清零，调用后由调用方释放。
 * @return 语料库或查询为空指针、距离为负、查询超长或内部分配失败时返回假并清空结果；否则返回真。
 * @example ffz_results r = {0};
 *          bool ok = ffz_corpus_filter_fallback(c, "abc", 3, FFZ_CASE_SMART, FFZ_NORM_SMART, 1, FFZ_SCORE_FAST, ffz_parallel_off(), 10, &r);
 *          ffz_results_free(&r);
 */
bool ffz_corpus_filter_fallback(ffz_corpus *c,
                                 const char *query, size_t query_len,
                                 ffz_case_matching cm, ffz_normalization nm,
                                 int max_distance, ffz_scoring_mode scoring,
                                 ffz_parallel par, size_t limit,
                                 ffz_results *out);

// Dual result handle: two independent result sets in one corpus scan.
//
// 双结果句柄：一次语料库扫描产出两个独立的结果集。
typedef struct {
    ffz_results seq;   // subsequence hits (fzf scores)
    //
    // 子序列命中结果（fzf 分数）。
    ffz_results edit;  // edit-distance hits (all items, including overlap with seq)
    //
    // 编辑距离命中结果（所有条目，包括与 seq 重叠的部分）。
} ffz_dual_results;

void ffz_dual_results_free(ffz_dual_results *d);

/**
 * 分别返回子序列和近似子串命中，允许两组重叠。
 * @param c 有效语料库。
 * @param query 非空的查询 UTF-8 字节指针，允许零字节查询。
 * @param query_len 查询字节数，最多六十四码点；空查询匹配全部条目。
 * @param cm 大小写规则。
 * @param nm 归一化规则。
 * @param max_distance 最大编辑距离，须为非负数。
 * @param scoring 子序列评分方式。
 * @param par 并行选项。
 * @param limit 结果数量上限，零表示不限，分别作用于两组结果。
 * @param d 结果容器，首次调用前须清零，调用后由调用方释放。
 * @return 语料库或查询为空指针、距离为负、查询超长或内部分配失败时返回假并清空结果；否则返回真。
 * @example ffz_dual_results d = {0};
 *          bool ok = ffz_corpus_filter_dual(c, "abc", 3, FFZ_CASE_SMART, FFZ_NORM_SMART, 1, FFZ_SCORE_FAST, ffz_parallel_off(), 10, &d);
 *          ffz_dual_results_free(&d);
 */
bool ffz_corpus_filter_dual(ffz_corpus *c,
                              const char *query, size_t query_len,
                              ffz_case_matching cm, ffz_normalization nm,
                              int max_distance, ffz_scoring_mode scoring,
                              ffz_parallel par, size_t limit,
                              ffz_dual_results *d);

#ifdef __cplusplus
}
#endif
#endif  // FFZ_CORPUS_H
