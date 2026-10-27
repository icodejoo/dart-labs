// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import 'verify_auto/rerun7_coverage_new.dart' as added;
import 'verify_auto/rerun7_coverage_widgets.dart' as widgets;

/// Device-only coverage runner. Commands arrive over adb forward on 18083.
///
/// 真机验证入口，通过 adb forward 18083 接受命令，不修改库实现。
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    MovaEngine.ensureInitialized();
    runApp(MaterialApp(navigatorObservers:[widgets.coverageRouteObserver],builder:(context,child)=>MovaMiniHost(ctl:mini,child:child!),home:const CoverageHome()));
  }, (e, s) => mark('UNCAUGHT', {'error': '$e', 'stack': '$s'}));
}

final clock = Stopwatch()..start();
final screen = ValueNotifier<MovaApi?>(null);
final skin = ValueNotifier<MovaSkin>(const MovaDefaultSkin());
final mini = MovaMini()
  ..onClosed = ((a)=>mark('MINI_CLOSED',snapshot(a)))
  ..onTapContent = ((a)=>mark('MINI_TAPPED',snapshot(a)));
final rebuild = ValueNotifier<int>(0);
final widgetMode=ValueNotifier<bool>(false);
MovaFit? declaredFit;
bool poster = false;
bool customSurface = false;
String status = 'idle';
MovaProg latest = const MovaProg();
final records = <Map<String, Object?>>[];
final events = <MovaEvent>[];
final progressOf=<MovaApi,MovaProg>{};

/// Writes evidence to logcat and an inspectable HTTP journal.
///
/// 将证据写入 logcat 和 HTTP 日志，时间取单调时钟。
void mark(String kind, Map<String, Object?> data) {
  final row = {'ms': clock.elapsedMilliseconds, 'kind': kind, ...data};
  records.add(row);
  print('COVERAGE ${jsonEncode(row)}');
}

/// Waits for observed conditions; deadlines are never performance evidence.
///
/// 等待真实状态，超时仅用于防挂死，不作为耗时测量值。
Future<void> until(bool Function() predicate, {int seconds = 20}) async {
  final end = clock.elapsedMilliseconds + seconds * 1000;
  while (!predicate()) {
    if (clock.elapsedMilliseconds > end) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<void> settle([int ms = 150]) => Future<void>.delayed(Duration(milliseconds: ms));
MovaSource source([String path = 'vod.mp4']) => MovaSource(
  'http://127.0.0.1:18080/$path${path.contains('?') ? '&' : '?'}t=${DateTime.now().microsecondsSinceEpoch}',
  title: 'Coverage $path',
);

/// Captures actual event payload and the snapshot seen by its subscriber.
///
/// 记录事件载荷以及订阅者接收时的状态快照。
void observe(MovaApi api) {
  api.preview.thumbs.listen((t)=>mark('PREVIEW_THUMB',{'engine':identityHashCode(api),'at':t?.at.inMilliseconds,'bytes':t?.bytes.length,'title':api.state.sourceTitle}));
  api.progress.listen((p) {latest = p;progressOf[api]=p;});
  api.events.listen((e) {
    events.add(e);
    final payload = switch (e) {
      MovaSourceChange() => {'uri': e.source.uri},
      MovaSeek() => {'target': e.target.inMilliseconds},
      MovaSeeked() => {'position': e.position.inMilliseconds},
      MovaBufferChange() => {'buffering': e.buffering},
      MovaDurationChange() => {'duration': e.duration.inMilliseconds},
      MovaFirstFrame() => {'sinceOpen': e.sinceOpen.inMilliseconds, 'signal': e.signal.name},
      MovaSizeChange() => {'width': e.width, 'height': e.height},
      MovaVolumeChange() => {'value': e.value},
      MovaBrightChange() => {'value': e.value},
      MovaRateChange() => {'value': e.value},
      MovaFitChange() => {'fit': e.fit.name},
      MovaZoomChange() => {'zoom': e.zoom},
      MovaLockChange() => {'value': e.value},
      MovaFullScreenChange() => {'value': e.value},
      MovaOrientationChange() => {'orientation': e.orientation.name},
      MovaMiniChange() => {'mini': e.mini},
      MovaPipChange() => {'value': e.value},
      MovaQualityListChange() => {'qualities': e.qualities.map((q) => '${q.label}:${q.uri}').toList()},
      MovaQualityChange() => {'quality': e.quality.label},
      MovaAbrDownShift() => {'from': e.from.label, 'to': e.to.label},
      MovaCutoverChange() => {'phase': e.phase.name},
      MovaPreviewBlock() => {'reason': e.reason.name},
      MovaSttBlock() => {'reason': e.reason.name},
      MovaErrorEvent() => {'error': '${e.error}'},
      MovaPlayFailure() => {'kind': e.fail.kind.name, 'action': '${e.action}','attempt':e.fail.attempt,'isLive':e.fail.isLive,'sourceIndex':e.fail.sourceIndex},
      MovaRecovered() => {'attempts': e.attempts},
      MovaFailover() => {'from': e.from, 'to': e.to, 'uri': e.uri},
      MovaTimeShiftChange() => {'behind': e.behind.inMilliseconds},
      MovaKeepAliveChange() => {'phase': e.phase.name, 'reason': e.reason.name, 'mode': '${e.mode}'},
      MovaKeepAliveResume() => {'elapsed': e.elapsed.inMilliseconds, 'signal': '${e.signal}'},
      _ => <String, Object?>{},
    };
    mark('EVENT', {'engine':identityHashCode(api),'event': e.runtimeType.toString(), 'payload': payload, 'state': snapshot(api)});
  });
}

Map<String, Object?> snapshot(MovaApi a) => {
  'playing': a.state.playing, 'intent': a.state.playbackIntent, 'buffering': a.state.buffering,
  'duration': a.state.duration.inMilliseconds, 'position': (progressOf[a]??latest).position.inMilliseconds,
  'size': '${a.state.width}x${a.state.height}', 'volume': a.state.volume, 'brightness': a.state.brightness,
  'rate': a.state.rate, 'fit': a.state.fit.name, 'zoom': a.state.zoom, 'locked': a.state.locked,
  'fullscreen': a.state.fullscreen, 'orientation': a.state.orientation.name, 'pip': a.state.pip,
  'mini': a.state.mini, 'rendered': a.state.rendered, 'epoch': a.state.renderEpoch,
  'sourceIndex': a.state.sourceIndex, 'keepAlive': a.state.keepAlivePhase.name,
  'quality': a.state.currentQuality?.label,
  'qualities': a.state.qualities.map((q) => '${q.label}:${q.uri}').toList(),
  'error': a.state.error == null ? null : '${a.state.error}',
  'type':a.state.type.name,'title':a.state.sourceTitle,
  'pipSupported':a.state.pipSupported,'controls':a.uiState.controlsVisible,'hud':a.uiState.hud.name,
  'previewCurrent':a.preview.current?.at.inMilliseconds,
  'timeshiftBehind':a.state.timeshiftBehind?.inMilliseconds,'liveSeekable':a.state.liveSeekable,'seekableWindow':a.state.seekableWindow.inMilliseconds,
  'hudText':a.uiState.hudText,'dragging':a.uiState.dragging,'previewAt':a.uiState.previewAt?.inMilliseconds,
};

void check(String id, bool pass, Object detail) => mark('CHECK', {'id': id, 'pass': pass, 'detail': '$detail'});

/// Single-command host; long operations run independently of the HTTP response.
///
/// 命令接收页，长任务异步执行，可持续抓取事件与截图。
class CoverageHome extends StatefulWidget {
  const CoverageHome({super.key});
  @override
  State<CoverageHome> createState() => _CoverageHomeState();
}

class _CoverageHomeState extends State<CoverageHome> {
  @override
  void initState() {
    super.initState();
    unawaited(serve());
  }

  Future<void> serve() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 18083);
    mark('SERVER', {'port': 18083,'build':'rerun7-20261027'});
    await for (final req in server) {
      if(req.uri.path=='/artifact') {
        final name=req.uri.queryParameters['name']??'';
        if(RegExp(r'^coverage-thumb-(4|8|12)\.jpg$').hasMatch(name)) {
          final file=File('${Directory.systemTemp.path}/$name');
          if(await file.exists()){req.response.headers.contentType=ContentType('image','jpeg');req.response.add(await file.readAsBytes());}
          else {req.response.statusCode=404;}
        }else {req.response.statusCode=400;}
        await req.response.close();continue;
      }
      if (req.uri.path == '/run' && status != 'running') {
        status = 'running';
        unawaited(run(req.uri.queryParameters));
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'status': status, 'records': records}));
      await req.response.close();
    }
  }

  Future<void> run(Map<String, String> args) async {
    final group = args['group'] ?? 'basic';
    mark('BEGIN', {'group': group, 'args': args});
    try {
      switch (group) {
        case 'basic': await basic(args['cutover'] == 'true');
        case 'video': await video(args);
        case 'dispose': await disposeStress();
        case 'testing': await testing();
        case 'playlist': await playlist();
        case 'new': await added.runNew(args);
        case 'widgets':
          widgetMode.value=true;await settle(200);
          await widgets.coverageWidgetKey.currentState!.command(args);
      }
      status = 'done';
    } catch (e, s) {
      mark('SCRIPT_ERROR', {'group': group, 'error': '$e', 'stack': '$s'});
      status = 'error';
    }
    mark('END', {'group': group, 'status': status});
  }

  Future<void> basic(bool cutover) async {
    events.clear();
    final reports = <MovaReportEvent>[];
    MovaEngine factory() => createMovaEngine(audioOnly: true,
      reporter: MovaCallbackReporter(reports.add), options: const MovaOpts(report: MovaReportConfig(qoe: false)));
    final MovaApi a = cutover ? MovaCutoverEngine(engineFactory: factory) : factory();
    observe(a);
    final streams = <Stream<dynamic>>[a.events, a.states, a.progress, a.uiStates];
    mark('STREAM_FLAGS',{'broadcast':streams.map((s)=>s.isBroadcast).toList(),'types':streams.map((s)=>s.runtimeType.toString()).toList(),'cutover':cutover});
    final counts = List.filled(8, 0);
    final closed = List.filled(8, false);
    final subscriptions = <StreamSubscription<dynamic>>[];
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 2; j++) {
        final n = i * 2 + j;
        subscriptions.add(streams[i].listen((_) => counts[n]++, onDone: () => closed[n] = true));
      }
    }
    check('A1.broadcast', streams.every((s) => s.isBroadcast), 'all streams broadcast cutover=$cutover');
    check('A3.audio', a.renderHandle == null, 'handle=${a.renderHandle}');
    final accepted = await a.open(source(), autoPlay: false);
    await until(() => a.state.duration > Duration.zero);
    check('A5.paused', accepted && !a.state.playbackIntent, snapshot(a));
    await a.play();
    await until(() => latest.position > const Duration(seconds: 2));
    check('A4', a.pipSupported && a.state.pipSupported, 'supported=${a.pipSupported}');
    final p0 = latest.position;
    await until(() => latest.position > p0 + const Duration(seconds: 1));
    check('A1.progress', latest.position > p0, '$p0 -> ${latest.position}');
    await a.pause(); await a.pause(); await settle();
    check('A6.pause', !a.state.playing && !a.state.playbackIntent, snapshot(a));
    await a.playOrPause(); await until(() => a.state.playing);
    await a.playOrPause(); await until(() => !a.state.playing);
    for (final sec in [5, 10, 15, 5, 10]) {
      final n = events.whereType<MovaSeeked>().length;
      await a.seek(Duration(seconds: sec));
      await until(() => events.whereType<MovaSeeked>().length > n);
      final landed = events.whereType<MovaSeeked>().last.position.inMilliseconds;
      check('A7.seek', (landed - sec * 1000).abs() < 200, 'target=${sec * 1000} landed=$landed');
    }
    await a.seekBy(const Duration(seconds: -2)); await settle();
    await a.seek(const Duration(seconds: -20)); await settle();
    check('A7.negative', events.whereType<MovaSeek>().last.target == Duration.zero, '${events.whereType<MovaSeek>().last.target}');
    for (final v in [-10.0, 0.0, 1.0, 50.0, 100.0, 110.0]) {
      await a.setVolume(v); await settle();
      mark('SAMPLE', {'name': 'volume$v', 'state': snapshot(a)});
      check('A8.clamp', a.state.volume >= 0 && a.state.volume <= 100, snapshot(a));
    }
    await a.setVolume(30);
    for (final v in [-1.0, 0.0, 0.5, 1.0, 2.0]) {
      await a.setBrightness(v);
      await settle();
      check('A9.clamp', a.state.brightness == v.clamp(0, 1), snapshot(a));
    }
    await a.setBrightness(0.5);
    for (final v in [0.5, 1.0, 1.5, 2.0, -1.0, 0.0]) {
      try { await a.setRate(v); mark('RATE', {'input': v, 'actual': a.state.rate}); }
      catch (e) { mark('RATE_REJECT', {'input': v, 'error': '$e'}); }
    }
    await a.setRate(1.5);
    a.hideControls(); check('A21.hide', !a.uiState.controlsVisible, a.uiState.controlsVisible);
    a.showControls(sticky: true); a.showHud(MovaHud.seek, text: 'coverage seek');
    a.setDragging(true, previewAt: const Duration(seconds: 5));
    await settle();
    check('A21.hud', a.uiState.dragging && a.uiState.previewAt?.inSeconds == 5 && a.uiState.hudText == 'coverage seek', '${a.uiState.hud}');
    a.setDragging(false); a.hideControls();
    const name = MovaReportName.custom('coverage');
    a.report(name, params: {'probe': 42}); a.report(MovaReportName.play, params: {'probe': 43});
    check('A22', name == const MovaReportName.custom('coverage') && name.hashCode == const MovaReportName.custom('coverage').hashCode && reports.any((r) => r.name == name && r.params['probe'] == 42), reports.map((r) => '${r.name.value}:${r.params}').toList());
    await a.stt.start(); await settle(); await a.stt.stop();
    a.preview.requestAt(const Duration(seconds: 5)); await settle(500); a.preview.cancel(); await a.preview.clear();
    final f = a.open(source('ad.mp4'), autoPlay: false);
    mark('OPEN_SYNC', snapshot(a)); await f;
    await until(() => a.state.duration > Duration.zero);
    check('A10.persist', a.state.rate == 1.5, snapshot(a));
    await a.reload(); await until(() => a.state.duration > Duration.zero);
    mark('RELOAD', snapshot(a));
    await a.backToLiveEdge();
    check('E2.disabled', events.where((e) => e is MovaCutoverChange || e is MovaKeepAliveChange || e is MovaPlayFailure || e is MovaRecovered || e is MovaFailover).isEmpty, 'count=0');
    check('C13.off', !reports.any((r) => [MovaReportName.firstFrame, MovaReportName.sessionStart, MovaReportName.sessionEnd, MovaReportName.rebuffer].contains(r.name)), 'QoE reports=${reports.length}');
    await a.dispose().timeout(const Duration(seconds: 15)); await settle();
    check('A1.closed', closed.every((b) => b), 'counts=$counts closed=$closed');
    try {await a.dispose().timeout(const Duration(seconds: 5));check('A23.doubleDispose',true,'completed');}
    catch(e){check('A23.doubleDispose',false,'$e');}
    check('A23.postOpen', !await a.open(source()), 'disposed open=false');
    for (final s in subscriptions) { await s.cancel(); }
    mark('BASIC_DONE', {'cutover': cutover, 'events': events.length});
  }

  Future<void> video(Map<String, String> args) async {
    widgetMode.value=false;
    final previous=screen.value;
    late final MovaApi a;
    if (previous == null) {
      final custom=args['style']=='custom';
      MovaEngine factory()=>createMovaEngine(audioOnly:args['audio']=='true',preciseFirstFrame: true,options:MovaOpts(mini:MovaMiniConfig(enabled:args['miniEnabled']!='false'),
        preview:MovaPreviewConfig(enabled:args['preview']=='true',network:MovaPreviewNet.always,vttUrl:'http://127.0.0.1:18084/${args['slowPreview']=='true'?'slowthumbs.vtt':'thumbs.vtt'}'),
        live:const MovaLiveConfig(seekMode:MovaLiveSeekMode.dvr,dvrWindow:Duration(seconds:12),edgeThreshold:Duration(seconds:1)),
        gesture:args['mapping']=='remap'?const MovaGestureConfig(horizontal:MovaGestureAction.volume,leftVertical:MovaGestureAction.seek):const MovaGestureConfig(),
        controls:custom?const MovaCtrlsConfig(autoHideDelay:Duration(milliseconds:800)):const MovaCtrlsConfig(),
        theme:custom?const MovaTheme(bufferingSize:60,bufferingStrokeWidth:8,bufferingColor:0xFFFF0000):const MovaTheme(),
        strings:custom?const MovaStrs(fitContain:'COVERAGE FIT',quality:'COVERAGE QUALITY'):const MovaStrs(),
        danmaku:MovaDanmakuConfig(enabled:custom,items:List.generate(8,(i)=>MovaDanmakuItem(text:'COVERAGE BULLET $i',time:Duration(seconds:i+2))))));
      a=args['cutover']=='true'?MovaCutoverEngine(engineFactory:factory):factory();
      observe(a); screen.value = a;
      await settle(500); await a.open(args['url']==null?source():MovaSource(args['url']!,type:args['live']=='true'?MovaStreamType.live:MovaStreamType.vod));
      await until(() => a.state.rendered && (args['audio']=='true'||a.state.width > 0));
    }else {a=previous;}
    final action = args['action'] ?? 'snapshot';
    switch (action) {
      case 'fit': await a.setFit(MovaFit.values.byName(args['value']!));
      case 'zoom': await a.setZoom(double.parse(args['value']!));
      case 'lock': await a.setLocked(args['value'] == 'true');
      case 'volume': await a.setVolume(double.parse(args['value']!));
      case 'brightness': await a.setBrightness(double.parse(args['value']!));
      case 'fullscreen': await a.setFullscreen(args['value'] == 'true');
      case 'orientation': await a.setOrientation(MovaOrientation.values.byName(args['value']!));
      case 'mini': await a.setMini(args['value'] == 'true');
      case 'pip': mark('PIP_RETURN', {'value': await a.enterPip()});
      case 'pause': await a.pause();
      case 'play': await a.play();
      case 'open': await a.open(args['url']==null?source(args['path']??'vod.mp4'):MovaSource(args['url']!,type:args['live']=='true'?MovaStreamType.live:MovaStreamType.vod));
      case 'openSync':
        mark('VIDEO_OPEN_BEFORE', snapshot(a));
        final pendingOpen = a.open(source(args['path'] ?? 'ad.mp4'));
        mark('VIDEO_OPEN_SYNC', snapshot(a));
        mark('VIDEO_OPEN_ACCEPTED', {'accepted': await pendingOpen});
      case 'seek': await a.seek(Duration(milliseconds:int.parse(args['value']!)));
      case 'rate': await a.setRate(double.parse(args['value']!));
      case 'backEdge': await a.backToLiveEdge();
      case 'keepAlive': await (a as MovaKeepAlive).setKeepAlive(args['value']=='true');
      case 'controls': a.showControls(sticky:args['value']=='sticky');
      case 'rebuild': rebuild.value++;
      case 'declarativeFit': declaredFit=MovaFit.values.byName(args['value']!); rebuild.value++;
      case 'poster': poster=args['value']=='true'; rebuild.value++;
      case 'surface': customSurface=args['value']=='true'; rebuild.value++;
      case 'miniPage': if(mounted) {await mini.showInPage(context,a);}
      case 'miniHost': await mini.show(a);
      case 'miniHide': await mini.hide();
      case 'miniClose': await mini.close();
      case 'miniRect': mini.setRect(const MovaMiniRect(left:30,top:90,width:180,height:110));
      case 'miniInfo':
        final r=mini.rect;
        mark('MINI_INFO',{'apiNull':mini.api==null,'showing':mini.isShowing(a),'mount':mini.mount.name,'rect':r==null?null:{'left':r.left,'top':r.top,'width':r.width,'height':r.height}});
      case 'skin':
        skin.value = switch(args['value']) {
          'bilibili' => MovaBilibiliSkin(),
          'minimal' => const MovaMinimalSkin(), 'mini' => const MovaMiniSkin(),
          'minimalError' => const MovaMinimalSkin(showError:true),
          'minimalEmpty' => const MovaMinimalSkin(showBuffering:false),
          _ => const MovaDefaultSkin(),
        };
      case 'dispose':
        screen.value = null; await settle(); await a.dispose();
    }
    if(action=='skin' && args['value']=='patch') {skin.value=MovaDefaultSkin(patches:[MovaPatch.add(MovaSlot.overlay,CoverageBadge())]);}
    await settle(400);
    if (!mounted) return;
    mark('VIDEO', {'action': action, 'state': snapshot(a), 'handle': '${a.renderHandle.runtimeType}',
      'window': {'w':View.of(context).physicalSize.width,'h':View.of(context).physicalSize.height},
      'padding': {'top':View.of(context).viewPadding.top,'bottom':View.of(context).viewPadding.bottom},
      'dpr':View.of(context).devicePixelRatio,
      'components': skin.value.components().toString()});
  }

  Future<void> disposeStress() async {
    for (var i = 0; i < 120; i++) {
      final a = createMovaEngine(audioOnly: true);
      await a.open(source(), autoPlay: i.isEven);
      await a.dispose().timeout(const Duration(seconds: 10));
      if (i % 20 == 19) mark('MEM_SAMPLE', {'round': i + 1, 'rss': ProcessInfo.currentRss});
    }
    check('A23.120', true, '120 native create/open/dispose completed');
  }

  Future<void> testing() async {
    MovaTesting.useTestKernels();
    final a = createMovaEngine();
    await a.open(MovaSource(source().uri,mpvOptions:const {'network-timeout':'7'})); await a.setBrightness(0.2); await a.setFullscreen(true);
    final pip = await a.enterPip();
    check('A33', MovaTesting.kernels.length == 1 && !pip && a.renderHandle == null, 'kernels=${MovaTesting.kernels.length} pip=$pip');
    mark('STAGED_OPTIONS',{'options':MovaTesting.kernels.single.stagedSourceOptions});
    await a.dispose(); MovaTesting.reset();
  }

  Future<void> playlist() async {
    final a = createMovaEngine(audioOnly: true, options: MovaOpts(playlist: MovaPlaylistConfig(items: [
      MovaPlaylistItem(source: source('ad.mp4')), MovaPlaylistItem(source: source()),
    ])));
    observe(a);
    final p = MovaPlaylist(a);
    await p.jumpTo(0); await p.previous();
    check('A28.start', p.currentIndex == 0 && p.hasNext, 'index=${p.currentIndex}');
    await p.next(); await p.next();
    check('A28.end', p.currentIndex == 1 && !p.hasNext, 'index=${p.currentIndex}');
    await p.previous();
    await until(() => p.currentIndex == 1, seconds: 45);
    check('A28.auto', p.currentIndex == 1, 'index=${p.currentIndex}');
    await p.dispose(); await a.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(valueListenable:widgetMode,
    builder:(context,mode,_)=>mode?widgets.CoverageWidgets(key:widgets.coverageWidgetKey):Scaffold(body: SafeArea(child: Column(children: [
    const Text('MOVA device coverage — adb :18083'),
    Expanded(child: ValueListenableBuilder<MovaApi?>(valueListenable: screen, builder: (context, a, _) => a == null
      ? const Center(child: Text('Ready')) : ValueListenableBuilder<MovaSkin>(valueListenable: skin,
        builder: (context, s, _) => ValueListenableBuilder<int>(valueListenable:rebuild,
          builder:(context,t,_)=>MovaPlayer(api:a,skin:s,fit:declaredFit,posterFade:const Duration(seconds:2),
            poster:poster?const ColoredBox(color:Colors.teal,child:Center(child:Text('COVERAGE POSTER'))):null,
            surface:customSurface?const ColoredBox(color:Colors.orange,child:Center(child:Text('CUSTOM SURFACE'))):null))))),
  ]))));
}

/// Visible proof that a host patch was assembled on the real device.
///
/// 真机中证明宿主补丁实际装配的可见标记。
class CoverageBadge extends MovaComponent {
  static const componentName='coverageBadge';
  @override
  String get name=>componentName;
  @override
  MovaSlot get slot=>MovaSlot.overlay;
  @override
  Widget build(BuildContext context,MovaApi api,List<Widget> children)=>const Positioned(top:100,left:30,child:Text('PATCH VISIBLE',style:TextStyle(color:Colors.red,fontSize:30)));
}
