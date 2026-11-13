## 0.5.1

- Docs: pubspec `homepage` and `repository` now point to the package directory on the `main` branch.

## 0.5.0

- **Breaking: public API renamed across the board. Old names are removed with no `@Deprecated` aliases** (`lib/src/deprecated_names.dart` is deleted, including the earlier `*Controller`/`Swap*`/`Standby*` class aliases; the member-level `@Deprecated` aliases are deleted too, see the list below). Migration table:

  | Old | New |
  |---|---|
  | `MovaEngine` / `createMovaEngine` | `Mova` / `createMova` |
  | `MovaEngineFactory` / `MovaViewEngineFactory` | `MovaFactory` / `MovaViewFactory` |
  | `MovaCutoverEngine` / `MovaFeedEnginePool` | `MovaCutover` / `MovaFeedPool` |
  | `MovaSttEngine` / `MovaSttSessionEngine` / `MovaNoopSttEngine` | `IMovaStt` / `IMovaSttSession` / `MovaNoopStt` |
  | `MovaSkin` | `IMovaUiKit` |
  | `MovaDefaultSkin` / `MovaMinimalSkin` / `MovaMiniSkin` / `MovaBilibiliSkin` / `MovaDouyinSkin` | `MovaDefaultUiKit` / `MovaMinimalUiKit` / `MovaMiniUiKit` / `MovaBilibiliUiKit` / `MovaDouyinUiKit` |
  | `package:mova/skin.dart` | `package:mova/ui_kit.dart` |
  | `Mova*Config` (`MovaAbrConfig`, `MovaAdConfig`, `MovaAutoPauseConfig`, `MovaCtrlsConfig`, `MovaCutoverConfig`, `MovaDanmakuConfig`, `MovaGestureConfig`, `MovaKeepAliveConfig`, `MovaLiveConfig`, `MovaMiniConfig`, `MovaPlaylistConfig`, `MovaPreviewConfig`, `MovaRecoveryConfig`, `MovaReportConfig`, `MovaSttConfig`) | `Mova*Opts` |
  | `MovaOrientationConfig` | `MovaOrientOpts` |
  | `MovaBrightPort` / `MovaBrightRestore` | `IMovaBrightness` / `IMovaBrightnessRestore` |
  | `MovaScreenBrightnessPort` / `MovaFallbackBrightnessPort` | `MovaBrightness` / `MovaFallbackBrightness` |
  | `MovaVolumePort` | `IMovaVolume` |
  | `MovaSystemVolumePort` / `MovaCallbackVolumePort` / `MovaFallbackVolumePort` | `MovaSystemVolume` / `MovaCallbackVolume` / `MovaFallbackVolume` |
  | `MovaPipPort` / `MovaPipObservable` | `IMovaPip` / `IMovaPipObservable` |
  | `MovaChannelPipPort` / `MovaNoopPipPort` | `MovaPip` / `MovaNoopPip` |
  | `MovaOrientationPort` | `IMovaOrient` |
  | `MovaSystemChromeOrientationPort` / `MovaNoopOrientationPort` | `MovaOrient` / `MovaNoopOrient` |
  | `MovaOrientation` (enum) | `MovaOrientMode` |
  | `MovaOrientationChange` / `MovaOrientationButtonComponent` | `MovaOrientChange` / `MovaOrientButtonComponent` |
  | `IMovaApi.setOrientation` / `MovaState.orientation` | `setOrient` / `orient` |
  | `preferredOrientationsFor` / `resolveOrientations` | `preferredOrientsFor` / `resolveOrients` |
  | `MovaCutover` (capability interface) | `IMovaCutover` |
  | Every other abstract interface `MovaXxx` | `IMovaXxx` (e.g. `MovaApi` → `IMovaApi`, `MovaKernel` → `IMovaKernel`, `MovaKeepAlive` → `IMovaKeepAlive`, `MovaThumbSource` → `IMovaThumbSource`, `MovaReporter` → `IMovaReporter`) |

  Parameters and members follow the same rules: `engine` → `mova` (`engineFactory` → `movaFactory`, `MovaFeedPool.engineCount` → `movaCount`, `MovaOpts.engineSectionsEqual` → `movaSectionsEqual`), `skin` → `uiKit`, `config` → `opts`, `orientation` → `orient` (`orientationConfig` → `orientOpts`, `allowedOrientations` → `allowedOrients`), and `*Port` members drop the suffix (`debugBrightnessPort` → `debugBrightness`, etc.). On the STT side the recognizer is named `recognizer`: `MovaSttOpts.engine` → `recognizer`, `hasEngine` → `hasRecognizer`, `MovaSttBlockReason.noEngine` → `noRecognizer`.
  Additional migration items of this round (the former `*Controller` classes' parameters and fields, deleted member aliases, report and path names):

  * `MovaFeedPlayerController` → `MovaFeedPlayerCtrl`; `MovaFeedPlayer(controller:)` → `MovaFeedPlayer(ctrl:)`.
  * `MovaDouyinUiKit(controller:)` and the `controller:` parameter of the feed components → `feed:` (the argument is a `MovaFeed`).
  * `MovaNextUpComponent.controller` → `playlist` (the argument is a `MovaPlaylist`).
  * `MovaMiniWindow(ctl:)` → `mini:`.
  * Deleted member aliases (they no longer exist in any form): `MovaOpts.standby` / `MovaOpts.swap` (use `keepAlive` / `cutover`), `MovaState.standby` (use `keepAlivePhase`), `MovaHiddenMode.standby` (use `keepAlive`), `MovaMiniHost(ctl:)` and `MovaMiniHost.ctl`, `MovaAdOverlayComponent.controller` (use `ads`). `MovaMiniHost(mini:)` is now `required`.
  * **QoE session field `swapEnabled` → `cutoverEnabled`. This changes the report payload, so any backend, dashboard or parser that reads `swapEnabled` must be updated.** The 2026-10-27 round kept this key unchanged; this version renames it.
  * Component path name `orientationButton` → `orientButton` (the `componentName` of `MovaOrientButtonComponent`). `MovaPatch` addressing that uses the old path (for example `'${MovaTopBarComponent.componentName}/orientationButton'`) no longer matches; use `MovaOrientButtonComponent.componentName`.
  * Internal file `src/core/cutover/ctl.dart` → `api.dart` (only affects code that imports `package:mova/src/...` directly).
- The thumbnail cache directory prefix changes from `engine_` to `mova_`. `engine_*` directories left by older versions are no longer recognized or cleaned up.

## 0.4.3

- Docs only: rewrote README wording in plain language; the HarmonyOS spike project under tool/ is no longer shipped in the package.

The full original Chinese changelog is kept in [CHANGES.zh-CN.md](https://github.com/icodejoo/dart-labs/blob/main/mova/CHANGES.zh-CN.md).

## 0.4.2

Documentation and metadata only. No runtime behavior change.

- `pubspec.yaml` `description` rewritten in English (pub.dev requires an ASCII-friendly 60-180 character description).
- `README.md` is now English. The previous Chinese README is kept as `README.zh-CN.md`; both link to each other at the top.
- `CHANGELOG.md` is now English (0.4.x in full, older versions condensed, with all breaking/migration notes kept). The full Chinese text is kept as `CHANGES.zh-CN.md`.
- Links to `doc/` in the README are now absolute GitHub links (the published package excludes `doc/` through `.pubignore`); the stale `mini_window_demo.dart` link now points at an example file that exists.
- `example/README.md` entry table rewritten against the real files under `example/lib`.
- Documentation revisions in `doc/SPEC.md` and the README.
- Relaxed the `connectivity_plus` constraint so the latest major version (`^7`) can be resolved.

## 0.4.1

- Full-review deferred P3 wrap-up (non-device part): the mini window and fullscreen/system PiP are now mutually exclusive in both directions (`setMini(true)` is rejected while in PiP and `MovaMini.show` then revokes the handoff; entering fullscreen collapses the mini window first). Format probing is now armed just before the real open (the END_FILE start-gate approach was shown by a real-device A/B run to make HE V9 background/foreground resume pass only 1 of 5 times, so it was reverted; B1 still waits for a native file identity). A failed keepAlive restore keeps the original value and retries next time. A mid-roll warm-up no longer swallows the end event when the content really plays to its end (end events produced as a by-product of a cutover are still swallowed). The watchdog deadline honors a source-level `network-timeout`. `stallMs` only counts stalls accepted by the policy (jitter is given back to watch time). Sub-second preview buckets use millisecond cache keys. Residual WAV files are deleted after audio extraction fails or is cancelled. The test baseline is whatever the current `flutter test` run reports.

- Full-review P3 fixes (22 of 40 fixed, 9 no longer valid, 9 deferred): an out-of-order async `beforeSeek` result no longer overwrites a newer seek; DVR back-to-live-edge leaves no stale seek filter; an internally re-issued seek that fails is reported as a non-terminal error and releases the filter; a late initial volume no longer overrides the user's setting; cutover `dispose` immediately releases a claimed shadow and the latest playback rate is applied before the cutover; a disposed `MovaPlaylist` no longer switches source on navigation; kernel per-source option transactions are serialized and `dispose` waits for native preparation with an upper bound; changing the guard config while hidden takes effect immediately; QoE does not count stalls during a user pause and an injected stall policy is reset per session; STT model and subtitle caches are written atomically and the downloaded size is verified; the preview cache key distinguishes request headers (unchanged when there are none), disabled preview no longer bypasses the switch through the cache, an illegal VTT crop degrades to the whole image; drag-seek preview and commit share the same starting point; the subtitle button reflects the real running state; the mini window recomputes geometry when its player changes.

- Request-header and event-delivery fixes: when the same URL is opened by two players (content and cutover shadow, or a feed pool) or by a retry with different headers, they no longer share each other's headers (each load uses an independent media_kit cache key and the fragment is not sent to the server); a failure to parse `http-header-fields` no longer silently clears the headers and is reported through the diagnostics stream instead; after a synchronous event listener switches source inside callbacks such as `MovaDone`/`MovaSourceChange`, the old source's remaining logic (live end, keepAlive downgrade, Ready, quality probing) no longer runs, and an open rejected by `beforeOpen` does not affect an in-flight quality switch or recovery; `screenshot()` also retries within a 2 second total budget while playing, with a 3 second outer fallback for cutover; `MovaFeedPlayerCtrl.pause()` no longer waits for activation to finish and no longer throws activation errors.

- Final-review follow-up fixes: a `play()` arriving inside the cutover commit window is also forwarded to the shadow about to take over, so the post-cutover state matches the latest play intent; exceptions thrown by host ad callbacks are, besides being logged, handed to the current Zone's `handleUncaughtError` so they can reach the host crash collector without interrupting ads or resume; URL time-shift lag keeps growing while paused, is kept after resuming and cleared on back-to-live-edge, and `seekBy` and retries compute from the lag including pause time.

- Full source-review fixes (27 P1/P2 items): when the host calls `open()` directly to switch source, the old ad session yields and does not grab the original source back; `dispose()` no longer hangs when the event stream has a paused subscription; a new seek during a quality-switch load is not overwritten; replay/keepAlive waits honor a pause that happened in between; a terminal error cancels a scheduled recovery retry; leaving fullscreen keeps a forced orientation (only `auto` restores the host orientation); HLS variants are sorted video-first and ABR never drops to an audio-only variant; cutover re-checks play intent before the cutover and a fatal shadow is not promoted; a feed activation failure does not block the latest page and prefetch is truncated by a byte budget; QoE respects the player `fatal/code`, and a manual start is landed only by the first frame and does not report TTFF; STT model id/filename path validation; lifecycle races of the mini window, fullscreen route and frame extractor; component patches fetch children by name, the progress bar follows the seek that was actually accepted, and the mini window fling is decided per axis.

- Corrected the overall CP3 headers criterion: with `CP3_HEADERS_READY` on, acceptance uses the bounded screenshot of the normal/cutover player, and the old native `pool` screenshot is kept as a diagnostic; quality switching stores the full variant list and the native path of the selected variant, and requires the auto and 360p variants, addresses and the rejection control to be correct. A new APK must be built and re-verified; old FAILs are not rewritten.

- The headers fixture gained `CP3_HEADERS_READY`: independent normal/cutover paused-pool instances use the bounded screenshot capability right after bind returns, counting authorized screenshot nulls and successful image decodes, and keeping the rejected-auth and raw screenshot controls. A new APK must be built and re-verified.

- Fixed insufficient waiting for the fifth-round paused-pool screenshot: the total budget of `IMovaFrameCapture.screenshot()` is unified at 2 seconds for normal and cutover players (including native capture and encoding), and screenshots are no longer gated on `rendered`; an empty result calls the kernel again at intervals starting at 50ms and growing to 250ms, and only an actually non-empty image counts as success. Timeout/failure still returns null; the `CP3_HEADERS_READY` criteria (null=0/30, decode success=30/30) are unchanged and need a new APK to re-verify.

- Added the optional `IMovaFrameCapture.screenshot()`, supported by normal and cutover players. Pause warm-up completes only after a non-empty screenshot within 2 seconds in total; a timeout/failure returns null, and stale results after a source switch, dispose or cutover are discarded. It does not play or seek, `IMovaApi` gains no members, and pool bind/ready and the original first-frame event keep their semantics.

- Preview frame extraction: after the first seek-landing wait times out it re-sends one seek and re-confirms the landing point; a second timeout still returns null and no unconfirmed frame is captured. A duration-ready timeout and a screenshot failure still return null.

- The pool warm-up probe now records non-empty screenshot evidence of the paused picture and the first-frame signal source, so size/grace fallbacks are not mistaken for real decoding success.

- The headers frame-extraction fixture keeps the first empty frame / byte count / elapsed time and exception classification, and keeps positive/negative auth ownership, without covering sporadic failures with automatic retries.

- The resource fixture no longer follows dynamic fd links; it reads thread/fd/CPU independently and records errors; it adds phase sampling for concurrent page flips and for 0/1/5 seconds after release, and a logical pool dropping to zero is not taken as proof that native resources were reclaimed.

- The receipt fixture no longer compares the Seeked payload with the independently throttled progress stream for strict equality; it stores three position readings separately and states that this is not a native landing acceptance; the Size/Quality state consistency criterion is kept.

- The normal `Mova` delivers state events synchronously after updating state, fixing event payloads that disagreed with the receiver's `state` after consecutive size notifications or a manual quality pick right after quality probing; nested events are queued, and error and recovery-failure notifications keep an async boundary.

- The headers pool warm-up fixture now mounts a real picture and waits for the exact first frame / media metadata or an error, keeps the accepted and decode results and the native read-back, and fetches the HTTP receipts only after both the positive and negative controls complete.

- Added the missing SRT asset declaration to the example; all four subtitle format fixtures use in-package assets. A rebuilt APK must be re-verified.

- Fixed the source request headers being lost in the media_kit load hook while playing media, and clear the previous source's headers after a source switch.
- Fixed feed page-flip activation finalization resuming playback and overriding a host controller pause.
- Corrected the matrix evidence gate: unrelated command errors no longer pollute every row, but an error in the integrity of the whole run still blocks a pass; the first failure of an old BLOCKED row is distinguished from a PASS fallback.
- Corrected the playback-rate same-value dedup and the actual player-pool count criteria.
- Fixed fixtures for CP3 subtitle assets, feed pool count, bottom bar live/DVR mounting prerequisites and silent-stream pause policy, STT start prerequisites and event-related field receipts; a new APK must be re-verified.

- Clarified the CP2 acceptance contract (no product behavior change): a pod waiting-type ad requires a cutover and a renderEpoch increment; nowait opens directly on the current player. Ad slot timing is based on effective wall-clock time after the first frame and freezes on playing edges; the last media position cannot stand in for the remaining duration. See the [offline triage](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/plans/2026-11-05-cp2-r4-offline-triage.md) for the rationale and fixture fixes.
- Fixed a waiting-type mid-roll discarding the still-playing content progress during warm-up, which made the content repeat the warm-up wait period after the ad; the MP4/HLS resume point now follows the content until the cutover.
- Fixed a stale proxy snapshot on an immediate insert right after `setRate` completed, which lost the user's rate after the ad; it is still 1x during the ad.
- When a feed open fails, the current page and the retry entry are kept; an explicit host pause during a built-in guard pause cancels the automatic resume, and a later play is still handled by the visibility policy.
- For VOD, automatic retries before the first frame and same-content alternative addresses keep `source.start`; after a picture appeared the failure resume point is still used.
- With `fullscreenRoute` on, the inline side yields its subtree while the route is mounted, avoiding duplicate GlobalKey mounting of the host surface/poster; the default (off) path is unchanged.

The following are behavior and migration notes after 0.4.0 (released with 0.4.1). They are merged by feature and keep the final contract; per-commit test numbers are in the unified orchestration master plan and CLAUDE.md and are not accumulated here.

### Breaking / Deprecated migration summary

- `state.error` holds terminal errors only; for full diagnostics listen to `MovaErrorEvent.fatal/code`, and look at `MovaPlayFailure` for recovery decisions.
- `MovaAds.load/loadDeferred` return `Future<bool>`; callers that only `await` are unchanged, overriders must update the signature; completion microtask timing is unchanged, and `Future<bool>` can be used where `Future<void>` was.
  `IMovaApi.open` already became `Future<bool>` in 0.3.1, so custom APIs must be updated too; `false` means rejected/stale/disposed and must not be treated as a playback failure.
- (Superseded by the 0.5.0 section: these aliases and the old-name typedefs have since been deleted.) Old-name typedefs plus `MovaMiniHost.ctl` and `MovaAdOverlayComponent.controller` are kept as `@Deprecated` aliases; verbs and named parameters without an alias must be migrated with the rename table below.
- Deprecations announced for the next release (no member-level annotations in this one): the old UI verbs/mirrors move to MovaChrome, the old style fields move to MovaPlayerStyle, `MovaAbrOpts.policy` moves to `policyFactory`. The STT re-export from the main entry is kept for one version only, so change imports to `stt.dart`; export-level internal helpers will be hidden next release, and `IMovaApi.stt` stays.

### Sessions, ads and cutover

- Added the `movaCapabilityOf<T>(api)` capability lookup. It prefers the proxy's own capability, otherwise looks through multiple cutover layers for the currently effective player, and does not modify `IMovaApi`.

- When the host grabs the source and the session yields, one `MovaNodeEnd(superseded)` is re-emitted for the node that had already started, keeping its original epoch, without reporting a node failure and without abandoning the host's new shadow.

- When a session reloads, calls `jumpTo`/`setItems` or is disposed, it cancels the warm-up credentials it holds; even a claimed transaction waiting for the old player to pause releases the shadow and forbids the cutover. The host's own new shadow is not affected.

- When a shadow cutover re-emits lifecycle events and a host callback grabs the source, the old re-emission stops immediately, the credential commit returns superseded and the session yields; the old player is still released normally.

- The session landing window caches terminal failures by media ownership; even if `open` returns normally after a recovery giveUp, ad failure or content `contentError`, `MovaNodeFail` are still settled and the session returns to idle.

- The NextUp of `MovaPlaylist(ads:)` is shown only on content session nodes and the old card is hidden immediately when entering/leaving ads and during transitions; the old direct playlist keeps its original criterion. The ad overlay reads the canSkip/skipIn of the ads orchestrator (`MovaAds`) directly, so stale progress in the pod landing window cannot show the skip button early; the countdown is rounded up at microsecond precision.

- Added `MovaAdOpts.midRollSnapback`: when one progress tick crosses several distinct mid-roll points, it can replay all of them (default `all`), replay only the full pod of the last insertion point (`last`), or skip all and mark them as played (`none`); a single due insertion point and pods at the same point play as normal.

- The cutover proxy keeps the old player's playback observation during the cutover window and suppresses internal pause events; after the cutover it re-emits shadow-period SourceChange, Ready and FirstFrame in order, and on abandon restores the real state. `MovaCutoverChange` gained an optional `reason`. Proxy state and events are delivered through the same queue carrying the render epoch, so the state at receive time matches the payload, fixing the buffering state lag of H77.

- Every waiting-type ad in an ad pod now goes through prepare + credential commit with a unified ad-direction plan (default 1x, stop at first frame once ready, adReadyTimeout); when superseded by a new host open the session yields, and when a slot is replaced it only falls back as not-ready. The landing window discards the old media's end, error and progress, and content warm-up accounts for both the ad slot and the remaining asset time. The public `cutoverTo` is kept.

- A session settles a failure of the same epoch, node and attempt only once: ads are still handled by the ad failure policy, and with recovery on, non-terminal diagnostics go to the player; a terminal content error (waiting for giveUp when recovery is on) emits `MovaNodeFail(failItem)`, `contentError`, and returns to idle without auto-advancing. `contentError` covers resolve failures, content open/switch exceptions and terminal failures.
  Fix: exceptions from an ad's `cutoverTo`, prepare and commit and direct ad open exceptions all enter the ad failure policy; a direct ad open rejected by the host is skipped without retry. Content open/switch exceptions are reported through `MovaAds.contentError` and return to idle; host rejection and stale loads do not report errors and no contentEnded is sent.

- Session auto-advance validates the epoch when consuming the end notification, so a manual episode change is not overridden by an old notification; replacing the list invalidates in-flight jumps, and the ad-shared list index and indexChanges follow session navigation. When a pre-roll still loading is skipped, the load result waits for the resume request of the same epoch to settle.

- `MovaPlaylist(api, ads:)` shares a session, episode changes carry per-episode ads and auto-advance waits for all post-rolls; this path obeys `playlist.enabled`, and the old direct constructor keeps its behavior.

- Added `MovaSession` with multiple items, per-episode ads and load outcomes; direct construction auto-detects the enabled cutover capability; `MovaPlaylistItem.adBreaks` can override the schedule and `MovaAds.session` offers shared access.

- Fixed internal pauses superseded by a successor switch polluting play intent; waiting-type ads pass an explicit start intent through an in-package capability. After an ad's first open fails in a hook, the retry keeps this load's intent and yields to later user play or pause commands.

- Cutover and ad resume inherit the user's play intent, so skipping an ad after a pause does not start playback automatically; custom movaFactory players must maintain playbackIntent, and if the intent is always false the player stays paused after the cutover.

- Ad slots and mid-roll countdowns use a pausable clock: time during an observed pause is not charged to the ad duration; `delayRemaining` is computed on the same clock, while the first-frame load deadline still uses an independent wall clock.

- The ad failure policy and shadow warm-up abandonment react only to `MovaErrorEvent.fatal == true`; non-terminal kernel logs no longer interrupt ads or warm-up, and the existing attempt dedup and cutover acceptance contract are unchanged.

- Fix: after the player is ready it probes HLS variants by itself by default (`MovaAbrOpts.probeVariants: true`). Automatic and explicit probes in the same session share one request, a late result updates the list but does not override a manually chosen variant; automatic probing can be turned off so the host calls it explicitly. Auto ABR takeover is still not enabled.

- Fix: later ad failures within an ad pod keep advancing. Resume and failure are deduped per attempt, so a Timer and the asset ending do not advance twice; cutover distinguishes host rejection through an in-package optional capability, a rejected shadow is released immediately, a rejected ad is skipped without entering retry, and the old content picture is no longer taken as the ad's first frame.

- Fix: the cutover commit transaction owns the cutover exclusively. Concurrent commits re-validate the slot after queuing, `cutoverTo` commits only the slot it warmed itself; a failure to hold the target frame does not block commit and release, and a slot cleanup exception still guarantees the effective player is released and streams are closed.

- Fix: returning to content uses a separate transition phase, so old ad progress, end events and immediate inserts no longer wrongly trigger content scheduling or rewrite the resume position.

- Fix: cutover isolates source switches, reloads and concurrent cutovers with an internal operation generation; commit releases only the claimed warm slot, keeping the resources and phase of a newer prepare, and a stale cutover no longer falls back to grab the source.

- Fix: live shadow warm-up no longer requires catching up with the content position (the longer the content played, the more likely it degraded into a non-seamless cutover). A live shadow starts from the live edge and never seeks, so its position starts at 0, while `MovaBufferWarm` required shadow position >= target position - tolerance, making readiness time about startup latency + content position already played; the variant where content played 7s first gave up warm-up 10/10 at the 8s `readyTimeout` (measured on real device STG-AL00). Now `MovaWarmSignal` gained `live` (default false, custom criteria unaffected) and `MovaBufferWarm` treats live as reached, still requiring no stall + lookahead buffer >= `lookahead` + `stableTicks` consecutive checks; VOD and signals without `live` behave as before. On device: content played first for 500ms/3s/7s/15s/30s all pass (B/C 5-10 runs each), shadow ready time stays at about 3-4s and no longer grows with the content position, and `readyTimeout` is still 8s; see [q13-live-warm-fix-verification](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/plans/2026-10-29-q13-live-warm-fix-verification.md).

- Fix: after `dispose()` verbs are no longer forwarded to a disposed kernel. Previously `pause`/`setVolume`/`setRate`/`switchQuality` etc. still called the kernel after dispose, and the real media_kit throws `AssertionError('has been disposed')` (the uncaught `[Player] has been disposed` exception in device re-test logs may share this cause). Now all public verbs of `Mova`/`MovaCutover` silently return once disposed (no throw, no event, no kernel or port access), async verbs re-check after awaiting, and `prepare`/`cutoverTo` of a disposed `MovaCutover` no longer create a new shadow player.

- Docs/verification page: fixed the resume-window anchor of the HE V6 verification script (the old form always matched the first frame of the session and once misjudged "V6 resume failed" as a library defect); Android device V6 re-test passed 5/5 with resume error 0-40ms. Coverage test results are in `doc/plans/2026-10-27-device-coverage-results.md`.

### Views, styles and host components

- `MovaPlayer` gained `fullscreenRoute` (default false): when on, the app root route shows fullscreen, the back key leaves fullscreen first, and when locked it uses `MovaStrs.unlock` to prompt unlocking. The route borrows the same API, builds its own independent chrome, does not re-probe quality, and returning shows the inline controls; styles inherit `MovaPlayerStyle` and the old config fallback, while orientation restore and PiP/mini are still managed by the player. The fullscreen route carries the background guard ownership so its own occlusion does not trigger a pause; custom surfaces of both the inline and route sides on Windows also go through MovaSnapshotGuard. When off, the original player tree and behavior are kept.

- `MovaView` rebuilds only when a config section actually consumed by the player changes; changes of theme, strings, gesture, controls and danmaku sections go through view updates, keeping the player, open count and playback state. The latest options are passed down as a compatibility fallback, and inline string closures and danmaku lists no longer trigger a rebuild.
  `MovaView` compares the constructed config through `MovaOpts.movaSectionsEqual`, ignoring host changes in the ads/playlist/mini sections; the UI style section goes through view updates since C06; in debug, if the actual config differs for 10 consecutive frames, it warns once per view.

- Added `MovaIcons` and `MovaPlayerStyle.icons/iconsOf`, allowing the 20 control-UI icons (excluding feed social buttons) to be replaced per view or per theme extension; accessibility labels continue to be provided explicitly by the strings. `MovaTheme.progressColor` configures the progress highlight and thumb color; the default null follows the host SliderTheme, and default icons are unchanged.
  The quality auto/unknown compatibility labels are promoted to kMovaAutoQualityLabel/kMovaUnknownQualityLabel, keeping the old values, and it is announced that the next version changes them to neutral values.
  Added `MovaPlayerStyle` (ThemeExtension) and `MovaDanmakuStyle`; `MovaPlayer`/`MovaView` support `style`. Theme, strings, gesture, controls behavior and danmaku style are looked up per section in order: view parameter > theme extension > old options > default. Switching theme updates the cached UI kit and controls config without rebuilding the player; the danmaku switch and items still come from options.
  Button accessibility names, tooltips and the quality "auto/unknown" display now read from `MovaStrs`, with new replaceable action strings and a labelWithValue format function; built-in buttons pass labels explicitly and default strings are unchanged. The old Chinese labels of `MovaQuality` are kept in this version and the next version plans to change them to neutral values.

- Deprecated (announcement, annotations next version): `MovaOpts.theme/strings/gesture/controls` and the danmaku style fields are planned to be deprecated in favor of `MovaPlayerStyle`; the old fields continue to act as fallbacks in this version and no member-level `@Deprecated` is added.

- Deprecated (announcement, annotations next version): `IMovaApi.showControls/hideControls/showHud/setDragging/uiState/uiStates` are planned to be deprecated next version in favor of `MovaChrome`; the old verbs broadcast to all mounted views and the old mirror takes the last changed view. Lock, zoom, fit and other `MovaState` remain shared by the player.

- Rename wrap-up: `MovaMiniHost.mini` replaces the old `ctl` parameter/field and `MovaAdOverlayComponent.ads` replaces the old `controller` field; the old entries are kept as `@Deprecated` aliases and construction and rendering behavior are unchanged. (The aliases were deleted in the 0.5.0 section.) In-package calls and examples migrated to the new names. Verified that factories already share `MovaFactory` and existing type aliases are all marked deprecated; fixed the outdated doc statement that "enum values cannot be accessed through a typedef".

- Fixed nested `MovaAutoPause` of different APIs shadowing the outer guard; `MovaPlayer` looks up the full ancestor chain by API and honors the outer config's background continue-playing.

- The video background pause of `MovaPlayer` now goes through the player, so hooks, play intent and the ad clock can observe it, and imperative keepAlive is also ended by the player; by default going to background still pauses and returning to foreground does not auto-resume. audioOnly without a render surface is unaffected; for background playback wrap the player with `MovaAutoPause(opts: MovaAutoPauseOpts(background: false))` on the same API.

- Fix: `probeVariants: false` turns off all automatic probing of the player and the default `MovaPlayer` / `MovaView`. The UI automatic entry requires both `autoLoadQualities && api.options.abr.probeVariants`; `autoLoadQualities: false` turns off only that UI entry, and an explicit `api.loadQualities()` is unaffected by either.

- Feat/Fix: buttons are focusable by default with semantics, tooltip and focus indication; mouse hover shows the controls. `MovaCtrlsOpts.shortcuts` defaults to false; when enabled, a focused player supports Space for play/pause, Left/Right to jump ten seconds, Up/Down for volume, F/Esc for fullscreen; lock, PiP/mini and text input do not handle player shortcuts.

- Perf: the position label updates per second, `MovaPlayer` caches static components and built subtrees; duplicate scalar state mirrors no longer emit events, and dispose cancels the HUD and controls timers before the first await.

- Fix: vertical swipe sensitivity takes effect, patch path errors assert in debug; the lock button enters the component tree and follows controls show/hide (the unlock entry is kept while locked), and option popups can scroll.

- Fix: the auto-pause guard exempts fullscreen; system PiP state broadcasts flow back only to the player that initiated entering, and the receiving eligibility is revoked after a failure.

- Breaking (naming): dropped the `*Controller` suffix, renamed standby to keepAlive and swap to cutover (pure renames, behavior unchanged).
  * Classes: `MovaAdController` -> `MovaAds`, `MovaFeedController` -> `MovaFeed`, `MovaPlaylistController` -> `MovaPlaylist`, `MovaMiniController` -> `MovaMini`, `MovaSwapController` -> `IMovaCutover`, `MovaStandbyController` -> `IMovaKeepAlive`.
  * `Swap*` -> `Cutover*` (`MovaSwapEngine`/`Config`/`Change`/`Phase` etc.), `Standby*` -> `KeepAlive*` (`MovaStandbyConfig`/`Phase`/`Mode`/`Reason`/`Change`/`Resume`, `MovaSilentStandby` etc.).
  * Members: `MovaState.standby` -> `keepAlivePhase` (type `MovaKeepAlivePhase`), `MovaOpts.standby` -> `keepAlive`, `MovaOpts.swap` -> `cutover`, `MovaHiddenMode.standby` -> `keepAlive`, `setStandby` -> `setKeepAlive`, `swapTo` -> `cutoverTo`, `MovaAdController(swap:)` -> `MovaAds(cutover:)`.
  * Files/directories: `core/standby/` -> `core/keep_alive/`, `core/swap/` -> `core/cutover/`, `ad_controller.dart` -> `ads.dart` etc. (only affects code importing `package:mova/src/...` directly; imports through `package:mova/mova.dart` are unaffected).
  * Compatibility layer: old class names are kept as `@Deprecated` typedefs for one version (`lib/src/deprecated_names.dart`), and `MovaState.standby`, `MovaOpts.standby`/`swap`, `MovaHiddenMode.standby` also keep `@Deprecated` aliases. (All of these aliases were removed in the 0.5.0 section.) Without aliases: renamed methods/named parameters (`setStandby`, `swapTo`, `MovaOpts(swap:/standby:)`, `copyWith(swap:/standby:)`, `MovaAdController(swap:)`) - these must be migrated using the mapping above.
  * The key `swapEnabled` in the report payload (QoE session field) is kept as is and not renamed. (Changed in the 0.5.0 section: the key is now `cutoverEnabled`.)

- Fix: the in-app mini window was not collapsed after entering system PiP (device coverage re-run A15/F5). `enterPip()` sets `MovaState.mini` back to false, but `MovaMini` did not know and the mini window stayed on screen. Now `MovaMini` listens to the borrowed api's state and removes the mini window when the api leaves the mini state by itself.

### Preview, feed and resource ownership

- Added the sub-entries ui_kit.dart, ads.dart, feed.dart, mini.dart, extend.dart and a separate stt.dart; mova.dart still exports all original symbols in this version. The STT re-export from the main entry is kept for one version only and `IMovaApi.stt` stays; model download is still an experimental implementation. Internal helpers are announced to be hidden at export level next version, no member-level `@Deprecated` is added in this version, and runtime behavior is unchanged.

- `MovaFeedPlayer` gained the host-owned `MovaFeedPlayerCtrl`, which can query the feed/current index/current player, jump pages and play/pause, and unbinds when the controller is replaced or on unmount; the players are still released by the widget. The whole-feed MovaAutoPause is built in, with configurable autoPause (null disables the guard) and routeObservers, and page-flip exclusivity is still handled by the pool.
  A per-page feed loader throw, open rejection/throw and terminal errors during playback are now a visible failure UI, using the theme's error/retry strings by default and customizable through errorBuilder; a failure does not retry endlessly on ordinary rebuilds and an explicit retry affects only that page. A load failure of the current page stops the previous page's sound while other pages can still be browsed; the end placeholder when the loader returns null is unchanged.

- `MovaSource` gained headers/userAgent/start: playback options, quality probing, VTT/sprite sheets, frame extraction and feed prefetch share the source request headers with an explicit UA taking precedence; the VOD start position is delivered through the existing seek register chain and ignored for live. The signatures of `IMovaApi.open` and `IMovaHttpFetch.get(Uri)` are unchanged; the new optional capability `IMovaHeaderedHttpFetch` lets old fetchers degrade to no headers with a debug hint once per instance; frame extraction is likewise compatible with old ports through the optional `IMovaHeaderedFramePuller`.

- Preview resource gating passes the request generation and a cancel signal and re-checks after the async network probe returns and before HTTP/frame extraction starts; cancel, source switch and dispose invalidate old calls, dispose does not wait for the probe, and the wrapper still does not dispose host ports.
  A preview network policy rejection is passed through VTT and the service layer by a dedicated signal; it no longer counts toward the VTT fetch-failure cooldown nor continues into ordinary failure fallback, and switching back to Wi-Fi can retry immediately.
  Tightened the on-demand boundary of C12: custom preview sources may only read memory, so without an explicitly injected probe the default connectivity is no longer queried from the remote media address; built-in sources still query only at actual remote resource requests, and custom sources with an explicitly injected probe keep entry gating; never/always policies are unchanged.
  Reversed the earlier decision not to wire a network probe by default: `createMova` creates a connectivity probe on demand for wifiOnly preview; it queries only when actually requesting a remote VTT, sprite sheet or frame extraction, and does not query for caches, VTT cooldown, disabled sources and local resources. The test seam still does not wire platform plugins.

- After the last view unbinds, the not-yet-expired HUD/controls timer responsibility is handed back to the player or the old mirror, keeping the remaining deadline and always-visible state and cleaning up drag and preview; this applies to normal players and the cutover proxy. The HUD registers its timer before synchronously notifying listeners, so reentrancy and a subsequent dispose no longer leave a stale timer.

- The built-in preview service builds an independent session per view, sharing the cache and serialized source resolution, and each view receives only its own results and cancels only its own requests. Custom previews can implement IMovaPreviewSessions for the same isolation. When the bottom bar or horizontal-swipe drag is unmounted because of locking, it releases its own drag state, clears the preview and resumes auto-hide.

- While dragging the progress bar or horizontal-swipe seeking, the view's controls and preview stay visible and the auto-hide timer restarts after release; pressing the controls, and pointer/keyboard/semantic activation of buttons renew it and the always-visible state is kept. Applies to views that support the bridge or are given an explicit chrome; non-bridge old paths keep their behavior.

- Every `MovaPlayer` view that supports the bridge owns its own MovaChrome (which the host may pass in), so controls, HUD, drag and preview do not interfere with each other; cutover cutovers and shadow Ready replay keep the view interaction state and timing. With no views the old behavior is unchanged; a custom IMovaApi keeps the old interface by default and can pass chrome explicitly to enable independent interaction state. When a view exists, ready show/hide is handled by the view, and the old reader of a normal player sees the mirror one microtask after MovaReady.

- The testing entry gained `MovaTestKernel.scripted` and `MovaTestStep`: scriptable ready, buffering, progress, failure and end; ready automatically composes the first-frame signal, and a source switch or dispose cancels old steps. The normal constructor stays passive by default and does not auto-play or emit signals.

- Injected kernels, preview cache/probe/source/frame extractor, HTTP and STT recognizers are disposed by the host; self-created resources are still released with the player. Use `ownsKernel: true` to hand over a kernel; kernels created by the default factory are automatically owned by the player. An STT start failure only rolls back and no longer throws into the playback chain. Added `MovaAbrOpts.policyFactory`, which creates an independent policy per player and takes precedence over the old `policy`; the old instance field is to be deprecated next version and only announced in this one.

- `MovaMini.show` obeys mini.enabled consistently with showInPage; a disabled cutover warm-up and an STT start without a recognizer warn once per instance in debug, and `cutoverEnabled` and `options.stt.hasRecognizer` can be read respectively.

- Fix: quality probing is deduped by session and effective source address index. After a failover the new master can be probed explicitly, and a late result from an old address is still discarded; quality switches and retries at the same address keep sharing the request. On player dispose the self-created fetcher is closed and in-flight probes are cancelled even when VTT is disabled or a custom preview source is used; a host-injected fetcher (including the default VTT borrowing) is closed by the host.

- Fix: an ad episode change cancels old timers and shadows synchronously, so a post-roll no longer warms an already ended content; async ad operations discard late results by load generation, preventing an old ad from resuming timing, rate or STT.

### Errors, recovery, loading and platform

- The delayed ready of the scripted test kernel uses the latest play intent, keeping the last decision of pause/play before ready; the normal passive kernel still only records commands and does not signal automatically.

- `createMova` warns in debug about default kernel parameters ignored when a kernel is injected; on Android with the default kernel and tlsVerify on, it asserts that a non-empty tlsCaFile must be provided. The frame extractor still defaults to null and the docs state it must be injected explicitly.

- README app examples consistently use createMova, the first example awaits and catches open failures; a bare Mova with default platform ports warns once in debug.

- Restored the terminal state for main-file open failure when there is no END_FILE event pump: it confirms at error arrival that the pump is unavailable and enables the fallback only if the stream/cplayer/ffmpeg error text contains the current main file address; external subtitle, external audio track and HLS segment errors stay diagnostics, and when the pump is available END_FILE still decides.

- Fixed END_FILE ownership and termination handling: before each actual load the old weak-client queue is drained synchronously, and end notifications carry an attempt number; termination goes through a single entry, one fatal per attempt, with duplicate logs kept as diagnostics. A keepAlive failure silently degrades and reopens on wake, and notifications during open are handled after it returns.

- `state.error` now means only errors that terminate playback. Non-terminal kernel logs no longer write this field nor show the default error overlay; `MovaErrorEvent(fatal: false)` and `MovaHook.onError` still notify as usual. Hosts that need to diagnose all errors should listen to `MovaErrorEvent` in `api.events` and decide by `fatal` whether to show a failure; hosts that need to track recovery decisions listen to `MovaPlayFailure`. END_FILE(error), recovery give-up, known terminal text and open throws are still written to state; without a pump the open-error fallback containing the main file address is restored and reuses the recovery or termination decision.

- The error overlay uses the `MovaStrs.playbackError` / `retry` strings (defaults are Chinese: "playback failed, please retry" / "retry"); the raw error is shown only in debug mode.

- Added the experimental `MovaAbrOpts.manageAuto` (default false): when explicitly enabled, on an auto stall mova drops to the second-highest variant of the list and then continues with the specific-variant downshift logic; it obeys the ABR master switch and the seek/switch lease. CP0 device measurement (STG-AL00, default config, throttled fixture, 90 second window): mpv's auto variant stayed at the highest variant without downshifting and rebuffered repeatedly under throttling; with this switch on, mova's ABR takes over the downshift. Still experimental and off by default.

- Failure detection no longer depends on recovery: the first open lazily starts the END_FILE weak client; a terminal error clears buffering and pauses, and enables RESTART when a poster exists. alternatives requires recovery enabled (debug assert).

- With recovery off, an open failure still throws and also writes a terminal state.error; it is announced that the next version no longer throws, so migrate to error-event handling.

- Added: playback error event grading. `MovaErrorEvent.classified` carries `fatal/code`, and the old constructor signature and default semantics are kept. mpv keeps the subsystem from logs through an optional error capability, the player subscribes to this entry first and old kernels can still use the error stream. Logs are non-terminal by default; `Failed to initialize a decoder`, `Failed to recognize file format.` and recovery give-up are terminal, and code and the QoE mapping are consistent. Only terminal errors are written to `state.error`; END_FILE is wired and the QoE settlement criterion is unchanged.

- Fix: the ABR lease of live quality switches and time-shift seeks is released after this buffering true -> false. The leading false from the internal stop in open is ignored so the load itself is not counted as a stall; without a buffering signal it is still released after 10 seconds, and VOD resume validation and source switch/dispose cleanup are unchanged.
  Fix: ABR masking is now a lease carrying the load attempt number. A late finish of an old switch cannot release the masking of a new switch or seek; buffering caused by a user seek is not counted as an ABR stall, and the 10 second fallback cap is unchanged.

- Fix: a new user seek clears the superseded old registered/pending-settlement target; when duration is known but the first variant has not landed and another switch happens, the latest seek (including 0 seconds) is used, and after the target echo settles it does not fall back to the old load spec. When duration is unknown it is still registered and re-sent after ready.

- Fix: keepAlive wake and back-to-edge reopen replays obey the current keepAlive phase; entering keepAlive again immediately invalidates an in-flight wake and sends no old resume event. With recovery off, a background wake reopen failure is reported through state.error, MovaErrorEvent and hook.onError and ends the recovery measurement, no longer falsely reporting recovery success after a timeout.

- Fix: internal retries replay the effective load spec, keeping the manually chosen quality; time-shift retries rebuild the address from the original fixed lag and the current time, a failover clears time-shift and the old variant list. Back-to-edge keeps the current variant and duration and starts playing by the latest play intent after reopening. Consecutive switches inherit the not-yet-landed resume target, and a user seek during the wait for the first frame of recovery supersedes the old failure point.

- Fix: keepAlive wake measurement uses an independent first-frame gate; a source switch, quality switch or recovery reload ends the old measurement as reloaded without sending MovaKeepAliveResume, and an old resume timeout no longer interferes with the new source's first frame.

- Fix/timing change: the back-to-edge and reopen of a keepAlive wake no longer occupy the keepAlive queue; `setKeepAlive(false)` completes on entering resuming and does not wait for the network reopen or the first frame. After the network returns, only the current attempt starts playing by the latest play intent, and a pause in the meantime is not overridden.

- Fix: an open rejected by the host no longer invalidates an in-flight play/seek; a play intent during a paused load is re-sent after the load completes, while a keepAlive request still keeps the paused load.

- Fix: a successful software-decoding fallback after hardware decoding failure no longer falsely reports a playback error. mpv's `Could not open codec.` attempt log is filtered precisely, keeping the terminal errors of decoder exhaustion and format recognition failure, so real failures can still be reported when recovery is off by default.

- Fix: a negative `seek`/`seekBy` with unknown duration no longer leaks the lower bound. When duration had not arrived, `seek(-5s)` was registered as is, progress reported a negative number first, and after duration arrived -5s was also sent to the kernel (the known-duration path used to clamp to 0). Now the entry clamps the lower bound to 0 first and clamps again by the duration upper bound when re-sent.

- Fix: the progress bar froze forever after a user-initiated `seek` was dropped by mpv (H17). Previously only the resume seek after a quality switch had the verify + re-send chain; after an ordinary seek was dropped `_pendingSeekTarget` stayed armed and all later real positions were swallowed as stale echoes until the next seek. Now VOD seek reuses the same verify/re-send chain (at most 3 times); after giving up it releases echo suppression and progress follows the real position again; if a new seek arrives during re-sending the old chain is invalidated, the rule that live does not seek is unchanged, and it also holds while paused.

- Fix: the resume position was lost after a quality switch (`switchQuality`/ABR downshift). During consecutive manual HLS variant switches the resume seek was sent the moment the new variant reported its duration, when mpv had not yet finished playback initialization, so the seek was silently dropped and playback restarted from the beginning (only 1 of 5 local HLS switches on an Android device resumed). Now the registered resume seek waits for the new variant to land (first frame / native RESTART) before being re-sent; if it has not landed within 4s it is re-sent as before, and if landing precedes duration it waits for duration. On Android device (STG-AL00) 15/15 landings across normal/cutover proxy/paused states, 5 each, had 0ms error.

- Fix: `setRate` entry clamping. The rate is clamped to 0.25-4.0 (`kMovaMinRate`/`kMovaMaxRate`, NaN treated as 1.0), and the kernel, state and `MovaRateChange` see the same value (previously 0/negative/NaN went straight to the kernel and state and event copied it).

- Fix: an exception thrown by the host report callback no longer interrupts the player. Exceptions thrown by `IMovaReporter.onReport` (both call sites, `IMovaApi.report` and the QoE collector) are isolated and only notify each hook's `MovaHook.onError`, leaving playback state and later reports unaffected (previously the exception propagated into the event subscription callback and became an uncaught async error).

- Fix: out-of-range `setVolume`/`setBrightness` values. The entry clamps to 0-100 / 0-1 first, so state, events and ports see the same value (previously state stored the out-of-range value, the system volume was clamped by the port and brightness was rejected by the platform plugin with `RangeError` and swallowed, so the HUD and the actual device disagreed).

- Fix: repeated `dispose()` threw an exception (A23). `dispose()` of `Mova`/`MovaCutover` is now idempotent and the second call returns immediately.

- Fix: low `setZoom` values collapsed the picture (A12). Values below 1.0 or NaN are treated as 1.0; there is still no upper limit (`maxZoom` only constrains the pinch gesture).

## 0.4.0

* **New: unified timeout config `MovaTimeouts`** (`MovaRecoveryOpts.timeouts`, exported through `package:mova/mova.dart`). Fields `network` (-> mpv `network-timeout`, whole seconds), `whepHandshake`/`whepFirstFrame`/`whepMedia` (-> `handshake_timeout`/`first_frame_timeout`/`media_timeout`, microseconds, `whep...` addresses only), delivered to mpv through the existing source-option mechanism before each open; all default to `null` (mpv defaults untouched); explicit settings of `MovaSource.mpvOptions`/`demuxerOptions`/`whepMediaTimeout` take precedence. `MovaSource.mpvOptionsFor` gained the optional parameter `timeouts`; new public constants such as `kMovaWatchdogMargin` (5s).
* **Behavior change: the Dart watchdog is demoted to a fallback and its deadline is derived from the mpv window** (visible only when `recovery.enabled`). Reconnection is driven mainly by mpv's `END_FILE(error)`/error events; the defaults of `startTimeout`/`stallTimeout` change from a fixed 10s to `null` (derived = longest mpv window + 5s): without `timeouts` configured, non-WHEP start/stall are both 65s, WHEP start is 85s and stall 10s; explicit settings still use the user's value. **Without configuration, failure detection for a black-hole host is much slower than before (10s)**, so setting `timeouts.network` as well is recommended.
* **Behavior change (API):** the type of `MovaRecoveryOpts.startTimeout`/`stallTimeout` becomes `Duration?`; the old `stallTimeout: null` (turn off the stall watchdog) is replaced by the new field `stallWatchdog: false`, and `null` now means "derive"; `copyWith(clearStallTimeout: true)` now means "reset to derived". Added `startTimeoutFor(uri)`/`stallTimeoutFor(uri)`.
* **Behavior change: the default of `MovaLiveReconnect.maxDelay` changes from 30s to 15s** (backoff sequence 1, 2, 4, 8, 15, 15...).
* **Docs:** the README recovery section gained "reconnect responsibilities" (live does not enable `reconnect_streamed`, VOD keeps mpv's default reconnect, mpv main path / Dart fallback) and `MovaTimeouts` usage.

## 0.3.2

* **Fix: two issues from device re-testing of the recovery layer.**
  * Deterministic failures such as 404 still waited the full `startTimeout` before retrying under the default config: the native `END_FILE` subscription was opened only with a reporter or `preciseFirstFrame: true`, and `recovery.enabled` did not open it. Now `createMova` subscribes `END_FILE` automatically when `recovery.enabled`; `MovaMpvKernel` gained `observeRestarts` (default `true`), so recovery opens only END_FILE and does not forward `PLAYBACK_RESTART`, keeping the first-frame criterion the same as without recovery (when RESTART is not forwarded `nativeRestartAvailable` is `false` and the first-frame gate does not wait the grace period for nothing). `movaObserveFlags` gained the `recovery` parameter and the `restart` field.
  * `whepMediaTimeout`/`demuxerOptions` overwrote `demuxer-lavf-o` as a whole and restoring then failed: the whole string was set, wiping media_kit defaults such as `seg_max_retry`/`allowed_extensions`/`protocol_whitelist`; on restore the read-back string was written back as is, but the value of `protocol_whitelist` contains commas and could not be parsed again, so mpv reported `Expected '=' and a value.`, the error went to `state.error` and `MovaErrorEvent`, and later VOD sources still carried `media_timeout`. Now `change-list add` merges only this source's keys, restore uses `remove` for those keys and `append` to bring back original values displaced by same-named keys, and no longer reads back the whole string; entries that fail to write or have invalid syntax are skipped as a whole. `MovaMpvKernel` uses this path for key-value list options such as `demuxer-lavf-o`/`stream-lavf-o`, while other `mpvOptions` are still written as whole values and restored to the value read.

* **Fix: six issues in the recovery layer (`MovaOpts.recovery`)** (from Android device runs pulling WebRTC/WHEP live streams with the publisher going offline and recovering):
  * `state.error` was not cleared after recovery succeeded: `MovaRecovered` now clears the kernel error left during the failure (previously only `open()` cleared it, so a normal picture still carried the old "Failed to recognize file format").
  * `state.buffering` stayed true after give-up: `giveUp` resets `buffering` to false and emits one `MovaBufferChange(false)` (not repeated if it was not buffering), so the spinner no longer hangs forever.
  * A failed retry waited the full `startTimeout` before the next one: the root cause was that `END_FILE(error)` (e.g. 404) arriving while a load was in flight (`_kernelOpening`) was simply dropped and only the 10s start timeout covered it. Now it is recorded and handled by the policy right after `open()` returns; a session superseded by a newer `open()` is discarded.
  * Live only retried once by default: added `MovaLiveReconnect` (exponential backoff, default starting at 1s, x2, capped at 30s, never gives up, `maxAttempts` can set a limit; with multiple addresses earlier addresses retry `retriesPerAddress` times before switching and the last one reconnects continuously) and `MovaDefaultRecovery` (VOD `MovaRetryThenFailover`, live `MovaLiveReconnect`), effective when `MovaRecoveryOpts.policy` is `null`; added the switch `MovaRecoveryOpts.liveReconnect` (default `true`; `false` brings live back to the old retry-once); `MovaPlayFail` gained `isLive`. **Behavior change**: a live source no longer gives up after the second failure when recovery is on and no custom `policy` is passed; VOD default behavior is unchanged. The default type of `MovaRecoveryOpts.effectivePolicy` changed from `MovaRetryThenFailover` to `MovaDefaultRecovery`.
  * The public API could not pass source-level libmpv/ffmpeg options: `MovaSource` gained `mpvOptions` (arbitrary mpv options), `demuxerOptions` (composes `demuxer-lavf-o`), `whepMediaTimeout` (WHEP `media_timeout`, converted to microseconds automatically, effective only for `whep...` addresses) and `mpvOptionsFor(address)`; `MovaSource.pick`/`sameAs` support them too. On the kernel side the new optional capability `IMovaSourceOptionsKernel` (implemented by `MovaMpvKernel` and `MovaTestKernel`): the player stages the address's options before each kernel `open`, the kernel applies them before open and the next open first restores the original values, so nothing leaks to the next source. `MovaTestKernel.stagedSourceOptions` lets host tests assert.
  * Live `MovaDurationChange` was too frequent: added `MovaLiveOpts.durationStep` (default 2s); live duration changes smaller than a step are not reported (both state and event skip; the first non-zero value, a fall back to 0 and the first value after re-open/reload always pass), `Duration.zero` turns throttling off; VOD is unchanged.
  * Added 48 regression tests (`recovery_fixes_test`/`live_reconnect_test`/`duration_throttle_test`/`source_options_test`/`mova_source_options_test`/`mpv_kernel_source_options_test` etc.); the full suite of 1472 passes.

## 0.3.1

* **Breaking (public signature): `IMovaApi.open()` changes from `Future<void>` to `Future<bool>`**; `true` means the source was accepted as the current source; it is `false` when a `beforeOpen` hook rejects, when superseded by a later `open()` and when the player is disposed. A load failure is not `false` (it is still reported through events/recovery and thrown if unhandled). Code that only `await`s/`unawaited`s the call needs no change; classes implementing `IMovaApi` themselves (including test doubles) must change the return type of `open` to `Future<bool>`. `MovaPlaylist.jumpTo` accordingly no longer advances the index when `open` is rejected, so the list and the actual source no longer drift apart.
* **Fix: three edges of host async hooks, preview queue and gesture reconfiguration.** (1) `play()`/`seek()` re-check after the host's async `beforePlay`/`beforeSeek` returns: a late play/seek no longer overrides a user `pause()` or source switch in between (previously it flipped pause back to play or applied an old jump to the new source). (2) A single resolve throw in the preview service queue no longer makes all later requests skipped, and the `dispose` steps are isolated from each other (a throwing host-injected cache/probe no longer drags dispose down). (3) After gesture actions are reconfigured, displacement is taken from the axis that selected the mode: `horizontal: volume/brightness` increases to the right, `leftVertical/rightVertical: seek` fast-forwards upward (previously the wrong axis was read and displacement was about 0); default config behavior is unchanged.
* **Fix: three small issues.** `MovaDanmakuOpts` gained `assert(trackCount > 0)` (previously 0 caused a modulo by zero), `MovaGestureOpts` gained `assert(maxZoom >= 1)` (previously a value below 1 made `clamp` throw `ArgumentError` mid-pinch), and `MovaSttService.start()` rolls back `isRunning` when the player `start` fails so it can be retried directly without `stop()` first. Also completed the public member docs of `MovaPatch*` and `MovaPlatform`.
* **Refactor: rate for seamless cutover is now declared by the warm-up plan.** `MovaWarmPlan` gained `rate` (null inherits the old player, behavior unchanged) and `IMovaCutover.cutoverTo` gained the optional `rate`; the ad direction (built-in `effectiveWarmPlan` and pod `cutoverTo`) declares 1x and the back-to-content direction declares the rate before the ad, written directly onto the successor at cutover time, so there is no window where the ad briefly runs at the user's rate between the cutover and the reset taking effect. The original `setRate` reset in `MovaAds` is kept as a fallback only for the paths that fall back to an ordinary `open()` or where a host custom `adWarmPlan` carries no `rate`. Android device V12/V13a(2x)/V13b(1.5x) passed.
* **Fix: the second ad's `cutoverTo` in an ad pod was silently downgraded to an ordinary `open()`.** Two races: (1) `MovaCutover.abandon()` reset `_warmPlan`/subscriptions, set the phase back to `idle` and woke the ready completer only after the first `await`, so a `cutoverTo` right after `unawaited(abandon())` wiped the new warm-up; shared state is now reset synchronously before the `await`; (2) while `cutoverTo` was waiting, the old player's progress tick triggered "warm content behind the ad" in `MovaAds`, pushing out the ad shadow `cutoverTo` was waiting for; now content is not warmed while `cutoverTo` is in flight. Android device (STG-AL00) V12/V12b: the second ad took a real cutover (`renderEpoch` incremented), slot duration 5970-5999ms (configured 6000ms).
* **Fix: `state.pip` was not reset after the user expanded/closed system PiP.** Added the optional port capability `IMovaPipObservable.changes` (the player probes it with `is`, so existing `IMovaPip` implementations need no change); the Android plugin listens to Activity configuration changes and pushes `pipChanged` (on exit the PiP flag flips after the configuration change, hence the delayed re-check and dedup); the player updates `state.pip` and emits `MovaPipChange` accordingly. On Android device (STG-AL00) the `am start` expand path was verified `true -> false`; the close-by-X path could not inject a tap and was not tested.
* **Fix: full review (Codex + manual final review) fixed a batch of async staleness / resource ownership issues**, adding about 45 regression tests, with Android device (STG-AL00) re-tests item by item against the pre-fix baseline:
  * **Seamless cutover**: the warm-up timeout is now covered by an independent timer rather than progress events (`readyTimeout` previously did not take effect when the shadow had no progress at all); a failing shadow `open`/`seek` is cleaned up and falls back to an ordinary open and no longer sends `MovaErrorEvent` to the main event stream (which would misjudge a healthy playing ad as failed); when a shadow already exists and `cutoverTo` changes the source it is discarded before warming and the old shadow is no longer committed; a `dispose` in the middle of commit destroys the shadow; at commit rate/fit/zoom/volume/lock/fullscreen/mini/orientation are handed to the successor, the old player is marked retired via `IMovaHandoffRetirable`, and disposing a retired player no longer resets the global orientation.
  * **`Mova`**: validates `dispose` after `beforeOpen`; no longer `add`s to a closed event stream after `dispose`; under fullscreen/forced orientation `dispose` resets the device orientation and immersive mode; `MovaMpvKernel.open()` re-checks the sequence number after async recovery so old requests no longer override the new source; the `MovaVolumeChange.value` comment corrected to 0-100.
  * **Ads**: added a session number and a disposed flag, so a stale deferred resolve result no longer reopens the old content; ad load timeout and slot timing are based on the real first frame (`rendered`/`MovaFirstFrame`, falling back to two consecutive increasing non-zero positions) and are no longer cancelled early by a zero position/leftover progress; on the cutover path 1x is reset during the ad and the user's rate is restored afterwards.
  * **Others**: the feed pool releases the old player first when the same index switches source; the QoE session accumulator is cleared on each `open()`; a playlist `jumpTo` discards stale results when interleaved; preview thumbnails with a crop are not cached (otherwise a hit would show the whole sprite sheet), results of old requests are discarded after a source switch, and after a cutover commit the bubble resubscribes with `renderEpoch`.
  * Known unfixed items are in `CLAUDE.md` "full review leftovers" (PiP exit state not reset etc.).

* **Fix: process native crash on Windows when pushing an opaque route (HE V10)**: the root cause is not in mova but a Flutter 3.47.0/3.47.1 engine bug - with Windows + Impeller, the default `ZoomPageTransitionsBuilder` of `MaterialPageRoute` snapshots the page (`SnapshotWidget`), and when the snapshot carries an external GPU texture (media_kit's DXGI shared handle texture) the player dereferences a null context in `LayerTree::Flatten` and the process exits with `0xC0000005` in `flutter_windows.dll` (flutter/flutter#190774, fixed in Flutter 3.47.2). Pure media_kit `Video` without mova reproduces it too. mova-side workaround: on Windows the render surface of `MovaPlayer` is wrapped in `MovaSnapshotGuard` (adds a layer with `supportsRasterization()==false`, so a lenient snapshot falls back to ordinary painting); other platforms are unchanged. Release measurements: 6/6 crashes before the fix and the probe always crashed within 2 rounds; after the fix verification page V10A 20/20, V10 10/10, probe 20/20/20/30 rounds without crash. **The real fix is for the host to upgrade to Flutter >= 3.47.2**; alternatively turn off snapshotting for the transition in the theme (`ZoomPageTransitionsBuilder(allowSnapshotting: false)`). Added 8 regression tests (`test/ui/snapshot_guard_test.dart`). See the V10 section of the plan doc `doc/plans/2026-10-23-host-ergonomics.md`.

* **Fix: VOD recovery retry lost the resume position (HE V6)**: retries after a stall timeout, an `open()` exception and native `END_FILE(error)` recovery now send the resume seek only after the first frame of this attempt lands, avoiding the seek being dropped when the load command has returned but the file is not ready. Same-content alternative addresses reuse the resume point and keep it across failures; live does not seek. Code regressions passed; Windows/Android re-tests pending.

* **Fix: seamless-cutover warm-up changed the system volume by mistake (keepAlive plan Q13)**: `muteWhileWarm` now uses the optional player mute capability, and mpv only saves, rewrites and restores its own `mute`; warm-up and commit never write the system volume port. Kernels that do not support the capability do not mute; when combined with keepAlive mute each restores exactly by its own ownership. A failed mute restore goes through the abandon-cutover policy and emits an error event. Code regressions passed; device audio confirmation pending.

* **Host ergonomics (batch 1, `doc/plans/2026-10-23-host-ergonomics.md` Task 1-8)** - all off by default or identical to old behavior:
  * **"Picture shown" signal**: added `MovaState.rendered` (the current source has presented its first frame / first audio, reset on each `open()`) and the `MovaFirstFrame(sinceOpen, signal)` event (once per `open()`, repeatable); the criterion is pure logic in `MovaFirstFrameGate`/`MovaFirstFrameSignal` (native RESTART is authoritative, fallbacks are the buffering falling edge / consecutive increasing positions / first size while paused; when native is working and a fallback signal arrives first it waits up to a 1.5s grace). Internal reloads (quality switch, back to live edge, time shift) do not reset `rendered`.
    **Minor behavior change**: `open()` now synchronously zeroes `state.width/height` (previously it waited for the kernel to send null asynchronously), so the old picture's aspect ratio no longer leaks into the new source.
  * **Native event subscription decoupled from QoE**: `MovaMpvKernel(observeNativeEvents:)` (follows `observeQoeSignals` by default, existing call sites unchanged); `createMova(preciseFirstFrame:)` (default `false`; when `true` it subscribes to native RESTART even without a reporter for a more precise first frame, at the cost of one mpv weak client per player).
  * **Declarative fit mode**: `Mova`/`createMova` gained the initial-value parameter `fit`; `MovaPlayer(fit:)` applies it once on mount and afterwards only when the value changes (or `api` is replaced), so a value chosen with the fit button is not overridden by unrelated rebuilds.
  * **Built-in poster**: `MovaPlayer(poster:, posterFade:)`; the poster sits inside the `video` handed to the UI kit (buffering spinner/error layer/controls draw above it), fades out once `rendered` and the picture size is known, covers again the moment the source changes; audio-only sources keep it permanently. `MovaFeedPlayer(posterUntilFirstFrame:)` (default `false`) covers the placeholder as a poster until the first frame.
  * **Minimal UI kit** `MovaMinimalUiKit(showBuffering:, showError:)`: only the picture with an optional spinner/error layer, no gesture layer and no bars; `MovaTheme` gained nullable `bufferingSize`/`bufferingStrokeWidth`/`bufferingColor` (default `null` = same as the old look).
  * **Declarative widget** `MovaView`: just pass `source`; it creates/reuses/rebuilds (when `options` change)/disposes the player itself, pauses when the source becomes `null`, open failures go to `onOpenError` (default handed to `FlutterError.reportError`); with a `poster` it enables the native first-frame subscription by default. Added `MovaSource.sameAs()` (compares uri and type, ignores title); `MovaSource` deliberately does not override `==`.
  * **Breaking change (compile time)**: `MovaEvent` is `sealed`, so the new subclass `MovaFirstFrame` makes **exhaustive `switch` statements without a `default` branch** in host code fail to compile; add a branch or `default`. mova's own event translation already has a `default` and is unaffected.
* **Host ergonomics (batch 2, same plan Task 9-15)** - all off by default:
  * **Start/stall timeout and recovery** `MovaOpts.recovery` (`MovaRecoveryOpts`, default `enabled: false`): start timeout (default 10s), stall timeout (default 10s, `null` turns it off), `open()` throws, native `END_FILE(error)`, live reaching its end (`liveEndIsFailure`). Decisions come from the injectable `IMovaRecoveryPolicy` (default `MovaRetryThenFailover`: retry once after 1s per address then switch to alternatives, give up when exhausted; also `MovaFailoverOnly`), producing `MovaRecoveryDecision.retry/failover/giveUp`. New events `MovaPlayFailure(fail, action)`, `MovaRecovered(attempts)`; on give-up it writes `state.error = MovaGiveUpError`, emits `MovaErrorEvent` and pauses the kernel. Retry/switch is a kernel reload, not a new session (no interceptors, no `MovaSourceChange`, QoE session untouched). **When off, no Timer is created and no new stream is subscribed, and an `open()` failure is still thrown to the caller as before** (`MovaAds` relies on it to distinguish `openThrew`).
  * **Multi-address fallback**: `MovaSource(alternatives:)`, `MovaSource.uris`, `MovaSource.pick()` (cleans and dedups keeping order), `MovaState.sourceIndex`, the `MovaFailover(from, to, uri)` event. `sameAs()` now also compares alternative addresses (including order). **Alternatives are used only when `recovery.enabled`** and ignored when off. mova provides no sort/filter hook; the host sorts them.
  * **Auto-pause guard** `MovaAutoPause` and the pure logic `MovaAutoPauseGate`/`MovaAutoPauseOpts` (`MovaHideReason`/`MovaLiveResume`/`MovaGuardAction`); `MovaView(autoPause:, routeObservers:)`. Covers scrolling out of the viewport, inactive tabs (`TickerMode`), covered by a route, and going to background; `inactive` does not pause but first snapshots the play intent; no pause in PiP/mini; live hidden for >= 3s goes back to the edge and plays. Uses only the Flutter SDK, no new dependencies. **Note**: `routeObservers` is a **list**, one observer per navigator - a `NavigatorObserver` cannot be attached to two navigators at once.
  * **Host test doubles** `package:mova/testing.dart`: `MovaTestKernel`, `MovaTesting.useTestKernels()/reset()/lastKernel`; once installed `createMova()` uses a programmable kernel with all platform ports as no-ops, so widget tests no longer need `MediaKit.ensureInitialized`. Not in the main barrel.
  * **Breaking change (compile time)**: `MovaEvent` gained three more subclasses `MovaPlayFailure`, `MovaRecovered`, `MovaFailover` (4 in total with the previous batch's `MovaFirstFrame`); exhaustive `switch` statements without a `default` branch in host code need a new branch. `MovaOpts` gained the `recovery` section (with a default, so existing call sites are unaffected).
  * Verification page: `example/lib/main_host_ergonomics_verify.dart` (for device verification, not yet run on a device).
* **Review fixes (11 items)**: `MovaState.playbackIntent` is independent of the kernel `playing`, so internal reloads and the watchdog follow the latest play intent; recovery binds to the accepted session and the failed attempt and keeps the resume point across failures; the auto-pause guard subscribes to state and rebinds the player, keeping the hidden period from before a config update; live resume, view loading and quality requests all validate async staleness. See the "Review fixes" section of `doc/plans/2026-10-23-host-ergonomics.md` for item-by-item notes.

* **Low-power keepAlive (keepAlive, `doc/plans/2026-10-23-keep-alive-mode.md` Task 1-9)** - off by default, and no line of it runs unless called:
  * **Entry**: `MovaAutoPauseOpts(hiddenMode: MovaHiddenMode.keepAlive)` (handled automatically by the guard, default `pause`) and the imperative `IMovaKeepAlive.setKeepAlive(bool)` (implemented by `Mova`/`MovaCutover`; `IMovaApi` and `IMovaKernel` gain zero members, probe with `is`). Tuning in `MovaOpts.keepAlive` (`MovaKeepAliveOpts`: `maxDuration` default 30s, `silentStreams`, `allowHls` default false, `resumeTimeout` default 5s, `liveResumeGrace` default 3s).
  * **Mechanism**: live with audio -> turn off video decoding and mute (`mute`/`vid`, saved and restored as is, never touching `volume`/`vo`/`wid`/`VideoController`); no audio -> keep decoding and only mute; VOD, going to background, unknown media info, HLS (default) -> ordinary pause; falls back to pause automatically at `maxDuration`. **No network is saved; what is saved is decoding/rendering/battery.**
  * **State and events**: `MovaState.keepAlivePhase` (`MovaKeepAlivePhase`: `off`/`holding`/`fallback`/`resuming`), `MovaKeepAliveChange(phase, reason, mode)`, `MovaKeepAliveResume(elapsed, signal, from)`; `MovaKeepAliveMode`/`MovaKeepAliveReason`/`MovaSilentKeepAlive` become public along with them.
  * **Resume timing**: `MovaFirstFrameGate.arm(resume: true)` accepts only native RESTART and a non-zero size and lands immediately; `rendered` does not move at all and no `MovaFirstFrame` is emitted.
  * **Interaction with existing features**: during keepAlive the watchdog does not run, ABR and automatic back-to-edge do not trigger, and a failure is deferred to a forced reopen on wake; an `open()` source switch during a keepAlive request loads paused and tries keepAlive again after the first frame lands; `setMini(true)`/`enterPip()` wake first; `MovaCutover` passes through and applies keepAlive to the new player at commit; the poster covers instantly during keepAlive and resume; `MovaTestKernel` supports keepAlive (`hasAudio`/`fileFormat`).
  * **Breaking change (compile time)**: `MovaEvent` gained `MovaKeepAliveChange` and `MovaKeepAliveResume`, and `MovaGuardAction` gained `keepAlive`/`wake`; exhaustive `switch` statements without a `default` branch in host code need new branches.
  * Verification page: `example/lib/main_keep_alive_verify.dart` (for device verification, not yet run on a device).

## 0.3.0

* QoE reporting enhancement: `IMovaReporter` covers the four QoE metrics TTFF first-frame time, stall count and duration, fatal/non-fatal playback failure distinction, and session start/end (with four end reasons); added `MovaReportOpts` (`MovaOpts.report`, default `qoe: false`, with the off-state event stream byte-identical to before). Signals prefer native libmpv capabilities (`paused-for-cache`/`video-bitrate`/`cache-speed`/dropped-frame count/log-prefix error classification), and two real bugs were fixed along the way: a session-boundary timing race in `Mova.open()` and a native resource race in `MovaMpvKernel.dispose()`.
  * **Breaking changes**:
    1. `MovaReportName` changes from an `enum` to a const value class - there is no more `MovaReportName.values.byName()`; `.index` is gone; call sites that `switch` on the name must switch on `.value` (`String`) instead, because Dart does not allow constant patterns on a type that overrides `==`. `==`/`hashCode` are computed from `.value`, `Map`/`Set` key usage and the `IMovaApi.report(name, ...)` signature are unchanged, and ordinary comparison call sites need no change.
    2. `MovaErrorEvent` production moves from `translator.dart` to `MovaQoeCollector`; with `qoe: true` `params` grows from `{'error'}` to `{'error', 'fatal', 'code'}` and non-fatal errors are downgraded to `batched` (old behavior unchanged with `qoe: false`).
  * Native mpv events (`PLAYBACK_RESTART` precise first frame, `END_FILE` session end reason) are subscribed by a self-built `dart:ffi` weak client (`mpv_create_weak_client`); the `media_kit` dependency stays at the pub.dev `^1.2.6` and **no longer depends on a git commit, so it can be published normally**. In debug it polls every 100ms and in release it uses native callbacks. Verified on Android and Windows; iOS/macOS not verified (silent fallback when the subscription fails).
  * QoE fixes (found after running on an Android device): the initial `false` of `buffering` after open is no longer taken as the first frame (a `true -> false` falling edge plus a "two consecutive increasing position samples" fallback is needed); `sessionEnd.stallMs` is no longer accumulated twice (it was 2x the real value); `watchedMs` is not counted before the first frame lands. When the native RESTART subscription is working (new `IMovaStatsProbe.nativeRestartAvailable`), the first frame trusts only RESTART and ignores earlier but coarser buffering/position fallbacks.
* **`VideoController` is now lazily created**: `MovaMpvKernel` gained `lazyVideo` (default `false`); `createMova()` and the default `Mova` kernel use `lazyVideo: true` and create the `VideoController` only the first time `renderHandle` is read (when `MovaPlayer` is mounted). A controller that is created but never attached to the UI makes media_kit's `Player.dispose()` wait forever (3/6 on Windows and 4/5 on Android hit the 8 second timeout on devices); with lazy creation, disposing an player that was created but never shown takes only a dozen milliseconds. The shadow player of seamless cutover reads `renderHandle` once after creation, so the picture pipeline still exists during warm-up. **If the caller creates and injects a `VideoController` itself, it must ensure it is attached to the UI before disposing** (see README "Known limitations").
* **Truncated-end judgment**: with `qoe: true`, a VOD session ending at EOF with a completion rate below `MovaReportOpts.truncatedBelow` (default `0.9`, `<=0` turns it off) is no longer recorded as `ended` but first emits a fatal `MovaErrorEvent` (`code: truncated`) and then records `failed`; live has no duration and is judged truncated only when there are ffmpeg error logs within the 5 seconds before `MovaDone`. Fixes a network drop after the first frame / the server cutting the stream midway being misrecorded as `ended` (Android device mid-stream cut re-test passed).
* **TLS strict verification switch**: `createMova()`/`MovaMpvKernel` gained `tlsVerify` (default `false`, behavior unchanged) and `tlsCaFile`. When on, HTTPS streams with an expired/self-signed/hostname-mismatched certificate are rejected (stream error, session `failed`), and HLS segments and AES keys are verified too. **Android's slim libmpv uses mbedtls with no system trust store, so when enabling it you must also pass `tlsCaFile` (PEM), otherwise all HTTPS fails**; putting a self-signed certificate into `tlsCaFile` trusts that certificate. Direct IP connections (such as `127.0.0.1`) do not compare the certificate hostname. The Android device local HTTPS matrix of 144 runs all matched expectations; iOS/macOS not verified.
* **Preview frame extractor fix**: `MovaFrameExtractor` no longer creates a `VideoController` (its initialization can never complete without a UI, and `extract` timed out 5/5 on Android), and instead decodes with `vid=auto` + `vo=null`; before the first seek it waits for the duration to be ready, then polls `seeking`/`time-pos` to determine that the seek has landed before capturing.
  * **Behavior change**: `settleDelay` changes meaning from "a fixed wait after the seek" to "an extra wait **after the seek lands**", and its default drops from 250ms to 60ms; if you pass your own value explicitly, re-evaluate it under the new meaning.

## 0.2.0

* Slim libmpv integration: a lightweight binary replacement scheme (Android / Windows / iOS / macOS) that cuts size by about 50%.
* Feed immersive stream player enhancements: short-video swiping, preloading and Douyin-style UI kit customization.
* Fixed the `ensure()` async callback type inference warning in `MovaFeedPlayer`.
* Improved docs and integration patterns.

## 0.1.0

First release.

A Flutter video player plugin built on media_kit (libmpv/ffmpeg) with a self-built gesture and control layer, supporting VOD and live; it can be used as a standalone UI and deeply customized through the Plugin / Component / UiKit three-layer contract.

### Core playback

* Playback kernel wrapping: `IMovaApi` (capability surface abstraction) + `Mova` (production implementation) + `IMovaKernel` (kernel abstraction; the only media_kit-dependent detail is contained in `MovaMpvKernel`).
* Construct players with `createMova()` (`lib/src/platform_impl/wiring.dart`), which wires the real brightness / PiP / orientation platform adapters; the bare `Mova()` constructor defaults its platform ports to no-ops and is only meant for injecting fake ports in unit tests.
* Quality: HLS master parsing, manual switching (position-preserving resume), automatic downshift on stalls (ABR).
* Fit modes `contain` / `cover` / `fill`; lock/unlock against accidental touches + immersive; fullscreen picks landscape/portrait by the video aspect ratio, and `IMovaApi.setOrient` can force landscape/portrait (independent of fullscreen).
* Audio-only mode (`audioOnly`): `createMova(audioOnly: true)` skips the video decoding pipeline entirely (no `VideoController`, no GPU texture registration), so `renderHandle`/`size` become `null`/`0x0` and the UI layer needs no change (pass cover/lyrics etc. as a custom picture through `MovaPlayer.surface`). Measured memory savings of about 2-2.7x (depending on the scenario).

### Gestures and UI

* Gesture layer: horizontal swipe for progress / double-tap seek / two-finger zoom with a HUD; left/right vertical swipes default to brightness / volume (aligned with mainstream players such as bilibili), freely remappable through the side-to-action mapping of `MovaGestureOpts` (`MovaGestureAction`) or disabled for a side with `MovaGestureAction.none`.
* Component tree / UI kit / patch three-layer contract: the `MovaComponent` tree is produced by `IMovaUiKit` (default `MovaDefaultUiKit`) from `MovaState`, with structure-level customization through `MovaPatch` (`replace`/`remove`/`insertAfter`/`add`) without subclassing; `MovaDefaultUiKit.assemble` can also be half-overridden through the three layers `buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`.
* `MovaPlugin` capability mixin: gives stateful components `api` (a stable handle) and `bind()` (subscribe and auto-reclaim on `dispose`).
* Strings and theme: `MovaStrs` (default Simplified Chinese strings) and `MovaTheme` (default colors/sizes) are injected through `MovaOpts` and can be replaced wholesale.
* System volume port `IMovaVolume`: right-side swipe can drive the system media volume instead of only the player volume; Android wires the native `MovaSystemVolume` by default and other platforms can pass `MovaCallbackVolume` to take over.
* Rendering performance: the playback / operable / persistent layers are each isolated by a `RepaintBoundary` so they do not repaint each other.

### Live features

* The VOD and live control bars adapt and are merged into `MovaBottomBarComponent`.
* Live time shift: two draggable modes `MovaLiveSeekMode.dvr` / `.timeshift`, configurable through `MovaLiveOpts.urlBuilder`/`backToLive`/`autoBackToLiveOnStall`/`windowResolver`; `MovaState.timeshiftBehind` works with the `MovaTimeShiftChange`/`MovaLiveEdgeReach` events, and `IMovaApi.backToLiveEdge()` executes by policy.
* `IMovaApi.pipSupported`/`MovaState.pipSupported`: the PiP button hides automatically on unsupported platforms.

### Picture-in-picture / in-app mini window

* Android system PiP (`IMovaApi.enterPip()`); iOS/desktop not yet supported (with libmpv texture rendering, system PiP depends on an AVPlayer path that is not implemented, and `pipSupported` returns `false`).
* In-app mini window `MovaMini`: no system PiP API needed, the picture shrinks from the page into a draggable floating mini window without re-decoding or black frames. **Off** by default (zero behavior change on the whole path while `MovaMiniOpts.enabled` is `false`). Two mounting styles coexist: `MovaMini.showInPage` (floating inside the page) and `MovaMini.show` + `MovaMiniHost` (persistent across routes). Supports edge snapping / clamping / safe-area avoidance and fling-to-close with inertia. Mutually exclusive with system PiP (entering the mini window first leaves system PiP and vice versa).

### Scrub preview thumbnails

* While dragging the progress bar or horizontal-swipe seeking, a thumbnail bubble of the target moment is shown above the progress bar (`MovaPreviewComponent`).
* Thumbnail sources in order: server-side WebVTT sprite sheet (`<video-url>.vtt`, supports `#xywh` cropping) -> libmpv hidden `Player` frame-extraction fallback; the source chain can be replaced wholesale through `MovaPreviewOpts.sources`.
* Two-level memory + disk cache; the network policy defaults to `wifiOnly` (decided by a `connectivity_plus` probe; unknown connections and desktop are always allowed), and when blocked it silently makes no request and emits a `MovaPreviewBlock` event.
* The defaults of `extractor`/`probe` in `createMova()` are `null` (to avoid statically reaching `media_kit_video`/`connectivity_plus` by default, which helps tree-shaking). To enable the frame-extraction fallback and the `wifiOnly` network policy, pass `extractor: MovaFrameExtractor()`/`probe: MovaConnectivityNetProbe()` explicitly; without `probe` the kernel falls back to the pure-Dart `MovaAlwaysAllowNetProbe()` and the `wifiOnly` policy is not enforced (other network policies are unaffected).

### Ad orchestration

* `MovaAds` plays ads with real business timing: the content source can be resolved lazily (`loadDeferred(MovaSourceResolver)`), and ad slot `duration`/`delay` are decoupled from the asset timeline (driven uniformly by a `Timer`, without querying/depending on `state.duration` and without tail seeks).
* Whether to wait for readiness is decided by ad slot kind (`IMovaAdWaitPolicy`, built-in `MovaAdWaitByKind` defaulting to `pre` no / `mid` yes / `post` no), with three override layers collected in `MovaAdOpts.waitsFor()`.
* Ad load failure fallback: `IMovaAdFailPolicy` (built-in `MovaAdRetrySkip`/`MovaAdAbandonPod`) handles open failures, player errors, no-first-frame timeouts and warm-up-not-ready uniformly.
* Waiting/seamless cutover requires the host to also wire the `MovaCutover` of the next section and enable `MovaCutoverOpts.enabled`, otherwise it degrades to the traditional "cut at the due time" behavior.

### Seamless cutover (optional)

* `MovaCutover`: a proxy layer that itself implements `IMovaApi`, holding the effective player and a warming shadow player and switching the pointer atomically once ready, turning "back to content after the ad" from a black screen/loading into a frame-seamless cutover. Default `MovaCutoverOpts.enabled: false`, and when off it is a pure pass-through proxy with the same behavior as not wiring it. `MovaState.renderEpoch` increments after a cutover to trigger the render surface to re-read `renderHandle`.
* Two pluggable layers: warm-up trigger strategy (`IMovaWarmTrigger`: `MovaLeadWarm`/`MovaEagerWarm`) and readiness criterion (`IMovaWarmPolicy`: `MovaBufferWarm`); `MovaWarmPlan` can be configured per warm-up direction.
* **Known limitations**: quality switching (`switchQuality`) and the feed player pool are not wired into seamless cutover - the former already goes through the safe registered-resume path but has not been verified through seamless cutover itself, and the latter is structurally not applicable (it needs two pictures coexisting).

### Dependencies

* `media_kit` / `media_kit_video` / `media_kit_libs_video`: playback kernel.
* `path_provider`: disk cache directory for scrub preview.
* `connectivity_plus`: probe for the `wifiOnly` network policy of scrub preview.
* `screen_brightness`: system brightness port for the brightness gesture.

### Known limitations

* iOS system PiP is not implemented (see above).
* `switchQuality` is not yet wired into seamless cutover (see the "Seamless cutover" section above).
* `MovaAudioUiKit` (a UI kit dedicated to cover/lyrics/waveform) is not provided; for audio-only scenarios pass a placeholder picture yourself through `MovaPlayer.surface`.

## 0.0.1

* Initial scaffold.
