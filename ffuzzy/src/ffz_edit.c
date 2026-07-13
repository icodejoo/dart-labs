// Myers bit-parallel edit distance — single-block path (qlen ≤ 64 codepoints).
//
// References:
//   Gene Myers, "A Fast Bit-Vector Algorithm for Approximate String Matching
//   Based on Dynamic Programming", JACM 1999.
//   edlib (Martinsos/edlib, MIT) — calculateBlock inner loop formulation.
//   rapidfuzz-cpp (maxbachmann/rapidfuzz-cpp, MIT) — Unicode Peq strategy.
//
// Both algorithms are always compiled together.
#include <stdlib.h>
#include "ffz_internal.h"

// ---------------------------------------------------------------------------
// Pattern-equivalence vector (Peq)
// ---------------------------------------------------------------------------
// One 64-bit word per distinct (normalised) codepoint in the query.
// ASCII codepoints [0,127] get a dense array; non-ASCII (≤ 64 distinct values,
// bounded by qlen ≤ 64) use parallel arrays searched linearly.

typedef uint64_t Word;

typedef struct {
    Word ascii[128];               // ASCII fast path
    uint32_t nc_cp[64];            // non-ASCII codepoints
    Word     nc_bits[64];          // corresponding Peq words
    int      nc_len;               // number of distinct non-ASCII entries
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
// Public function
// ---------------------------------------------------------------------------

int ffz_edit_distance(ffz_str query, ffz_str hay,
                      int max_dist, const ffz_config *cfg) {
    // Single-block path only.
    if ((int)query.len > 64) return max_dist + 1;

    int qlen = (int)query.len;
    int hlen = (int)hay.len;

    // Trivial cases.
    if (qlen == 0) return 0;
    if (hlen == 0) return qlen <= max_dist ? qlen : -1;

    // --- Common prefix strip ---
    size_t pre = 0;
    while (pre < (size_t)qlen && pre < (size_t)hlen) {
        uint32_t qcp = ffz_normalize_cp(ffz_at(query, pre), cfg);
        uint32_t hcp = ffz_normalize_cp(ffz_at(hay,   pre), cfg);
        if (qcp != hcp) break;
        pre++;
    }
    // --- Common suffix strip ---
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
    int q0 = (int)pre;
    int q1 = qlen  - (int)suf;   // exclusive
    int h0 = (int)pre;
    int h1 = hlen  - (int)suf;   // exclusive

    int new_qlen = q1 - q0;
    int new_hlen = h1 - h0;

    // Free distance from the stripped characters (pure insertions/deletions
    // after the common prefix/suffix are removed).
    int free_dist = abs(new_qlen - new_hlen);
    if (new_qlen == 0) {
        // All query chars matched in suffix/prefix; remaining hay chars = deletions.
        return new_hlen <= max_dist ? new_hlen : -1;
    }
    if (new_hlen == 0) {
        return new_qlen <= max_dist ? new_qlen : -1;
    }

    // Build a new query view for the reduced range.
    // Re-use a local codepoint buffer so we don't need heap allocation.
    uint32_t qbuf[64];
    for (int i = 0; i < new_qlen; i++)
        qbuf[i] = ffz_at(query, (size_t)(q0 + i));

    // Build Peq over the reduced query.
    ffz_peq peq;
    // We need a ffz_str over the reduced slice.
    ffz_str qslice;
    qslice.b = NULL;
    qslice.u = qbuf;
    qslice.len = (size_t)new_qlen;

    peq_build(&peq, qslice, cfg);

    // Myers single-block DP.
    Word VP = ~(Word)0;
    Word VN = (Word)0;
    int score = new_qlen;
    Word mask = (Word)1 << (new_qlen - 1);

    for (int col = h0; col < h1; col++) {
        int remaining = (h1 - 1) - col;  // columns still to process after this one

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
        if (score - remaining > max_dist) return -1;

        HP = (HP << 1) | (Word)1;
        HN <<= 1;
        VP = HN | ~(D0 | HP);
        VN = HP & D0;
    }

    return score <= max_dist ? score : -1;
}
