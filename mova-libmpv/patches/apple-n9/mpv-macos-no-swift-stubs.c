/*
 * mova：mpv 0.41 在 macOS 上去掉 Swift 之后的桩。
 *
 * 0.41 把 cocoa 层改成了 Swift（osdep/mac/*.swift），libmpv 里仍有几处在 HAVE_COCOA 下引用
 * 原本由 Swift 提供的符号，以及 clipboard-mac.m（依赖 swift.h）。本构建不编 Swift，
 * 用这个文件补齐，行为等同"没有 macOS 菜单栏/媒体键/剪贴板集成"，对 libmpv 渲染 API 无影响。
 */
#include "config.h"
#include "osdep/mac/app_bridge.h"
#include "player/clipboard/clipboard.h"

/* 媒体键：不接管 */
void cocoa_init_media_keys(void) {}
void cocoa_uninit_media_keys(void) {}

/* 给 Swift 层传 input / client 句柄：没有 Swift 层，忽略 */
void cocoa_set_input_context(struct input_ctx *input_context) { (void)input_context; }
void cocoa_set_mpv_handle(struct mpv_handle *ctx) { (void)ctx; }

/* 剪贴板后端：init 直接报不可用，clipboard.c 会跳过它 */
static int stub_init(struct clipboard_ctx *cl, struct clipboard_init_params *params)
{
    (void)cl;
    (void)params;
    return CLIPBOARD_UNAVAILABLE;
}

const struct clipboard_backend clipboard_backend_mac = {
    .name = "mac",
    .desc = "macOS clipboard (disabled in mova build)",
    .init = stub_init,
};
