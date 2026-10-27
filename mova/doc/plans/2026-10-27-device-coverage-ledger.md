# mova 公开 API 覆盖台账（v2 附录）

> 2026-10-27 · 由 `lib/mova.dart` 导出面自动生成，共 285 个公开类型。每个类型必须在「覆盖编号」列填入至少一个真机用例编号（见 `2026-10-27-device-coverage-matrix-v2.md`），并给出 PASS/FAIL/BLOCKED/INDIRECT。
> INDIRECT = 纯内部聚合类型，无法单独触发，须在备注给出经由哪个可观测输出（事件/状态/上报字段）间接验证的证据。不允许留空，也不允许写“已有单测”。

另需覆盖的顶层函数/成员：`createMovaEngine`、`movaObserveFlags`、`movaProtocolWhitelist`、`package:mova/testing.dart` 全部导出；`MovaApi`/`MovaEngine`/`MovaCutoverEngine` 的每个公开成员；`MovaOpts` 及其全部子配置的每个字段；`@Deprecated` 旧名 typedef（`lib/src/deprecated_names.dart`）各一次可用性验证。

## core/ad

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaAds | class | ads.dart |  |  |  |
| MovaAdFailKind | enum | fail.dart |  |  |  |
| MovaAdFail | class | fail.dart |  |  |  |
| MovaAdFailAction | enum | fail.dart |  |  |  |
| MovaAdFailPolicy | class | fail.dart |  |  |  |
| MovaAdRetrySkip | class | fail.dart |  |  |  |
| MovaAdAbandonPod | class | fail.dart |  |  |  |

## core

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaApi | class | api.dart |  |  |  |
| MovaEngine | class | engine.dart |  |  |  |

## core/events

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaEvent | class | events.dart |  |  |  |
| MovaReady | class | events.dart |  |  |  |
| MovaSourceChange | class | events.dart |  |  |  |
| MovaPlay | class | events.dart |  |  |  |
| MovaPause | class | events.dart |  |  |  |
| MovaDone | class | events.dart |  |  |  |
| MovaSeek | class | events.dart |  |  |  |
| MovaSeeked | class | events.dart |  |  |  |
| MovaBufferChange | class | events.dart |  |  |  |
| MovaDurationChange | class | events.dart |  |  |  |
| MovaFirstFrame | class | events.dart |  |  |  |
| MovaSizeChange | class | events.dart |  |  |  |
| MovaVolumeChange | class | events.dart |  |  |  |
| MovaBrightChange | class | events.dart |  |  |  |
| MovaRateChange | class | events.dart |  |  |  |
| MovaQualityListChange | class | events.dart |  |  |  |
| MovaQualityChange | class | events.dart |  |  |  |
| MovaAbrDownShift | class | events.dart |  |  |  |
| MovaFitChange | class | events.dart |  |  |  |
| MovaZoomChange | class | events.dart |  |  |  |
| MovaLockChange | class | events.dart |  |  |  |
| MovaFullScreenChange | class | events.dart |  |  |  |
| MovaOrientationChange | class | events.dart |  |  |  |
| MovaPipChange | class | events.dart |  |  |  |
| MovaMiniChange | class | events.dart |  |  |  |
| MovaTimeShiftChange | class | events.dart |  |  |  |
| MovaLiveEdgeReach | class | events.dart |  |  |  |
| MovaPreviewBlock | class | events.dart |  |  |  |
| MovaSttBlock | class | events.dart |  |  |  |
| MovaCutoverChange | class | events.dart |  |  |  |
| MovaErrorEvent | class | events.dart |  |  |  |
| MovaPlayFailure | class | events.dart |  |  |  |
| MovaRecovered | class | events.dart |  |  |  |
| MovaFailover | class | events.dart |  |  |  |
| MovaKeepAliveChange | class | events.dart |  |  |  |
| MovaKeepAliveResume | class | events.dart |  |  |  |

## core/feed

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaEngineFactory | typedef | engine_pool.dart |  |  |  |
| MovaFeedSlot | class | engine_pool.dart |  |  |  |
| MovaFeedEnginePool | class | engine_pool.dart |  |  |  |
| MovaFeedLoader | typedef | feed.dart |  |  |  |
| MovaFeed | class | feed.dart |  |  |  |
| MovaFeedPrefetcher | class | feed_prefetcher.dart |  |  |  |
| MovaNetworkWarmFeedPrefetcher | class | feed_prefetcher.dart |  |  |  |

## core/guard

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaHideReason | enum | auto_pause.dart |  |  |  |
| MovaLiveResume | enum | auto_pause.dart |  |  |  |
| MovaHiddenMode | enum | auto_pause.dart |  |  |  |
| MovaAutoPauseConfig | class | auto_pause.dart |  |  |  |
| MovaGuardAction | enum | auto_pause.dart |  |  |  |
| MovaAutoPauseGate | class | auto_pause.dart |  |  |  |

## core/interceptor

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaHook | class | interceptor.dart |  |  |  |
| MovaHookChain | class | interceptor.dart |  |  |  |

## core/mini

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaMiniRect | class | placement.dart |  |  |  |
| MovaMiniInsets | class | placement.dart |  |  |  |
| MovaMiniPlacement | class | placement.dart |  |  |  |
| MovaCornerSnap | class | placement.dart |  |  |  |

## core/model

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaAdBreakKind | enum | ad.dart |  |  |  |
| MovaAdBreak | class | ad.dart |  |  |  |
| MovaAdEventType | enum | ad.dart |  |  |  |
| MovaAdEvent | class | ad.dart |  |  |  |
| MovaDanmakuItem | class | danmaku.dart |  |  |  |
| MovaFeedLikeChange | typedef | feed_item.dart |  |  |  |
| MovaFeedItem | class | feed_item.dart |  |  |  |
| MovaFit | enum | fit.dart |  |  |  |
| MovaOrientation | enum | orientation.dart |  |  |  |
| MovaPlaylistItem | class | playlist.dart |  |  |  |
| MovaQuality | class | quality.dart |  |  |  |
| MovaStreamType | enum | source.dart |  |  |  |
| MovaSource | class | source.dart |  |  |  |
| MovaSourceResolver | typedef | source.dart |  |  |  |

## core/options

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaOpts | class | options.dart |  |  |  |

## core/platform

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaBrightPort | class | ports.dart |  |  |  |
| MovaVolumePort | class | ports.dart |  |  |  |
| MovaPipPort | class | ports.dart |  |  |  |
| MovaPipObservable | class | ports.dart |  |  |  |
| MovaOrientationPort | class | ports.dart |  |  |  |
| MovaFallbackBrightnessPort | class | ports.dart |  |  |  |
| MovaFallbackVolumePort | class | ports.dart |  |  |  |
| MovaCallbackVolumePort | class | ports.dart |  |  |  |
| MovaNoopPipPort | class | ports.dart |  |  |  |
| MovaNoopOrientationPort | class | ports.dart |  |  |  |

## core/playlist

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaPlaylist | class | playlist.dart |  |  |  |

## core/preview

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaPreviewApi | class | api.dart |  |  |  |
| MovaThumbCache | class | cache.dart |  |  |  |
| MovaMemoryThumbCache | class | cache.dart |  |  |  |
| MovaThumbDirProvider | class | dir_provider.dart |  |  |  |
| MovaFixedThumbDirProvider | class | dir_provider.dart |  |  |  |
| MovaDiskThumbCache | class | disk_cache.dart |  |  |  |
| MovaFramePuller | class | extractor.dart |  |  |  |
| MovaPullerThumbSource | class | extractor.dart |  |  |  |
| MovaHttpFetch | class | fetcher.dart |  |  |  |
| MovaIoHttpFetcher | class | fetcher.dart |  |  |  |
| MovaCacheKeyBuilder | typedef | hash.dart |  |  |  |
| MovaThumbCrop | class | models.dart |  |  |  |
| MovaThumb | class | models.dart |  |  |  |
| MovaThumbCue | class | models.dart |  |  |  |
| MovaThumbIndex | class | models.dart |  |  |  |
| MovaPreviewNet | enum | net_probe.dart |  |  |  |
| MovaNetProbe | class | net_probe.dart |  |  |  |
| MovaAlwaysAllowNetProbe | class | net_probe.dart |  |  |  |
| MovaPlatformKind | enum | platform_kind.dart |  |  |  |
| MovaPreviewService | class | service.dart |  |  |  |
| MovaThumbSource | class | source.dart |  |  |  |
| MovaTwoLevelCache | class | two_level_cache.dart |  |  |  |
| MovaVttUrlSolver | typedef | vtt_source.dart |  |  |  |
| MovaVttThumbSource | class | vtt_source.dart |  |  |  |

## core/recovery

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaPlayFailKind | enum | fail.dart |  |  |  |
| MovaPlayFail | class | fail.dart |  |  |  |
| MovaRecoveryAction | enum | fail.dart |  |  |  |
| MovaRecoveryDecision | class | fail.dart |  |  |  |
| MovaRecoveryPolicy | class | fail.dart |  |  |  |
| MovaRetryThenFailover | class | fail.dart |  |  |  |
| MovaLiveReconnect | class | fail.dart |  |  |  |
| MovaDefaultRecovery | class | fail.dart |  |  |  |
| MovaFailoverOnly | class | fail.dart |  |  |  |
| MovaGiveUpError | class | fail.dart |  |  |  |

## core/render

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaFirstFrameSignal | enum | first_frame.dart |  |  |  |
| MovaFirstFrameGate | class | first_frame.dart |  |  |  |

## core/report

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaErrorVerdict | class | error_policy.dart |  |  |  |
| MovaErrorPolicy | class | error_policy.dart |  |  |  |
| MovaPrefixError | class | error_policy.dart |  |  |  |
| MovaReportKind | enum | report.dart |  |  |  |
| MovaReportPriority | enum | report.dart |  |  |  |
| MovaReportName | class | report.dart |  |  |  |
| MovaReportEvent | class | report.dart |  |  |  |
| MovaReporter | class | report.dart |  |  |  |
| MovaCallbackReporter | class | report.dart |  |  |  |
| MovaSessionEnd | enum | session.dart |  |  |  |
| MovaSessionTally | class | session.dart |  |  |  |
| MovaSessionIdFactory | typedef | session_id.dart |  |  |  |
| MovaStall | class | stall.dart |  |  |  |
| MovaStallPolicy | class | stall.dart |  |  |  |
| MovaEdgeStall | class | stall.dart |  |  |  |
| MovaLogLine | class | stats_probe.dart |  |  |  |
| MovaStatsSnapshot | class | stats_probe.dart |  |  |  |
| MovaEndFileReason | enum | stats_probe.dart |  |  |  |
| MovaStatsProbe | class | stats_probe.dart |  |  |  |

## core/keep_alive

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaKeepAlivePhase | enum | keep_alive.dart |  |  |  |
| MovaKeepAliveMode | enum | keep_alive.dart |  |  |  |
| MovaKeepAliveReason | enum | keep_alive.dart |  |  |  |
| MovaKeepAlive | class | keep_alive.dart |  |  |  |

## core/state

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaProg | class | progress.dart |  |  |  |
| MovaState | class | state.dart |  |  |  |
| MovaHud | enum | ui_state.dart |  |  |  |
| MovaUiState | class | ui_state.dart |  |  |  |

## core/stt

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaSttApi | class | api.dart |  |  |  |
| MovaAudioPuller | class | audio_extractor.dart |  |  |  |
| MovaSttCue | class | cue.dart |  |  |  |
| MovaSttModelDirProvider | class | model_dir_provider.dart |  |  |  |
| MovaFixedSttModelDirProvider | class | model_dir_provider.dart |  |  |  |
| MovaSttModelProg | class | model_provider.dart |  |  |  |
| MovaSttModelLoadError | class | model_provider.dart |  |  |  |
| MovaSttModelProvider | class | model_provider.dart |  |  |  |
| MovaSttModelLoader | class | model_provider.dart |  |  |  |
| MovaSttModelFile | class | model_spec.dart |  |  |  |
| MovaSttModelSpec | class | model_spec.dart |  |  |  |
| MovaSttModelFiles | class | model_spec.dart |  |  |  |
| MovaSttEngine | class | port.dart |  |  |  |
| MovaNoopSttEngine | class | port.dart |  |  |  |
| MovaSttChunkSubtitleStore | class | chunk_subtitle_store.dart |  |  |  |
| MovaFileSttChunkSubtitleStore | class | chunk_subtitle_store.dart |  |  |  |
| MovaSttService | class | service.dart |  |  |  |
| MovaSttSubtitleDirProvider | class | subtitle_dir_provider.dart |  |  |  |
| MovaFixedSttSubtitleDirProvider | class | subtitle_dir_provider.dart |  |  |  |
| MovaSttSubtitleStore | class | subtitle_store.dart |  |  |  |
| MovaFileSttSubtitleStore | class | subtitle_store.dart |  |  |  |

## core/cutover

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaCutoverPhase | enum | ctl.dart |  |  |  |
| MovaCutover | class | ctl.dart |  |  |  |
| MovaWarmPlan | class | plan.dart |  |  |  |
| MovaCutoverEngine | class | cutover_engine.dart |  |  |  |
| MovaWarmCue | class | trigger.dart |  |  |  |
| MovaWarmTrigger | class | trigger.dart |  |  |  |
| MovaLeadWarm | class | trigger.dart |  |  |  |
| MovaEagerWarm | class | trigger.dart |  |  |  |
| MovaWarmSignal | class | warm.dart |  |  |  |
| MovaWarmVerdict | enum | warm.dart |  |  |  |
| MovaWarmPolicy | class | warm.dart |  |  |  |
| MovaBufferWarm | class | warm.dart |  |  |  |

## (root)

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaAdController | typedef | deprecated_names.dart |  |  |  |
| MovaFeedController | typedef | deprecated_names.dart |  |  |  |
| MovaPlaylistController | typedef | deprecated_names.dart |  |  |  |
| MovaMiniController | typedef | deprecated_names.dart |  |  |  |
| MovaSwapEngine | typedef | deprecated_names.dart |  |  |  |
| MovaSwapController | typedef | deprecated_names.dart |  |  |  |
| MovaSwapConfig | typedef | deprecated_names.dart |  |  |  |
| MovaSwapChange | typedef | deprecated_names.dart |  |  |  |
| MovaSwapPhase | typedef | deprecated_names.dart |  |  |  |
| MovaStandbyController | typedef | deprecated_names.dart |  |  |  |
| MovaStandbyConfig | typedef | deprecated_names.dart |  |  |  |
| MovaStandbyPhase | typedef | deprecated_names.dart |  |  |  |
| MovaStandbyMode | typedef | deprecated_names.dart |  |  |  |
| MovaStandbyReason | typedef | deprecated_names.dart |  |  |  |
| MovaStandbyChange | typedef | deprecated_names.dart |  |  |  |
| MovaStandbyResume | typedef | deprecated_names.dart |  |  |  |
| MovaSilentStandby | typedef | deprecated_names.dart |  |  |  |

## platform_impl

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaAudioExtractor | class | mpv_audio_extractor_impl.dart |  |  |  |
| MovaFrameExtractor | class | mpv_extractor_impl.dart |  |  |  |
| MovaConnectivityNetProbe | class | net_probe_impl.dart |  |  |  |
| MovaTempSttModelDirProvider | class | stt_model_dir_impl.dart |  |  |  |
| MovaTempSttSubtitleDirProvider | class | stt_subtitle_dir_impl.dart |  |  |  |
| MovaTempThumbDirProvider | class | thumb_dir_impl.dart |  |  |  |
| MovaScreenBrightnessPort | class | brightness_impl.dart |  |  |  |
| MovaSystemChromeOrientationPort | class | orientation_impl.dart |  |  |  |
| MovaChannelPipPort | class | pip_impl.dart |  |  |  |
| MovaSystemVolumePort | class | volume_impl.dart |  |  |  |

## ui/components

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaAdOverlayComponent | class | ad_overlay.dart |  |  |  |
| MovaBottomBarComponent | class | bottom_bar.dart |  |  |  |
| MovaPositionLabelComponent | class | bottom_bar.dart |  |  |  |
| MovaDurationLabelComponent | class | bottom_bar.dart |  |  |  |
| MovaSeekBarComponent | class | bottom_bar.dart |  |  |  |
| MovaLiveBadgeComponent | class | bottom_bar.dart |  |  |  |
| MovaTimeshiftLabelComponent | class | bottom_bar.dart |  |  |  |
| MovaBackToLiveComponent | class | bottom_bar.dart |  |  |  |
| MovaCenterPlayComponent | class | center_play.dart |  |  |  |
| MovaPlayPauseComponent | class | center_play.dart |  |  |  |
| MovaIconButton | class | common.dart |  |  |  |
| MovaGradBar | class | common.dart |  |  |  |
| MovaSheetItem | class | common.dart |  |  |  |
| MovaDanmakuTrackComponent | class | danmaku.dart |  |  |  |
| MovaDouyinGestureLayerComponent | class | douyin_gesture_layer.dart |  |  |  |
| MovaSocialRailComponent | class | feed_social.dart |  |  |  |
| MovaAvatarComponent | class | feed_social.dart |  |  |  |
| MovaLikeButtonComponent | class | feed_social.dart |  |  |  |
| MovaCommentButtonComponent | class | feed_social.dart |  |  |  |
| MovaShareButtonComponent | class | feed_social.dart |  |  |  |
| MovaFeedInfoComponent | class | feed_social.dart |  |  |  |
| MovaGestureLayerComponent | class | gesture_layer.dart |  |  |  |
| MovaHudLayerComponent | class | hud_layer.dart |  |  |  |
| MovaVolumeHudComponent | class | hud_layer.dart |  |  |  |
| MovaBrightnessHudComponent | class | hud_layer.dart |  |  |  |
| MovaSeekHudComponent | class | hud_layer.dart |  |  |  |
| MovaZoomHudComponent | class | hud_layer.dart |  |  |  |
| MovaNextUpComponent | class | next_up.dart |  |  |  |
| MovaBufferingComponent | class | overlays.dart |  |  |  |
| MovaErrorComponent | class | overlays.dart |  |  |  |
| MovaLockMaskComponent | class | overlays.dart |  |  |  |
| MovaPreviewComponent | class | preview.dart |  |  |  |
| MovaSpeedButtonComponent | class | speed_button.dart |  |  |  |
| MovaSubtitleOverlayComponent | class | subtitle.dart |  |  |  |
| MovaSubtitleButtonComponent | class | subtitle.dart |  |  |  |
| MovaTopBarComponent | class | top_bar.dart |  |  |  |
| MovaTitleComponent | class | top_bar.dart |  |  |  |
| MovaPipButtonComponent | class | top_bar.dart |  |  |  |
| MovaQualityButtonComponent | class | top_bar.dart |  |  |  |
| MovaFitButtonComponent | class | top_bar.dart |  |  |  |
| MovaOrientationButtonComponent | class | top_bar.dart |  |  |  |
| MovaFullscreenButtonComponent | class | top_bar.dart |  |  |  |

## ui

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaFeedHolderBuilder | typedef | feed_player.dart |  |  |  |
| MovaFeedPlayer | class | feed_player.dart |  |  |  |
| MovaPlayer | class | player.dart |  |  |  |
| MovaViewEngineFactory | typedef | view.dart |  |  |  |
| MovaView | class | view.dart |  |  |  |

## ui/guard

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaAutoPause | class | auto_pause.dart |  |  |  |

## ui/mini

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaMiniMount | enum | mini.dart |  |  |  |
| MovaMini | class | mini.dart |  |  |  |
| MovaMiniHost | class | mini_host.dart |  |  |  |
| MovaMiniSkin | class | mini_skin.dart |  |  |  |
| MovaMiniCloseComponent | class | mini_skin.dart |  |  |  |
| MovaMiniWindow | class | mini_window.dart |  |  |  |

## ui/scope

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaPlugin | mixin | plugin.dart |  |  |  |
| MovaScope | class | scope.dart |  |  |  |
| MovaSelect | class | selector.dart |  |  |  |
| MovaProgSelect | class | selector.dart |  |  |  |
| MovaUiSelect | class | selector.dart |  |  |  |

## ui/skins

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaBilibiliSkin | class | bilibili_skin.dart |  |  |  |
| MovaDefaultSkin | class | default_skin.dart |  |  |  |
| MovaDouyinSkin | class | douyin_skin.dart |  |  |  |
| MovaMinimalSkin | class | minimal_skin.dart |  |  |  |
| MovaSkin | class | skin.dart |  |  |  |

## ui/slots

| 类型 | 种类 | 来源文件 | 覆盖编号 | 结论 | 备注/证据 |
|---|---|---|---|---|---|
| MovaComponent | class | component.dart |  |  |  |
| MovaPatch | class | patch.dart |  |  |  |
| MovaPatchReplace | class | patch.dart |  |  |  |
| MovaPatchRemove | class | patch.dart |  |  |  |
| MovaPatchInsertAfter | class | patch.dart |  |  |  |
| MovaPatchAdd | class | patch.dart |  |  |  |
| MovaSlot | enum | slot.dart |  |  |  |
| MovaSlotBundle | class | tree.dart |  |  |  |
