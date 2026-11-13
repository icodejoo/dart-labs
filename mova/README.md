# mova

[English](README.md) | [Chinese (zh-CN)](README.zh-CN.md)

A Flutter video player built on [media_kit](https://pub.dev/packages/media_kit)
(libmpv/ffmpeg) with a self-built gesture + control layer for VOD and live
playback.

> **Repository version: 0.4.2** (pubspec.yaml is authoritative).
> The CHANGELOG may have an `Unreleased` section. Those changes come after the
> current release and are only available through a path or git dependency.
> Before installing a pub.dev version, check its CHANGELOG entry, and don't assume
> a repository feature has been released.
> Android/Windows have partial real-device verification; iOS is not verified,
> CP2/CP3 still need real devices, and CP1 is 13 PASS / 3 BLOCKED, so it has not
> passed as a whole. The target-device acceptance scope is in the
> [SPEC](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) and the
> [acceptance matrix](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/ACCEPTANCE-MATRIX.md).

## Features

- **Gestures**: vertical swipe on the left half = brightness, right half = volume, horizontal swipe = seek, double tap = fast forward/rewind, two-finger pinch = zoom, all with HUD feedback; the side-to-action mapping is configurable.
- **Fill modes**: cycle through `contain` / `cover` / `fill`.
- **Lock**: one tap blocks all touch input, so nothing triggers by accident while you watch.
- **Orientation**: fullscreen picks landscape/portrait from the video aspect ratio; the top-bar orientation button (mobile only) can force landscape/portrait via `setOrient`, independent of fullscreen.
- **Quality**: reads renditions from the HLS master playlist, switches manually, and steps down automatically when the network stalls. The "auto" rendition uses libmpv's own ABR.
- **PiP**: Android system-level picture-in-picture (iOS/desktop not supported yet, see below).
- **VOD & Live**: separate control bars. Live seeking is off by default; you can turn it on as DVR (seek inside the server window) or time-shift (seeking re-opens the source). Live has a "back to live" button and a time-shift badge.
- **Scrub preview**: while dragging the progress bar or horizontal-swiping, a thumbnail bubble for the target time floats above the bar (WebVTT sprite sheet / libmpv frame extraction fallback, two-level cache, Wi-Fi only by default).
- **Ad orchestration (optional)**: `MovaAds` plays pre/mid/post-roll breaks on a schedule, with deferred content-source resolution, ad-slot duration decoupled from asset duration, readiness waiting, and failure fallback.
- **Seamless cutover (optional)**: `MovaCutover` keeps the current player and a warming-up shadow player behind one render surface, and cuts over between them atomically when the shadow is ready. This removes the black screen or loading spinner when, for example, content resumes after an ad. Off by default.
- **In-app mini window (optional)**: separate from system PiP. Shrinks the picture into a draggable floating window, with no re-decoding and no black screen. Off by default.
- **Audio-only mode (optional)**: skips the video pipeline and decodes audio only, saving memory/CPU. Off by default.

## Platform support

| | Android | iOS | Windows |
|---|:---:|:---:|:---:|
| Playback / gestures / control bar | Yes | Not verified | Yes |
| Picture-in-picture (PiP) | Yes | No | No |

> iOS/desktop PiP: media_kit renders libmpv through textures, while system-level PiP depends on the AVPlayer path, which is not implemented yet; `isPipSupported()` returns `false`. See the "PiP (native)" section of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md).

## Known limitations

- iOS/desktop (Windows/macOS/Linux) do not support system-level picture-in-picture yet.
- Desktop platforms (Windows/macOS/Linux) have no "true fullscreen" (fill the OS window, remove the title bar); `setFullscreen()` itself only updates state/orientation. For in-app fill use `MovaPlayer(fullscreenRoute: true)`; OS-window fullscreen must be wired by the host with a package such as `window_manager` (see the "Platform ports" section below).
- Strict TLS verification (`createMova(tlsVerify: true, tlsCaFile: ...)`, off by default, in which case Android libmpv does not verify certificates): **on Android, enabling it requires also passing `tlsCaFile` (a PEM CA bundle, for example concatenated from the certificates under `/system/etc/security/cacerts/`), otherwise every HTTPS request fails** (the slimmed libmpv uses mbedtls and has no system trust store); direct-IP connections do not verify the certificate host name, only domain names are checked; iOS/macOS are not verified.
- Audio-only mode (`audioOnly`) does not provide background playback, lock-screen/notification controls, headset buttons, audio focus, gapless playback, or playlists; those need a dedicated solution such as `just_audio` + `audio_service`.
- **For a kernel with video, the `VideoController` must be attached to the UI before it can be disposed cleanly** (this is media_kit behavior, not introduced by mova): if a `VideoController` is created but never attached to a video widget, `Player.dispose()` keeps waiting for it; on real devices 3 of 6 disposes on Windows and 4 of 5 on Android hit the 8-second timeout. The default implementation (`createMova()` / `Mova()`) creates it **lazily**, on first render (when `MovaPlayer` is mounted and reads `renderHandle`), so "created an player but never showed it, then disposed it" is safe. **If you create and inject the `VideoController` yourself (passing your own `MovaMpvKernel`/`Player`, or a kernel with `lazyVideo: false`), you must make sure it ends up attached to the UI before disposing it**; for scenarios that show no picture (pure logic, background warm-up, unit tests) use `audioOnly: true`, or keep the default lazy creation and do not read `renderHandle`. The shadow player of seamless cutover is the exception: it needs to decode frames during warm-up, so it creates the controller early.
- **Flutter 3.47.0/3.47.1 (Impeller) on Windows: pushing/popping an opaque route crashes the process natively**. This is a Flutter engine bug (flutter/flutter#190774, fixed in 3.47.2), unrelated to mova, and plain media_kit crashes too. mova works around it on Windows by excluding the player render surface from page-transition snapshots; hosts are still advised to upgrade to Flutter 3.47.2 or later. Pages that use the media_kit `Video` directly are not covered by this workaround and need to upgrade or turn off snapshotting for the transition (`ZoomPageTransitionsBuilder(allowSnapshotting: false)`).
- The viewport detection of the auto-pause guard (`MovaAutoPause`) only walks ancestor `Scrollable`s and does **not** cover occlusion caused by arbitrary `ClipRect`/`Transform`/`Overlay`; translucent routes on an outer navigator require `routeObservers` (one observer per navigator, they cannot be shared); if a lazy list disposes a card before the guard had a chance to pause it, the player belongs to its owner from then on.
- KeepAlive has Windows release data (FLV wake-up 18/18 went through the grace period, and the timing readings are the 5s fallback, so they cannot be used as measured first-frame times), and Android CP1 S1/S7/S13/S14 are 20/20; HLS, power consumption and iOS/macOS are still not sufficiently verified. See the [keepAlive verification record](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/plans/2026-10-23-keep-alive-mode.md) and [CP1](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/plans/2026-11-03-cp1-results.md).
- Recovery, ads and cutover are now coordinated by one session: non-terminal diagnostics are left to the player; while recovering it waits for giveUp, and a terminal ad failure is decided once by the ad policy; a content failure enters `contentError` and does not advance to the next episode automatically. A new host `open` takes priority, and the old session and old shadow yield.
- Out-of-pool network prefetch for Feed only issues a Range request of about **64KB** (default `bytes=0-65536`, 65537 bytes inclusive); the code drains the response, so a server that ignores Range may deliver the whole resource; for HLS only the **m3u8** is fetched and media segments are not prefetched. Every prefetch does a `force close`, so connections are not reused; the player of an out-of-pool live item may still pull the stream at full speed, so prefetch is not a substitute for rate limiting or an offline cache.
- STT model download is an **experimental implementation with no checksum verification**, and this package ships no recognizer.
- **DRM, casting and offline download are not supported**.
- Some optional capabilities (ad orchestration, seamless cutover, in-app mini window, audio-only mode) are implemented in code but verified on real devices to varying degrees; see the [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) chapters linked from each section.

## Install

```yaml
dependencies:
  mova: ^0.5.0
```

To use picture-in-picture on Android, declare it on the Activity in `AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|screenSize|screenLayout|smallestScreenSize|...">
```

## Capability entry points (0.4.x)

`package:mova/mova.dart` still exports everything it used to. You can also import by capability:

| Entry | Purpose |
|---|---|
| `package:mova/ui_kit.dart` | Components, slots, scopes, MovaChrome, styles |
| `package:mova/ads.dart` | Ads and their configuration |
| `package:mova/feed.dart` | Feed data, widgets, controller and prefetch |
| `package:mova/mini.dart` | Mini window and its configuration |
| `package:mova/extend.dart` | Session, cutover, preview, platform ports, reporting |
| `package:mova/stt.dart` | STT port, subtitles and experimental model download |

The STT re-export from the main entry is kept for one version only; switch to importing `package:mova/stt.dart` (`MovaSttOpts`, `IMovaStt`, `formatSrt` and the other STT types live there; `IMovaApi.stt` stays).
The plan to hide internal helpers from the exports is in the [SPEC](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md); members are not marked `@Deprecated` yet.

## In-app fullscreen and view styles (0.4.x)

```dart
MovaPlayer(
  api: mova,
  fullscreenRoute: true, // default false; the root Navigator pushes mova/fullscreen
  style: const MovaPlayerStyle(strings: MovaStrs(retry: 'Try again')),
)
```

The back key leaves fullscreen first (while locked, it asks you to unlock). The fullscreen route reuses the same API and builds its own controls; when you leave it, the inline control bar comes back.
Orientation and PiP/mini are still managed by the player; a custom surface on Windows is protected by the snapshot guard as well.
`MovaPlayerStyle` is looked up per section: view parameter > ThemeExtension > legacy options > defaults, and switching themes does not rebuild the player.
A component can use `MovaChrome.of(context)` to control the HUD/control bar/dragging of its own view; lock, fit and zoom are still shared.

## Source headers and start position (0.4.x)

```dart
const source = MovaSource(
  'https://cdn.example/video.mp4',
  headers: {'Authorization': 'Bearer token'},
  userAgent: 'MyApp/1.0',
  start: Duration(seconds: 30),
);
```

An explicit `userAgent` overrides a header of the same name. Playback, quality probing, VTT/sprite sheets, frame extraction and Feed prefetch share the headers;
`start` is for VOD only and waits for readiness through the seek register chain. A custom side-channel HTTP client should implement
`IMovaHeaderedHttpFetch.getWithHeaders(Uri url, Map<String, String> headers)`;
the old `IMovaHttpFetch.get(Uri)` still works, but it drops the headers and prints a debug hint once per instance.
The default IO implementation sets headers per request and does not leak them into the next request; a custom frame extractor can implement `IMovaHeaderedFramePuller`.
If different players (content and cutover shadow, feed pool) or retries open the same URL with different headers, the headers stay separate;
the preview thumbnail cache key also includes the headers (same as before when there are none). A failure to parse `http-header-fields` is no longer silently cleared; it is reported on the diagnostics stream.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Mova.ensureInitialized(); // one-time global initialization
  runApp(const MyApp());
}

class Page extends StatefulWidget {
  const Page({super.key});
  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  late final Mova mova;

  @override
  void initState() {
    super.initState();
    mova = createMova();
    _open();
  }

  Future<void> _open() async {
    try {
      await mova.open(const MovaSource(
      'https://example.com/master.m3u8',
      type: MovaStreamType.live, // or MovaStreamType.vod
      title: 'Demo',
      ));
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    }
  }

  @override
  void dispose() {
    mova.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MovaPlayer(api: mova); // default UI kit MovaDefaultUiKit
  }
}
```

> **Note**: apps should use `createMova()` exported by `package:mova/mova.dart`, which wires the
> brightness/PiP/orientation ports by default. A bare `Mova()` uses empty platform ports,
> which suits tests or injecting your own ports, and prints a one-time hint in debug.

To customize the gesture side-to-action mapping and switches, pass `MovaOpts` to the player. Sides and actions are decoupled and can be
remapped freely (put brightness on the right, or disable a side with `MovaGestureAction.none`):

```dart
final mova = createMova(
  options: const MovaOpts(
    gesture: MovaGestureOpts(
      // Default: left brightness, right volume, horizontal seek. This example switches back to the old layout (left volume, right brightness).
      leftVertical: MovaGestureAction.volume,      // left vertical swipe = volume
      rightVertical: MovaGestureAction.brightness, // right vertical swipe = brightness
      horizontal: MovaGestureAction.seek,          // horizontal swipe = seek
      doubleTapSeek: true,
      doubleTapStep: Duration(seconds: 10),
      pinchZoom: true,
    ),
  ),
);
```

## Declarative usage (MovaView)

When you just want to "mount a card and play a URL" without managing the player lifecycle yourself:

```dart
MovaView(
  source: url == null ? null : MovaSource(url, type: MovaStreamType.live),
  fit: MovaFit.cover,
  poster: Image.network(cover, fit: BoxFit.cover),
  uiKit: const MovaMinimalUiKit(),
)
```

- The player is created the first time a non-null `source` arrives; it is re-opened only when `source` really changes (`MovaSource.sameAs`: compares uri, type, alternatives, source options, headers/userAgent/start, and **not the title**), so rebuilding with the same source does not re-open the stream.
- When `source` becomes `null`: the player pauses, leaving only the poster (a black background if there is no poster).
- Only a change in the option sections the player actually reads **disposes and rebuilds** the player; equal inline options and changes to ads/playlist/mini do not rebuild it. UI style changes only update the view; the player's options keep the construction snapshot.
- An open failure goes to `onOpenError`; if not provided it is handed to `FlutterError.reportError` and never becomes an uncaught async exception.
- When you need to pass the player around (cross-route mini window and so on), keep using the imperative `createMova()` + `MovaPlayer`; **do not give the player owned by `MovaView` to `MovaMini`**, because `MovaView` disposes it when it unmounts.

## Poster and the rendered signal

`MovaState.playing` becomes true **before loading starts**, so it cannot tell you whether a picture is showing. Use `MovaState.rendered`: the first frame of the current source is on screen (for a source without video, the first audio segment is audible). It resets to false on every `open()`; internal reloads such as quality switching, going back to the live edge and retrying do **not** reset it, so the poster does not flash white.

```dart
api.events.listen((e) {
  if (e is MovaFirstFrame) log('first frame ${e.sinceOpen} via ${e.signal}');
});
```

- How it is detected: the native `PLAYBACK_RESTART` is the most accurate; without a subscription it falls back to the buffering falling edge, consecutively increasing positions, and the first picture size in the paused state. If the native subscription is working but RESTART never arrives, it lands after at most a 1.5s grace period.
- **By default the first open lazily subscribes to END_FILE, and RESTART is not enabled** (one weak mpv client per player, plus a 100ms poll in debug; END_FILE is independent of the recovery switch): `createMova(preciseFirstFrame: true)` turns it on and gives a more accurate first frame (on real devices the buffering fallback is about 200ms earlier than the real RESTART, which is optimistic); `MovaView` enables it by default when it has a `poster`.
- `MovaPlayer(poster:)` / `MovaView(poster:)`: the poster is layered into the "picture layer" passed to the UI kit, with the buffering spinner, error layer and control bar painted above it; it fades out (`posterFade`) once `rendered` and the picture size is known, and covers again the moment the source changes; for audio-only sources the poster stays. `MovaFeedPlayer(posterUntilFirstFrame: true)` works the same way and is off by default.
- Fill mode is declarative: `Mova(fit:)` / `createMova(fit:)` give the initial value, and `MovaPlayer(fit:)` / `MovaView(fit:)` apply it once at mount and **when that parameter changes**; a value picked by the user with the fit button is not overwritten by unrelated rebuilds.
- For a bare picture with no gestures and no bars: `MovaMinimalUiKit(showBuffering:, showError:)`; the spinner size/stroke width/color use `MovaTheme.bufferingSize/bufferingStrokeWidth/bufferingColor` (default `null`, i.e. the old look).

## Playback errors

`state.error` only holds terminal errors, for the retry overlay and failure state; this includes `END_FILE(error)`, recovery giving up, known terminal texts, and an `open` throw. The default configuration also detects END_FILE, with the weak client started only on the first open; old events are drained before each load and late notifications are dropped per load attempt. Each attempt reports a terminal error only once, and duplicate logs stay as diagnostics; a keepAlive failure is recorded silently and re-opened at wake-up. With recovery off, an open failure is still thrown in this version and also writes the terminal state; the next version will stop throwing.

Without an END_FILE event pump or when its registration fails, mova falls back to catching main-file open failures: when an error arrives it checks whether the pump is available, and only if a stream/cplayer/ffmpeg error text contains the current main file's effective address does it enter the same recovery or terminal entry. Separate addresses of external subtitles, external audio tracks and HLS segments do not trigger this fallback; when the pump is active, END_FILE still decides termination.

Non-terminal kernel logs keep being sent as `MovaErrorEvent(fatal: false)` and notify `MovaHook.onError`, and do not write `state.error` or show the error overlay. When migrating code that "listens to state.error to collect all errors", listen to events instead:

```dart
mova.events.listen((event) {
  if (event is MovaErrorEvent) {
    recordDiagnostic(event.error);
    if (event.fatal) showPlaybackFailure();
  }
  if (event is MovaPlayFailure) recordRecoveryDecision(event.action);
});
```

With recovery enabled, `MovaPlayFailure` reports every retry/failover/give-up decision. The error overlay texts are configured with `MovaStrs(playbackError: 'Playback failed, please retry', retry: 'Retry')`, and the raw error text is only shown in debug mode. A `MovaPlayer`/`MovaView` with a poster enables the RESTART precise first frame.

## Timeouts and multiple addresses (optional, off by default)

Terminal failures are already detected through `END_FILE(error)` by default and end the spinner; `MovaOpts.recovery` adds a timeout fallback, retry and multi-address failover:

```dart
createMova(
  options: const MovaOpts(recovery: MovaRecoveryOpts(enabled: true)),
);
// Order the addresses by your own priority; mova only guarantees trying them in the given order
final src = MovaSource.pick([hd, sd, backup], type: MovaStreamType.live);
```

- Triggers: **start timeout** (no first frame; a fallback deadline derived from `timeouts`, default 65s for non-WHEP / 85s for WHEP; opening in the paused state with `autoPlay: false` is not timed, and timing starts from scratch after `play()`), **stall timeout** (continuous buffering after the first frame; fallback deadline default 65s non-WHEP / 10s WHEP, turned off with `stallWatchdog: false`; pausing stops the timer), an `open()` throw, native `END_FILE(error)` (a bad address fails immediately instead of waiting for a timeout; subscribed by default, independent of `recovery`, no need to add `preciseFirstFrame`), and a live stream reaching its end (`liveEndIsFailure`, counted as a failure by default).
- Default policy `MovaDefaultRecovery`: **VOD** uses `MovaRetryThenFailover` (wait 1s and retry each address once, then move to the next alternative, give up when all are used; same behavior as before); **live** uses `MovaLiveReconnect` (exponential backoff 1s, 2s, 4s... capped at 15s (`maxDelay` is adjustable), reconnecting continuously so playback resumes automatically after the publisher restarts or drops; with alternatives, earlier addresses are retried once each before moving on, the last address reconnects forever, and `maxAttempts` can set a cap). To stop live from reconnecting forever: `MovaRecoveryOpts(liveReconnect: false)`, and live goes back to the same "retry once then give up" as VOD. `MovaFailoverOnly` does not retry the same address; you can also implement `IMovaRecoveryPolicy` to replace it entirely (a policy that throws is treated as giving up; `MovaPlayFail.isLive` tells live from VOD).
- **Who does what on reconnect**: timeouts are handled by libmpv/ffmpeg, and Dart only handles reconnecting. Live does **not** enable libmpv's `reconnect_streamed`; stream-drop reconnects are left entirely to `MovaLiveReconnect` (exponential backoff, multi-address failover, events); VOD **keeps** mpv's default ffmpeg reconnect (Range resume, window about 11s). The **main path** that triggers reconnecting is mpv's `END_FILE(error)`; Dart's `startTimeout`/`stallTimeout` are only a **fallback watchdog**, covering hangs where mpv reports no error (buffering spinning forever, WHEP where server-side STUN keepalives keep `media_timeout` from firing, and so on).
- **Unified timeout config `MovaRecoveryOpts.timeouts` (`MovaTimeouts`)**: `network` -> mpv `network-timeout` (whole seconds), `whepHandshake`/`whepFirstFrame`/`whepMedia` -> WHEP `handshake_timeout`/`first_frame_timeout`/`media_timeout` (microseconds, `whep...` addresses only), sent to mpv before every open; anything you leave unset keeps mpv's default. Explicit settings of the same option in `MovaSource.mpvOptions`/`demuxerOptions`/`whepMediaTimeout` take precedence.
- **Watchdog deadlines are derived from the mpv window by default**: when `startTimeout`/`stallTimeout` are not set they equal the longest mpv-side window + 5s margin, so the watchdog never fires before mpv's reconnect/handshake window ends; if set explicitly, your value wins (a value shorter than the mpv window interrupts mpv's reconnecting). The mpv window: for non-WHEP it is `max(network, 11s)` (an unset `network` uses mpv's default 60s; 11s is the ffmpeg reconnect window), for WHEP start it is `network+handshake+firstFrame` (default 60+10+10), and for stalls it is `media_timeout` (default 5s). Turn the stall watchdog off with `stallWatchdog: false` (replacing the old `stallTimeout: null`).
  ```dart
  // 10s network timeout: non-WHEP start/stall fallback 16s; WHEP (handshake 5 / first frame 8 / media 5) start 28s, stall 10s
  const MovaRecoveryOpts(
    enabled: true,
    timeouts: MovaTimeouts(
      network: Duration(seconds: 10),
      whepHandshake: Duration(seconds: 5),
      whepFirstFrame: Duration(seconds: 8),
      whepMedia: Duration(seconds: 5),
    ),
  );
  ```
- Deterministic failures (404, connection refused, an `open()` throw, an `END_FILE(error)` arriving while a load is in flight) proceed to the next attempt with the policy's backoff as soon as they are discovered, without waiting for the full `startTimeout`.
- Events: every failure emits `MovaPlayFailure(fail, action)` (`fail.kind` distinguishes start/stall/..., and `state.error` is **not** written at this point because it is still retrying); a picture reappearing after a failure emits `MovaRecovered` and also clears the `state.error` left over from the failure; switching to an alternative emits `MovaFailover(from, to, uri)` and `MovaState.sourceIndex` follows; after all fail, it writes `state.error = MovaGiveUpError`, emits `MovaErrorEvent`, resets any leftover `state.buffering` to false and pauses the kernel (an offline live source does not keep reconnecting in the background). The "retry" in the error layer goes through `reload()`, opening a brand-new session from the primary address.
- A retry/failover is a kernel reload, **not a new session**: it does not pass the `beforeOpen` interceptor, does not emit `MovaSourceChange`, and does not touch the QoE session; `MovaSourceChange`/`MovaReady` are emitted only once per `open()`. For a VOD source that had shown a picture before failing, playback resumes to the failure position after the reload.
- **`alternatives` are ignored when `recovery` is off** (failure detection is provided by recovery), and an `open()` failure is still thrown to the caller as before; once enabled, an `open()` failure emits `MovaPlayFailure(openThrew)` and retries instead of throwing.
- **Per-source libmpv / ffmpeg options**: `MovaSource(mpvOptions:, demuxerOptions:, whepMediaTimeout:)`. `mpvOptions` maps mpv option names to values (such as `{'cache': 'no'}`), and `demuxerOptions` is merged into `demuxer-lavf-o`; both are applied before that source loads and restored when the next source loads, so they do not leak into other sources, and options mpv does not accept are skipped silently. `demuxer-lavf-o` is merged into the existing list key by key (mpv's `change-list add`); on restore only the keys added by this source are removed and keys it overrode get their original values back, so media_kit's default `protocol_whitelist`, `allowed_extensions` and so on are always kept. A WHEP live source can simply write `whepMediaTimeout: Duration(seconds: 3)` (converted to `media_timeout` in microseconds, effective only for `whep...` addresses, with an explicit `demuxerOptions['media_timeout']` taking precedence), so that a publisher drop is judged as failed sooner and reconnected sooner:
  ```dart
  const MovaSource(
    'whep+http://host:8889/x/whep',
    type: MovaStreamType.live,
    whepMediaTimeout: Duration(seconds: 3),
  );
  ```
- The duration of a live stream keeps growing, so `MovaDurationChange` (and `state.duration`) is throttled for live sources by `MovaLiveOpts.durationStep` (default 2s): changes smaller than one step are not reported; `Duration.zero` restores reporting every change. VOD is unaffected.
- mova has no hook to sort or filter alternative addresses: the sort criteria (such as rendition names) and whether a protocol can play (depends on the libmpv build you use) are only known to the host, so pass them in already sorted. `MovaSource.pick` only cleans: trims whitespace, drops empty strings, de-duplicates, and keeps order.

## Event delivery, frame capture and capability lookup

- **Event delivery**: a normal `Mova` delivers events synchronously after updating state, so when a listener receives an event, `state` is consistent with the payload;
  nested events are queued for delivery. If a callback such as `MovaDone`/`MovaSourceChange` synchronously switches source, the old source's follow-up logic
  (live end, keepAlive downgrade, Ready, quality probing) no longer runs; an `open()` rejected by `beforeOpen` does not affect an in-flight quality switch or recovery.
- **Frame capture**: the optional capability `IMovaFrameCapture` (not on `IMovaApi`) is implemented by both the normal and the cutover player.
  While playing/paused it retries for up to 2 seconds in total to get a non-empty image, and returns `null` on timeout, no video, source change or dispose; it does not play and does not seek.
- **Capability lookup**: `movaCapabilityOf<T>(api)` returns the capability implemented by `api` itself or by the player currently in effect inside a cutover, and `null` if unsupported;
  query again after a cutover.

```dart
final png = await movaCapabilityOf<IMovaFrameCapture>(api)?.screenshot();
final keepAlive = movaCapabilityOf<IMovaKeepAlive>(api);
```

## Auto pause (optional)

Pauses automatically when scrolled out of the viewport, switched to another tab, covered by another page, or when the app goes to the background, and resumes when it comes back:

```dart
MovaView(source: src, autoPause: const MovaAutoPauseOpts())
// or wrap manually: MovaAutoPause(api: mova, child: MovaPlayer(api: mova))
```

- Uses only the Flutter SDK, with no third-party visibility package: scroll viewport (computes the visible fraction along ancestor `Scrollable`s, `minVisibleFraction` is adjustable), `TickerMode` (`go_router`'s `indexedStack` wraps inactive branches in `Offstage + TickerMode(enabled:false)`), `ModalRoute.isCurrentOf`, and `AppLifecycleListener`.
- Dialogs / BottomSheets count as "covered" (a dialog is a translucent route, so when it sits on the same navigator `isCurrentOf` is false).
- **Fullscreen / PiP / in-app mini window are exempt from page-occlusion and visibility pausing** (the background still follows the guard config). `inactive` (pulling down the notification shade, Android system PiP) does not pause, but first records "was it playing": on Android, going to the background may first deliver a playback-paused observation, and without recording it would be misjudged as "was not playing in the first place" and would not resume on return to the foreground.
- Live resume: the pause point may already have slid out of the HLS window and the HTTP-FLV connection may have dropped, so after being hidden for at least `liveResumeGrace` (default 3s) it calls `backToLiveEdge()` and plays by default, and under 3s it just does a normal `play()`; `liveResume: MovaLiveResume.resume` always does a normal resume.
- **Translucent routes pushed on an outer navigator** (typically a card placed in a `go_router` shell branch while a dialog/transparent page is shown by the root navigator) are not visible to `ModalRoute.isCurrentOf`, so pass `routeObservers`: **one `RouteObserver<ModalRoute<dynamic>>` per navigator** (Flutter does not allow one `NavigatorObserver` to be attached to two navigators, which fails an assertion in debug), and pass all of them to the guard. Opaque outer routes (ordinary full pages) are already noticed through `TickerMode` after the transition ends, and need nothing.
- `MovaFeedPlayer` has a built-in guard for the whole feed (disable with `autoPause: null`), so do not wrap a guard around every page; page-flip exclusivity is managed by the pool.
- A `MovaPlayer` with a video render surface handles background pausing through `api.pause()` by default and does not resume on its own when returning to the foreground; a `MovaAutoPause` with the same API in an ancestor can take over (for example `background: false`). The old background pause came from media_kit's `Video.pauseUponEnteringBackgroundMode` default; that default path is turned off, and surface reclamation is not treated as the only proven cause. audioOnly has no video surface and is unaffected by this fallback.

## keepAlive while hidden (optional)

When a live card is hidden (switched tab, scrolled off screen, covered by a route), besides pausing you can put it on "keepAlive": no picture and no sound, but **the stream connection and the live progress are kept**. When shown again only video decoding needs to be restored, without going through the whole "re-request -> first segment -> decoder -> first frame" chain again.

```dart
// Handled automatically by the guard (recommended; the default is still pause)
MovaView(
  source: live,
  autoPause: const MovaAutoPauseOpts(hiddenMode: MovaHiddenMode.keepAlive),
)

// Or imperatively: the player implements IMovaKeepAlive, and IMovaApi itself gains no members
final api = createMova();
if (api is IMovaKeepAlive) {
  await api.setKeepAlive(true);   // card slides away
  await api.setKeepAlive(false);  // back on screen
}
```

- **Mechanism**: if the stream has audio -> turn off video decoding and mute (the audio chain is the clock, and the demuxer keeps chasing the edge); if the stream has no audio -> keep decoding and only mute; VOD, going to the background, unknown media info, and HLS (default) -> fall back to a normal pause. KeepAlive lasts at most `MovaKeepAliveOpts.maxDuration` (default 30s), then falls back to pause automatically.
- **It saves no network traffic**: during keepAlive it keeps downloading at full speed; what is saved is decoding/rendering/battery. On cellular networks, switch back to `hiddenMode: MovaHiddenMode.pause`; **when there are several live cards in a list, enable keepAlive only for the primary card**, since every keepAlive card downloads at full speed.
- **By default it only takes effect for live streams such as FLV**: HLS/DASH pause by default (`MovaKeepAliveOpts.allowHls: false`); after switching back to `vid`, whether the demuxer reads back from the network and whether problems appear after the live window slides away have not been tested on real devices yet.
- **Resuming waits for a keyframe**: typically 0 to 1 GOP, with no reconnect. `MovaKeepAliveResume.elapsed` records the time from the wake-up call to the first new frame, and `signal` says what triggered the landing.
- **Always pause when going to the background**: the guard downgrades keepAlive to pause when the app goes to the background (the system throttles network and CPU). Imperative users must `pause()` themselves when going to the background.
- **Only `setKeepAlive(false)` can wake it**: a programmatic `play()` during keepAlive (ads, playlist) does not make an invisible card make sound. If `open()` switches source while a keepAlive request exists, the new source loads paused, and after the first frame lands it tries to enter keepAlive again if it should still be playing.
- Tuning is in `MovaOpts.keepAlive` (`MovaKeepAliveOpts`: `maxDuration`/`silentStreams`/`allowHls`/`resumeTimeout`/`liveResumeGrace`); these options only tune it, and there is no on/off switch: keepAlive code does not run until you call `setKeepAlive`.
- State and events: `MovaState.keepAlivePhase` (`off`/`holding`/`fallback`/`resuming`), `MovaKeepAliveChange`, `MovaKeepAliveResume`. With a poster (`poster`), the poster covers instantly during keepAlive and resume, and fades out after the resume lands.
- During keepAlive QoE keeps counting watch time and stalls (the collector does not know about keepAlive yet).
- In host widget tests, `MovaTestKernel`'s `hasAudio` (default `null` = media info unknown, which falls back to pause) and `fileFormat` can script keepAlive scenarios.
- Verification page: [example/lib/main_keep_alive_verify.dart](https://github.com/icodejoo/dart-labs/blob/main/mova/example/lib/main_keep_alive_verify.dart); partially measured on Windows, Android CP1 is in the record above, and that does not mean CP2/CP3 passed.

## Widget tests

In a host's widget tests, `createMova()` by default constructs a real media_kit `Player` and reports `MediaKit.ensureInitialized must be called`. Use the testing entry to swap in a programmable kernel:

```dart
import 'package:mova/testing.dart';

setUp(MovaTesting.useTestKernels);
tearDown(MovaTesting.reset);

testWidgets('poster fades out after the first frame', (t) async {
  await t.pumpWidget(MaterialApp(home: MovaView(source: src, poster: cover)));
  final k = MovaTesting.lastKernel!;
  k.emitSize(1280, 720);
  k.emitRestart();            // MovaState.rendered -> true
  await t.pump();
});
```

- `MovaTestKernel` records calls and can push arbitrary kernel signals (`emitPlaying/Buffering/Position/Size/Restart/EndFile/...`); `nativeRestartAvailable` defaults to `false`, so the buffering/position fallback lands immediately and leaves no pending grace timer.
- While installed, all platform ports are empty implementations and thumbnails use only the in-memory cache, so you will not hit the platform channels of `path_provider`/`screen_brightness`; an explicitly passed `kernel:`/port still takes priority.
- The testing entry is **not** in the main barrel and is imported only through `package:mova/testing.dart`, so it does not show up in the completion list of app code.

## Scrub preview

```dart
final mova = createMova(
  options: const MovaOpts(
    preview: MovaPreviewOpts(
      network: MovaPreviewNet.wifiOnly, // default; always / never are also available
      frameWidth: 160,                    // thumbnail width
      bucket: Duration(seconds: 10),      // bucket size, the same bucket reuses one image
      memMaxEntries: 40,                  // in-memory LRU entry cap
      diskMaxBytes: 64 * 1024 * 1024,     // disk LRU byte cap
    ),
  ),
);
```

The thumbnail track is expected at `<video address>.vtt`; to change that, use `vttUrl` or `vttUrlResolver`.
To replace the whole bubble:

```dart
MovaPlayer(
  api: mova,
  uiKit: MovaDefaultUiKit(
    patches: [MovaPatch.replace(MovaPreviewComponent.componentName, MyBubble())],
  ),
)
```

## Live time-shift

```dart
// DVR: no source change, seek inside the server's sliding window
final mova = createMova(
  options: const MovaOpts(
    live: MovaLiveOpts(seekMode: MovaLiveSeekMode.dvr),
  ),
);

// Time-shift: on seeking, re-open the source with your own URL scheme
final mova = createMova(
  options: MovaOpts(
    live: MovaLiveOpts(
      seekMode: MovaLiveSeekMode.timeshift,
      dvrWindow: const Duration(hours: 2),
      urlBuilder: (uri, behind, now) =>
          '$uri?begin=${now.subtract(behind).millisecondsSinceEpoch}',
    ),
  ),
);
```

The default is `off` (seeking disabled); `timeshift` mode has no effect without a `urlBuilder`;
`windowResolver` is for the case where the server declares the window out of band.

## Danmaku (optional)

`MovaDanmakuItem` is a pure data value (text / trigger position / optional color) used together with
`MovaDanmakuTrackComponent` to render scrolling danmaku; the core layer only defines the data and never renders:

```dart
final items = [
  MovaDanmakuItem(text: 'Here it comes', time: const Duration(seconds: 30)),
  MovaDanmakuItem(text: 'Awesome', time: const Duration(seconds: 45), color: 0xFFFF5555),
];
```

How exactly to feed a danmaku stream into `MovaDanmakuTrackComponent` depends on your UI kit/component tree;
see the "Custom UI kits" section.

## Playlist (optional)

`MovaPlaylist` drives sequential playback on top of `IMovaApi`: it tracks the current index, navigates between items through
`IMovaApi.open`, and can optionally auto-advance. Pure Dart (no Flutter dependency), constructed and
injected by the host, and never held by the player:

```dart
final playlist = MovaPlaylist(mova);
await playlist.jumpTo(0); // open the first item
```

Initial values (item list / initial index / auto-advance) come from `MovaOpts.playlist`
(`MovaPlaylistOpts`). When combined with ads they share a session: switching episodes loads the matching schedule, and
auto-advance waits for the content and all post-roll breaks to finish (requires `playlist.enabled: true`):

```dart
final ads = MovaAds(api, cutover: api); // api is the same MovaCutover
final playlist = MovaPlaylist(api, ads: ads);
await playlist.jumpTo(0);
```

New code can also use `MovaSession` directly (borrows the player, `autoAdvance` is off by default):

```dart
final api = createMova();
final session = MovaSession(api, items: episodes, autoAdvance: true);
final outcome = await session.jumpTo(0);
// The adBreaks of each item in episodes override the ads for that episode; null falls back to api.options.ads.breaks.
// outcome == MovaLoadOutcome.accepted means the first segment was accepted, which does not guarantee a first frame.
```

## Immersive Feed playback (optional)

`MovaFeedPlayer` is a bilibili/TikTok-style "swipe up for the next video" vertical feed widget, backed by
`MovaFeed` + `MovaFeedPool`: every hot page has its own independent player instead of all pages
sharing one, so a swipe up switches between two pictures that are already playing (no black flash, no stale frame).

```dart
MovaFeedPlayer(
  movaFactory: createMova,             // MovaFactory: how to build each player in the pool
  loader: (index) async {                      // MovaFeedLoader: resolve an item by index, return null at the end
    if (index >= myFeedUrls.length) return null;
    return MovaFeedItem(source: MovaSource(myFeedUrls[index]));
  },
)
```

`MovaFeedItem` is the data value of a single feed item (source + social fields such as likes/comments/shares);
`IMovaFeedPrefetcher` (default `MovaNetworkWarmFeedPrefetcher`) warms the network path of neighboring items ahead of time,
and the warm-up depth is host-configurable through `prefetchDepth`. The social interaction UI components are in
`ui/components/feed_social.dart` (like/comment/share buttons, avatar, info bar, all addable/removable through the UI kit
patch system). See the "Feed" chapters of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) for details.

The host can hold a `MovaFeedPlayerCtrl()`, pass it as `MovaFeedPlayer(ctrl: ctrl, ...)`,
query through `feed`, `activeIndex`, `activeApi`, and call `jumpToPage(index)`, `pause()`, `play()`.
When unbound, queries return null and commands do nothing; while an open is in flight the current API can still be controlled; the `MovaFeedPlayerCtrl` is released by the host, and the pool and players are released by the widget.
`autoPause`/`routeObservers` control the guard of the whole feed, and `errorBuilder(context, index, error, retry)`
can customize the UI for single-page loading, open rejection/exception and failures while running; an explicit retry does not affect adjacent pages.

## Speech-to-subtitles / STT (optional)

`IMovaApi.stt` (`IMovaSttApi`) exposes the recognized subtitle stream: components only listen to `cues`/`current` and call
`start()`/`stop()`, while audio extraction and recognizer calls are hidden behind the core layer. The recognizer itself is injected through the
`IMovaStt` port (default `MovaNoopStt`; without a recognizer the capability silently does nothing):

```dart
mova.stt.cues.listen((cue) => print('${cue.start}: ${cue.text}'));
await mova.stt.start();
```

The built-in `MovaSubtitleOverlayComponent`/`MovaSubtitleButtonComponent` render the subtitle track and the toggle
button; `formatSrt()` exports a list of recognized `MovaSttCue`s as a standard `.srt` file. The directories for model and
subtitle files are injected through `IMovaSttModelDirProvider`/`IMovaSttSubtitleDirProvider`, and
default to the system temp directory (`platform_impl/stt_model_dir_impl.dart` and so on).

Model download is an experimental implementation with **no checksum verification**. To enable it you must inject a host-owned recognizer through
`createMova(options: MovaOpts(stt: MovaSttOpts(enabled: true, recognizer: recognizer)))`;
mova ships no recognizer; for the selection see the [08-04 decision](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/notes/2026-08-04-stt-recognizer-decision.md).

## Ad orchestration (optional)

`MovaAds` plays pre/mid/post-roll breaks on a schedule and can model real ad-business timing. **Apart from ad-slot duration,
every new option is off by default or leaves existing behavior unchanged.**

```dart
// Deferred content-source resolution: the content address is only resolved after the pre-roll ends (short-lived signed URLs).
await ads.loadDeferred(() async {
  final play = await playbackService.requestPlayback(videoId); // host business service, not IMovaApi
  return MovaSource(play.url, title: play.title);
});
ads.contentError.listen((error) {
  // The host shows a retry entry; this also covers content open failures and terminal errors while running.
});

// Ad-slot duration and countdown: duration is decoupled from the asset duration, delay only applies to mid-roll.
MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://cdn/ad.mp4'),
  offset: const Duration(seconds: 600),
  delay: const Duration(seconds: 3),     // "ad plays in 3 seconds"; content keeps playing meanwhile
  duration: const Duration(seconds: 15), // the purchased slot is 15 seconds, regardless of the asset length
  skippableAfter: const Duration(seconds: 5),
);

// Wait until the ad is really ready before cutting in: by default pre does not wait / mid waits / post does not wait.
MovaAdOpts(
  waitForAdReady: const MovaAdWaitByKind(post: true), // post-roll waits too
  adReadyTimeout: const Duration(seconds: 5),
  notReadyAction: MovaAdNotReady.hardCut,             // hard cut if it never gets ready
);

// Load-failure fallback.
MovaAdOpts(
  failPolicy: const MovaAdRetrySkip(maxRetries: 0), // default: no retry, skip this one
  loadTimeout: const Duration(seconds: 8),          // how long without a first frame counts as a failure
);
```

Key points:

- The ad-slot duration, skipping and mid-roll delay use a pausable clock: no time is billed and no countdown is consumed while paused; the first-frame load timeout still uses an independent wall clock and does not depend on the media timeline.
- `contentError` merges resolution failures, content open/switch exceptions and terminal errors while running (with recovery on, it waits for giveUp); host rejections and stale loads do not report errors. On failure it goes back to idle, does not emit `contentEnded`, and does not advance episodes automatically; `contentEnded` is only emitted after the content and all post-roll breaks have ended.
- `duration` must be longer than `skippableAfter`, otherwise `assertValid()` fails in debug.
- Readiness waiting only takes effect when the host has wired in `IMovaCutover` and `MovaCutoverOpts.enabled` is `true`; both are off by default.
- The failure fallback policy `IMovaAdFailPolicy` returns `retry` / `skipBreak` / `abandonPod`, and the built-in `MovaAdAbandonPod` abandons the whole pod on the first failure.

For detailed behavior rules, the state machine and real-device verification progress, see the "Ad orchestration enhancements" section of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) and
[doc/plans/2026-09-16-ad-cutover-enhancements.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/plans/2026-09-16-ad-cutover-enhancements.md).

## Seamless cutover (optional)

`MovaCutover` is itself a `IMovaApi`: behind one stable render surface it holds the player currently in effect and
an optional, warming shadow player; once the shadow is ready the two are cut over atomically, with no remount and no black screen.
It is **off** by default (`MovaCutoverOpts.enabled` is `false`), in which case it is a pure pass-through proxy whose behavior is identical to using
`Mova` directly.

```dart
final api = MovaCutover(
  movaFactory: () => createMova(
    options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)),
  ),
);
final ads = MovaAds(api, cutover: api); // pass the same instance as cutover
runApp(MovaPlayer(api: api));
```

Once `MovaAds` is given the `cutover:` parameter, while an ad plays it warms the content in the background according to the trigger policy configured by `MovaCutoverOpts`
(default `MovaLeadWarm`: start warming 2 seconds before the end, no warming for ads shorter than 5 seconds), and cuts back to the content atomically as soon as the ad
ends. See the "Seamless cutover" section of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) and
[doc/plans/2026-09-16-seamless-cutover.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/plans/2026-09-16-seamless-cutover.md).

## In-app mini window (`MovaMini`, optional)

Without relying on any system PiP API, the picture shrinks from the page into a draggable floating window, with no re-decoding and no black screen. It is neither
system-level PiP (`IMovaApi.enterPip()`) nor a system overlay window that needs the `SYSTEM_ALERT_WINDOW` permission:
it is drawn inside Flutter's own paint tree, never leaves the app, and needs no permissions on any of the four platforms.
It is **off** by default (`MovaMiniOpts.enabled` is `false`).

There are two ways to mount it; use whichever fits:

```dart
// Style A - in-page floating: floats inside the current page and disappears when the page is popped.
final mini = MovaMini();
await mini.showInPage(context, api);

// The page's dispose() must call hide() or close() once:
@override
void dispose() {
  if (mini.isShowing(api)) mini.hide();
  super.dispose();
}
```

```dart
// Style B - persistent across routes: push/pop any number of levels and the window stays on top.
final mini = MovaMini(); // built at the app root, outside any route

MaterialApp(
  builder: (context, child) => MovaMiniHost(mini: mini, child: child!),
  home: const HomePage(),
)

// Tapping "shrink" on the playback page:
await mini.show(api);
Navigator.of(context).pop();   // the player is unaffected, the picture keeps playing in the mini window
```

**Mutually exclusive with fullscreen/system PiP**: during system PiP `setMini(true)` is rejected and `MovaMini.show` revokes the handoff accordingly;
entering fullscreen first collapses the mini window.

**Who disposes the player**: mova's convention is "the host owns the player": `MovaPlayer`/`MovaMini`
never dispose the `api` passed in. Calling `api.dispose()` in the page's `dispose()` would kill the player playing in the
mini window at the moment of handoff; use `MovaMini.isShowing(api)` to check before `dispose`.

A usage example is in [example/lib/main_coverage_api.dart](https://github.com/icodejoo/dart-labs/blob/main/mova/example/lib/main_coverage_api.dart)
(`flutter run -t lib/main_coverage_api.dart`). See the "In-app mini window (MovaMini)" section of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) for details.

## Audio-only mode (`audioOnly`, optional)

If your app plays both video and pure audio, the audio path should not pay for video resources.
A player built with `audioOnly: true` creates no video pipeline at all: the default kernel skips `VideoController`,
and the frame-extraction fallback is not wired either. `renderHandle` is then `null`, and `MovaPlayer` renders a black placeholder, or any
`surface` you pass it (cover art, waveform, lyrics). It is **off** by default, and when off the behavior is byte-for-byte identical to not passing this
parameter.

```dart
final mova = createMova(
  audioOnly: true,
  options: const MovaOpts(preview: MovaPreviewOpts(enabled: false)), // there are no frames to preview
);
runApp(MovaPlayer(api: mova, surface: CoverArt(url: coverUrl)));
```

For playback that keeps going with the screen off plus system media controls (lock screen/notification bar, headset buttons, audio focus, gapless, playlists),
use `just_audio` + `audio_service`; to just put a piece of audio in a foreground UI, this mode is enough, with no need to add
another plugin. For measured memory/CPU gains see the "Audio-only mode" section of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) and
[doc/notes/2026-09-16-audio-only-feasibility.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/notes/2026-09-16-audio-only-feasibility.md).

## Telemetry and QoE enhancements (optional)

`createMova(reporter: ...)` takes a `IMovaReporter` (wrap a callback with `MovaCallbackReporter`, see "State,
events and custom components" below); by default it only forwards the UI action stream. Setting `MovaOpts.report` to
`MovaReportOpts(qoe: true)` also reports four standard metrics: startup time (`firstFrame`/
`startupFail`), stall count and duration (`rebuffer`), playback failures marked fatal or non-fatal
(`MovaErrorEvent` gains `fatal`/`code`), and session start/end (`sessionStart`/`sessionEnd`,
with `reason` being one of `ended`/`stopped`/`failed`/`abandoned`). It is **off** by default,
and when off the event stream is byte-for-byte identical to not passing `report`. When a VOD session ends at EOF but the completion rate is below
`MovaReportOpts.truncatedBelow` (default `0.9`, `<=0` turns it off), it is treated as truncated: a fatal
`MovaErrorEvent` (`code: truncated`) is emitted first and `sessionEnd.reason` is recorded as `failed` instead of `ended`.

```dart
final mova = createMova(
  options: const MovaOpts(report: MovaReportOpts(qoe: true)),
  reporter: MovaCallbackReporter((e) {
    // Forward it to any analytics SDK. mova only standardizes events; it never sends, batches or schedules anything itself.
    myAnalytics.track(e.name.value, {...e.params, 'sessionId': e.sessionId});
  }),
);
```

Since 0.2.x `MovaReportName` is a const value class, not an enum (built-in names plus `MovaReportName.custom`
for your own names; `==`, `hashCode` and use as `Map`/`Set` keys work as before). See the CHANGELOG for the breaking changes. Signals prefer
libmpv's native capabilities (`paused-for-cache` as the real stall signal, `video-bitrate`/`cache-speed`/
dropped-frame counts, error classification from mpv log prefixes), and where necessary (exact TTFF landing, session end reason) subscribe to native mpv events through a self-built
`dart:ffi` weak client (the `media_kit` dependency stays at the pub.dev version, no git commit needed). See the
"Telemetry and QoE" section of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md) and
[doc/plans/2026-09-29-telemetry-enhancement.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/plans/2026-09-29-telemetry-enhancement.md).
**TTFF, stalls, the four end states and the `qoe: false` off state have been verified on Android real devices and Windows desktop; iOS/macOS are not verified (when native event subscription fails, it silently degrades to buffering edges and timing inference).**

## Platform ports

A bare `Mova()` constructor uses noop ports by default (for pure-Dart unit tests); application code should use `createMova()` from
`lib/src/platform_impl/wiring.dart` instead, which wires
`MovaBrightness()` / `MovaPip()` / `MovaOrient()` by default,
plus the preview-related ports (real implementations of the thumbnail directory / frame extractor / network probe).

### Volume port

The right-side vertical swipe adjusts volume through `IMovaVolume`. On **Android**, `createMova()` wires
`MovaSystemVolume()` by default (native `AudioManager`, adjusting the **system media volume**, linked with the hardware volume keys,
with no third-party dependency); **iOS** (the system forbids code from changing volume) and **desktop** fall back to the player's own volume.

You can take over on any platform by passing a `MovaCallbackVolume`, whose callback receives the target percentage (0-100)
and decides how to apply it (for example with your own system-volume solution):

```dart
final mova = createMova(
  options: options,
  volume: MovaCallbackVolume((percent) => myAudio.setSystemVolume(percent)),
);
```

Without a callback, Android uses the built-in system volume and other platforms use the player volume, with no extra code needed.

### Brightness and orientation ports

The left-side vertical swipe adjusts brightness through `IMovaBrightness` (`createMova()` wires
`MovaBrightness()` by default); forcing landscape/portrait goes through `IMovaOrient` (wired to
`MovaOrient()` by default). Both have the same shape as `IMovaVolume`, and you can
implement the abstract class yourself and swap it in through `createMova(brightness: ..., orient: ...)`.
Where the orientation port is not needed, pass the built-in `MovaNoopOrient()` to turn it off explicitly; the brightness port currently
has no built-in empty implementation, so when you do not need it, implement an empty `IMovaBrightness` yourself.

### Desktop true fullscreen

`MovaOrient` only handles orientation locking / immersive system UI on mobile; desktop platforms
(Windows/macOS/Linux) have no "true fullscreen" here (stretching the OS window over the screen and removing the title bar),
so `setFullscreen(true)` has no visible effect on desktop. mova has no window-management dependency, so
the host has to wire up true desktop fullscreen:

```dart
mova.events.listen((e) {
  if (e is MovaFullScreenChange) {
    // For example, use the window_manager package to toggle real OS-window fullscreen.
    windowManager.setFullScreen(e.value);
  }
});
```

The `MovaFullScreenChange` event is emitted on every `setFullscreen()` call and has nothing to do with
`IMovaOrient`; you do not need to implement the whole `IMovaOrient` interface, just listen to the event stream.

## State, events and custom components

`MovaState` (cumulative snapshot such as `playing`/`duration`/`quality`), `MovaProg` (high-frequency progress
fields: `position`/`buffer`) and `MovaUiState` (pure UI state such as HUD/lock) are three kinds of read-only state;
`IMovaApi.events` is the stream of discrete events (the `MovaEvent` sealed class family, with over thirty kinds such as `MovaPlay`/`MovaSeeked`/
`MovaQualityChange`/`MovaPipChange`/`MovaCutoverChange`/`MovaErrorEvent`;
see `lib/src/core/events/events.dart` for the full list).

When writing a custom component (`extends MovaComponent`), the two ways of reading serve two scenarios:

```dart
// Stateless rebuild: read one field and rebuild automatically as it changes, with no subscription to manage.
MovaSelect<bool>(
  selector: (state) => state.playing,
  builder: (context, playing) => Icon(playing ? Icons.pause : Icons.play_arrow),
)

// Stateful side effects: do something when an event happens (show a toast, log a metric), not just rebuild.
class _MyState extends State<MyWidget> with MovaPlugin<MyWidget> {
  @override
  void initState() {
    super.initState();
    bind(api.events, (e) { if (e is MovaErrorEvent) showToast(e.error); }); // unsubscribes automatically on dispose
  }
}
```

`MovaPlugin` adds only two members, `api` (a stable handle) and `bind` (a lifecycle-safe subscription),
so there is little room for name clashes.

## Built-in UI kits

Besides `MovaDefaultUiKit`, ready-made UI kits are built in; pass one to `MovaPlayer.uiKit` to switch:

```dart
MovaPlayer(api: mova, uiKit: MovaBilibiliUiKit()); // bilibili-like style (not const: built-in patches are joined through static final)
MovaPlayer(api: mova, uiKit: const MovaMinimalUiKit()); // picture only (no gestures, no control bar)
```

`MovaBilibiliUiKit` is a patched variant of `MovaDefaultUiKit`, and you can stack your own `patches` on top.
`MovaDouyinUiKit` (double-tap like + single-tap pause gesture layer) is a **single-page feed UI kit**; its constructor needs
`item`/`feed`/`index`/`likeNotifier`, it is created page by page by `MovaFeedPlayer`, and it cannot be passed directly to a standalone `MovaPlayer`.

## Custom UI kits

Three levels of customization, from shallow to deep:

1. **Patch level**: `MovaDefaultUiKit(patches: [...])` - add/remove/replace/rewrite components and move things between existing slots.
2. **Partial override level**: `extends MovaDefaultUiKit` and override only the protected methods of one layer
   (`buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`), re-laying out that layer while reusing the others.
3. **Full implementation level**: `implements IMovaUiKit` and rewrite `components()`/`assemble()`, with layout and components fully custom.

The built-in UI kit is a three-layer skeleton: the **playback layer** (picture) + the **operable layer** (gestures / top, center and bottom bars / left and right bars, fading out together when idle,
hidden as a whole during pip/lock) + the **persistent layer** (status layer, lock overlay and the patchable `lockToggle`; when unlocked the button hides with the control bar, when locked the unlock entry is kept, and during PiP/mini the button is hidden).
The component tree is static (`components()` does not consume state), and visibility is decided reactively by each component through its own `MovaSelect`.
Slot vocabulary: `top`/`center`/`bottom`/`bottomAbove`/`overlay`/`left`/`right`/`gesture`/`hud`.

Buttons support Tab focus, Enter/Space activation, accessibility semantics and hover tooltips by default. Moving the mouse over the player brings up the control bar.
Player keyboard shortcuts are off by default; after enabling them with `MovaOpts(controls: MovaCtrlsOpts(shortcuts: true))`,
click the picture or Tab-focus the player, then Space plays/pauses, Left/Right seek ten seconds, Up/Down adjust volume, F toggles fullscreen, and Esc leaves fullscreen.
Shortcuts only act on the currently focused view and do not take over text input, lock, or PiP/mini states.

Patching or implementing `IMovaUiKit` as a whole:

```dart
// Remove the picture-in-picture button from the top bar.
// Build the component path with <ComponentClass>.componentName to avoid hand-written string typos.
const noPipUiKit = MovaDefaultUiKit(
  patches: [
    MovaPatch.remove(
      '${MovaTopBarComponent.componentName}/${MovaPipButtonComponent.componentName}',
    ),
  ],
);

MovaPlayer(api: mova, uiKit: noPipUiKit);
```

```dart
// Append a custom component to the top bar.
final withExtra = MovaDefaultUiKit(
  patches: [MovaPatch.insertAfter(
    '${MovaTopBarComponent.componentName}/${MovaFullscreenButtonComponent.componentName}',
    MyExtraButtonComponent(),
  )],
);
```

When you need a completely different layout, implement `IMovaUiKit` directly:

```dart
class MyUiKit implements IMovaUiKit {
  @override
  List<MovaComponent> components() => [/* custom component tree (static) */];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) {
    return Stack(children: [video, ...slots[MovaSlot.top]]);
  }
}
```

## Interceptors

`MovaHook` lets the host app veto or rewrite core actions (for example pre-playback authorization, seek boundary limits,
unified error reporting) without touching `Mova`/component code:

```dart
class AuthGate extends MovaHook {
  @override
  Future<bool> beforeOpen(MovaSource source) async {
    return await checkEntitlement(source.uri); // false cancels the open
  }

  @override
  Future<Duration?> beforeSeek(Duration target) async {
    return target < Duration.zero ? Duration.zero : target; // rewrite the target position
  }

  @override
  void onError(Object error, StackTrace stack) => reportToSentry(error, stack);
}

final mova = createMova(interceptors: [AuthGate()]);
```

## Project structure (for developers who want to dig deeper or contribute)

Two layers: `lib/src/core/` (capability surface / kernel wrapper with no UI dependency) and `lib/src/ui/` (component tree + UI kits + gestures,
pure Flutter widgets). `IMovaApi` is the only abstraction `ui/` may depend on, and it never reaches
`IMovaKernel` or media_kit directly. For the full layering description and the responsibilities of each module see the "Architecture layering" section of [doc/SPEC.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/SPEC.md).

## Self-built slim libmpv

For consumer-side integration and per-platform configuration, see [libmpv/README.md](https://github.com/icodejoo/dart-labs/blob/main/mova/libmpv/README.md#%E6%8E%A5%E5%85%A5%E6%8C%87%E5%8D%97%E4%BB%8E%E9%A1%B9%E7%9B%AE-readme-%E8%BF%81%E5%85%A5);
for build recipes and CI see the separate [mova-libmpv docs](https://github.com/icodejoo/dart-labs/blob/main/mova-libmpv/README.md).

## Roadmap

See [doc/ROADMAP.md](https://github.com/icodejoo/dart-labs/blob/main/mova/doc/ROADMAP.md).

## License

MIT
