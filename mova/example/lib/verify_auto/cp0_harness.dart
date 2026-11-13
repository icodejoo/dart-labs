// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'auto_kit.dart';

class Cp0NativePending implements Exception {
  const Cp0NativePending();
  @override
  String toString()=>'native properties not ready';
}

typedef Cp0Script = Future<void> Function(Cp0Harness h);

void cp0Main(String scene, Cp0Script script, {bool automatic = false}) {
  WidgetsFlutterBinding.ensureInitialized();
  Mova.ensureInitialized();
  runApp(MaterialApp(home: Cp0Page(scene: scene, script: script, automatic: automatic || kAutoRun || coverageRunsOverride != null)));
}

/// Independent pages share only recording, mounting and native readback.
class Cp0Page extends StatefulWidget {
  const Cp0Page({super.key, required this.scene, required this.script, required this.automatic});
  final String scene;
  final Cp0Script script;
  final bool automatic;
  @override
  State<Cp0Page> createState() => Cp0Harness();
}

class Cp0Harness extends State<Cp0Page> with WidgetsBindingObserver {
  final clock = Stopwatch()..start();
  final records = <Map<String, Object?>>[];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final acks = <String>{};
  final positions = <IMovaApi,Duration>{};
  Duration position(IMovaApi a) => positions[a] ?? Duration.zero;
  final videoKey = GlobalKey();
  HttpServer? server;
  IMovaApi? api;
  bool rawVideo = false;
  bool backgroundPause = true;
  Axis? outerAxis;
  PageController? pages;
  int pageIndex = 0;
  bool running = false;
  bool completed = false;
  int get runs => autoRuns();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 18083);
      server!.listen((request) async {
        if (request.uri.path == '/snapshot'&&api!=null){await native();}
        if (request.uri.path == '/ack') acks.add(request.uri.queryParameters['id']!);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'scene':widget.scene,'completed':completed,'records':records}));
        await request.response.close();
      });
      mark('SERVER', {'port':18083});
      if (widget.automatic) unawaited(start());
    });
  }

  Map<String,Object?> snapshot([IMovaApi? a]) {
    final s=(a??api)!.state;
    return {'positionMs':position(a??api!).inMilliseconds,'durationMs':s.duration.inMilliseconds,
      'playing':s.playing,'intent':s.playbackIntent,'buffering':s.buffering,
      'rendered':s.rendered,'renderEpoch':s.renderEpoch,'sourceIndex':s.sourceIndex,
      'fullscreen':s.fullscreen,'pip':s.pip,'mini':s.mini,'keepAlivePhase':s.keepAlivePhase.name,
      'fit':s.fit.name,'zoom':s.zoom,'locked':s.locked,'size':'${s.width}x${s.height}',
      'volume':s.volume,'brightness':s.brightness,'rate':s.rate,
      'timeshiftBehindMs':s.timeshiftBehind?.inMilliseconds,'windowMs':s.seekableWindow.inMilliseconds};
  }

  void mark(String kind, Map<String,Object?> values) {
    final r=<String,Object?>{'kind':kind,'us':clock.elapsedMicroseconds,'scene':widget.scene,...values};
    records.add(r);
    print('[MOVA-CP0] ${jsonEncode(r)}');
  }

  void check(String id, Map<String,Object?> numbers, {String? missing}) {
    if(missing==null&&numbers.isEmpty){missing='缺数值样本';}
    mark('EXPECT', {'id':id,'expect':'CP0 measurement present; no product threshold'});
    mark('ACTUAL', {'id':id,'numbers':numbers});
    mark('CHECK', {'id':'CP0.${widget.scene}.$id','pass':missing==null?true:null,
      'status':missing==null?'PASS':'BLOCKED','missing':missing,'numbers':numbers});
  }

  Future<T> call<T>(String method, Object? args, Future<T> Function() action) async {
    mark('CALL', {'method':method,'args':args,'state':api==null?null:snapshot()});
    try {
      final result=await action();
      mark('RET', {'method':method,'result':'$result','state':api==null?null:snapshot()});
      return result;
    } catch (e,st) {
      mark('RET', {'method':method,'exception':'$e','stack':'$st'});
      rethrow;
    }
  }

  void observe(IMovaApi a) {
    subscriptions.add(a.progress.listen((p){positions[a]=p.position;}));
    subscriptions.add(a.events.listen((e) {
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
      MovaOrientChange() => {'orient': e.orient.name},
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
      mark('EVENT', {'event':e.runtimeType.toString(),'payload':payload,'state':snapshot(a),
        if(e is MovaFirstFrame) 'sinceOpenUs':e.sinceOpen.inMicroseconds,
        if(e is MovaFirstFrame) 'signal':e.signal.name,
        if(e is MovaSourceChange) 'uri':e.source.uri});
    }));
    subscriptions.add(a.states.listen((s)=>mark('STATE',{'state':snapshot(a)})));
  }

  MovaSource source(String name, {bool slow=false, bool live=false}) => MovaSource(
    live?'http://127.0.0.1:18192/live.m3u8?t=${DateTime.now().microsecondsSinceEpoch}':
    'http://127.0.0.1:18190/$name.mp4?t=${DateTime.now().microsecondsSinceEpoch}${slow?'&slow=1':''}',
    type:live?MovaStreamType.live:MovaStreamType.vod,title:name);

  Future<void> mount(IMovaApi a, {bool raw=false, bool pause=true, Axis? axis}) async {
    api=a; rawVideo=raw; backgroundPause=pause; outerAxis=axis;
    pages?.dispose();pages=axis==null?null:PageController();pageIndex=0;
    observe(a);
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    mark('MOUNT', {'rawVideo':raw,'pauseUponEnteringBackgroundMode':pause,'axis':axis?.name});
  }

  Future<void> until(FutureOr<bool> Function() condition, {int seconds=30}) async {
    final deadline=clock.elapsedMilliseconds+seconds*1000;
    while(true) {
      var ready=false;
      try {ready=await condition();} on Cp0NativePending {ready=false;}
      if(ready){return;}
      if(clock.elapsedMilliseconds>deadline) throw TimeoutException('CP0 condition; scene=${widget.scene}');
      await Future<void>.delayed(const Duration(milliseconds:25));
    }
  }

  Future<Map<String,Object?>> native() async {
    final deadline=clock.elapsedMilliseconds+10000;
    while(true) {
      final active=api is MovaCutover?(api as MovaCutover).active:api!;
      final epoch=api!.state.renderEpoch;
      final controller=active.renderHandle as VideoController;
      final player=controller.player.platform as NativePlayer;
      final values=await Future.wait(['path','time-pos','pause','duration'].map(player.getProperty));
      final stable=api is! MovaCutover||identical((api as MovaCutover).active,active);
      if(stable&&values[0].isNotEmpty&&double.tryParse(values[1])!=null) {
        final r=<String,Object?>{'path':values[0],'timePosMs':(double.parse(values[1])*1000).round(),
          'pause':values[2],'duration':values[3],'mova':identityHashCode(active),'epochAtRead':epoch,'state':snapshot()};
        mark('NATIVE',r);return r;
      }
      mark('NATIVE_PENDING',{'properties':values,'activeStable':stable});
      if(clock.elapsedMilliseconds>=deadline){throw TimeoutException('native path/time-pos unavailable');}
      await Future<void>.delayed(const Duration(milliseconds:25));
    }
  }

  Future<void> manualAudioFocus() async {
    setState((){running=true;completed=false;});
    await release();
    final a=createMova(preciseFirstFrame:true);
    await mount(a);
    final src=source('a');
    await call('open.manualAudioFocus',src.uri,()=>a.open(MovaSource(src.uri,
      title:'音频焦点手工记录',mpvOptions:const {'loop-file':'inf'})));
    mark('MANUAL_BEGIN',{'case':'audioFocus','instructions':'来电/其他 App 放音前后请求 /snapshot 导出原生读回及事件'});
  }

  Future<void> waitPosition(int ms) async => until(() async=>(await native())['timePosMs'] as int>=ms);

  Future<void> host(String id, String action) async {
    final box=videoKey.currentContext?.findRenderObject() as RenderBox?;
    final origin=box?.localToGlobal(Offset.zero);
    final dpr=MediaQuery.devicePixelRatioOf(context);
    mark('HOST', {'id':id,'action':action,if(box!=null&&origin!=null)'rect':
      {'x':origin.dx*dpr,'y':origin.dy*dpr,'w':box.size.width*dpr,'h':box.size.height*dpr}});
    await until(()=>acks.contains(id),seconds:60);
    mark('HOST_ACK', {'id':id});
  }

  Future<void> release() async {
    if(api==null)return;
    // Keep the real surface mounted until disposal completes.
    await call('dispose', null, ()=>api!.dispose()).timeout(const Duration(seconds:15));
    for(final s in subscriptions){await s.cancel();}subscriptions.clear();
    api=null;
    if(mounted){setState((){});}
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> start() async {
    if(running)return;
    running=true;setState((){});mark('BEGIN',{'runs':runs});
    try {await widget.script(this);}
    catch(e,st){mark('ERROR',{'kindDetail':'HARNESS','error':'$e','stack':'$st'});check('harness',{},missing:'$e');}
    finally {
      try {await release();}catch(e,st){mark('ERROR',{'kindDetail':'HARNESS','error':'$e','stack':'$st'});}
      completed=true;mark('END',{'completed':true});print('CP0 AUTORUN DONE ${widget.scene}');
      if(mounted){setState((){});}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    mark('LIFECYCLE',{'value':state.name,'state':api==null?null:snapshot()});
  }

  @override
  Widget build(BuildContext context) {
    final a=api;
    Widget surface=a==null?const Center(child:Text('等待场景')):
      rawVideo?Video(controller:a.renderHandle as VideoController,
        pauseUponEnteringBackgroundMode:backgroundPause,resumeUponEnteringForegroundMode:false):MovaPlayer(api:a);
    if(outerAxis!=null) {surface=PageView(controller:pages,scrollDirection:outerAxis!,
      onPageChanged:(v){pageIndex=v;mark('PAGE',{'index':v});},
      children:[surface,const ColoredBox(color:Colors.indigo,child:Center(child:Text('Page 2')))]);}
    return Scaffold(appBar:AppBar(title:Text('CP0 ${widget.scene}')),
      body:Column(children:[SizedBox(key:videoKey,height:300,child:surface),
        Text(completed?'完成：${records.where((r)=>r['kind']=='CHECK').length} CHECK':'独立验证页；原始记录 HTTP :18083'),
        if(widget.scene=='pageview') ElevatedButton(onPressed:running&&!completed?null:manualAudioFocus,child:const Text('音频焦点手工记录（需本地源服务）')),
        if(!running) ElevatedButton(onPressed:start,child:const Text('运行验证')),
        const Expanded(child:SingleChildScrollView(child:Text('CP0 只记录基线，无产品通过线。\n音频焦点：播放时来电/其他 App 放音，再恢复，导出 HTTP 原始记录。')))]));
  }

  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);unawaited(server?.close(force:true));pages?.dispose();super.dispose();}
}
