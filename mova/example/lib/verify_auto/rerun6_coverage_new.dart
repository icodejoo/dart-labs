// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:media_kit_video/media_kit_video.dart';
// Transitive plugin readback is deliberate; the library owns this dependency.
// ignore: depend_on_referenced_packages
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';
import '../main_rerun6_coverage_api.dart' as c;

/// Tests newly introduced APIs on the native player, retaining raw readbacks.
///
/// 在原生播放器测试新增接口，并保留属性读回证据。
Future<void> runNew(Map<String, String> args) async {
  switch (args['case']) {
    case 'options': await options();
    case 'recovery': await recovery(args);
    case 'live': await live(args);
    case 'hooks': await hooks(args['cutover']=='true');
    case 'feed': await feed();
    case 'preview': await preview(args);
    case 'qoe': await qoe(args);
    case 'hls': await hls(args);
    case 'retestDispose': await retestDispose();
    case 'tls': await tls();
    case 'lifecycle': await lifecycle();
    case 'lazy': await lazy();
    case 'stt': await stt();
    case 'watchoff': await watchoff();
    case 'cutover': await cutover();
    case 'ads': await ads();
    case 'adResume': await adResume();
    case 'abr': await abr();
    case 'rerun6Weak': await rerun6Weak(args);
    case 'subtitles': await subtitles();
    case 'tlsProbe': await tlsProbe();
    case 'stallRelease': await stallRelease();
    case 'edges': await edges();
    case 'adFailure': await adFailure();
    case 'nextUp': await nextUp();
    case 'visualAd': await visualAd();
    default: throw ArgumentError('missing new case');
  }
}

/// Measures remaining boundary paths against real native engines.
Future<void> edges() async {
  final a=createMovaEngine(audioOnly:true);c.observe(a);
  final pending=a.open(c.source(),autoPlay:false);
  c.mark('OPEN_IMMEDIATE',c.snapshot(a));await pending;
  await a.seek(const Duration(seconds:7));await c.until(()=>a.state.duration>Duration.zero);
  await c.settle(300);c.mark('SEEK_LOADING',c.snapshot(a));
  await a.seekBy(const Duration(seconds:2));await c.settle(300);c.mark('SEEK_BY',c.snapshot(a));
  await a.seek(const Duration(hours:1));await c.settle(300);c.mark('SEEK_BEYOND',c.snapshot(a));
  for(final v in [-1.0,0.0,.25,.75,1.0,2.0]) {await a.setBrightness(v);c.mark('BRIGHTNESS_NATIVE',{'input':v,'state':a.state.brightness,'native':await ScreenBrightness().application});}
  var threw=false;bool? accepted;
  try{accepted=await a.open(c.source('404.mp4'));}catch(e){threw=true;c.mark('BAD_OPEN_THROW',{'error':'$e'});}
  await c.settle(500);c.mark('BAD_OPEN_RESULT',{'threw':threw,'accepted':accepted,'error':'${a.state.error}'});
  await a.dispose();
}

/// Exercises both built-in ad failure policies using a real 404 creative.
Future<void> adFailure() async {
  for(final policy in [const MovaAdRetrySkip(maxRetries:1),const MovaAdAbandonPod()]) {
    final received=<MovaAdEvent>[];
    final broken=MovaAdBreak(kind:MovaAdBreakKind.pre,source:c.source('404.mp4'));
    final good=MovaAdBreak(kind:MovaAdBreakKind.pre,source:c.source('ad.mp4'),duration:const Duration(seconds:1));
    final opts=MovaOpts(ads:MovaAdConfig(enabled:true,breaks:[broken,good],failPolicy:policy,onAdEvent:(e){received.add(e);c.mark('AD_POLICY_EVENT',{'policy':'${policy.runtimeType}','type':e.type.name,'uri':e.adBreak.source.uri,'error':'${e.error}'});}));
    final a=createMovaEngine(audioOnly:true,options:opts);c.observe(a);final ctl=MovaAds(a);
    await ctl.load(c.source());await c.until(()=>!ctl.isShowingAd && a.state.sourceTitle=='Coverage vod.mp4',seconds:30);
    c.mark('AD_POLICY_END',{'policy':'${policy.runtimeType}','events':received.map((e)=>e.type.name).toList(),'state':c.snapshot(a)});
    await ctl.dispose();await a.dispose();
  }
}

/// Leaves the real NextUp card visible long enough for adb interaction.
Future<void> nextUp() async {
  c.widgetMode.value=false;
  final a=createMovaEngine(preciseFirstFrame:true,options:MovaOpts(playlist:MovaPlaylistConfig(enabled:true,nextUpLeadTime:const Duration(seconds:10),items:[MovaPlaylistItem(source:c.source('ad.mp4'),title:'EPISODE ONE'),MovaPlaylistItem(source:c.source(),title:'COVERAGE NEXT EPISODE')])));
  final ctl=MovaPlaylist(a);c.observe(a);c.screen.value=a;
  c.skin.value=MovaDefaultSkin(patches:[MovaPatch.add(MovaSlot.overlay,MovaNextUpComponent(ctl))]);
  await c.settle(200);await ctl.jumpTo(0);await c.until(()=>a.state.rendered);await a.seek(const Duration(seconds:12));await a.pause();
  c.mark('NEXTUP_READY',{'index':ctl.currentIndex,'state':c.snapshot(a)});
}

/// Hosts the real ad chrome so adb can exercise click and skip controls.
Future<void> visualAd() async {
  c.widgetMode.value=false;
  final config=MovaAdConfig(enabled:true,breaks:[MovaAdBreak(kind:MovaAdBreakKind.pre,source:c.source('ad.mp4'),duration:const Duration(seconds:15),skippableAfter:const Duration(seconds:2),clickThroughUrl:'https://example.invalid/coverage')],onAdEvent:(e)=>c.mark('VISUAL_AD_EVENT',{'type':e.type.name,'uri':e.adBreak.source.uri}));
  final a=createMovaEngine(preciseFirstFrame:true,options:MovaOpts(ads:config));c.observe(a);c.screen.value=a;
  final ctl=MovaAds(a);c.skin.value=MovaDefaultSkin(patches:[MovaPatch.add(MovaSlot.overlay,MovaAdOverlayComponent(ctl))]);
  await c.settle(200);await ctl.load(c.source());await c.until(()=>a.state.rendered);
  c.mark('VISUAL_AD_READY',c.snapshot(a));
}

/// Reuses the subtitle assets, unmounting the video before disposing each player.
///
/// 复用字幕资产，每种格式先卸载画面再销毁播放器。
Future<void> subtitles() async {
  for(final format in ['srt','ass','vtt','movtext']) {
    final videoAsset=format=='movtext'?'assets/test_video_movtext.mp4':'assets/test_video.mp4';
    final data=await rootBundle.load(videoAsset);
    final video=File('${Directory.systemTemp.path}/coverage-sub-$format.mp4');await video.writeAsBytes(data.buffer.asUint8List());
    final p=Player();final k=MovaMpvKernel(player:p,lazyVideo:true,observeNativeEvents:false);
    final a=createMovaEngine(kernel:k);c.observe(a);c.screen.value=a;await c.settle(200);
    await a.open(MovaSource(video.path),autoPlay:false);
    final n=p.platform as NativePlayer;
    if(format!='movtext') {
      final http=HttpClient();
      final response=await(await http.getUrl(Uri.parse('http://127.0.0.1:18084/test_subtitle.$format'))).close();
      final bytes=<int>[];await for(final b in response){bytes.addAll(b);}http.close();
      final sub=File('${Directory.systemTemp.path}/coverage-sub.$format');await sub.writeAsBytes(bytes);
      await n.command(['sub-add',sub.path,'select']);
    }
    await n.setProperty('sid','1');await n.setProperty('sub-visibility','yes');await a.play();
    String text='';
    final deadline=c.clock.elapsedMilliseconds+12000;
    while(text.isEmpty&&c.clock.elapsedMilliseconds<deadline){try{text=await n.getProperty('sub-text');}catch(_){text='';}await c.settle(100);}
    c.check('F11.$format',text.isNotEmpty,'native sub-text=$text');
    c.mark('SUBTITLE_SHOT',{'format':format,'text':text,'position':await n.getProperty('time-pos'),'tracks':await n.getProperty('track-list'),'state':c.snapshot(a)});
    await c.settle(1500);c.screen.value=null;await c.settle(200);await a.dispose().timeout(const Duration(seconds:10));
  }
}

/// Suppresses startup reloads, then arms the real buffer ABR for a network stall.
///
/// 排除起播重载，随后用真实缓冲ABR观察网络卡顿。
class GatedAbr implements MovaAbrPolicy {
  final inner=MovaBufferAbr(threshold:1);
  bool armed=false;
  int resets=0;
  @override
  bool onBuffering(bool buffering)=>armed&&inner.onBuffering(buffering);
  @override
  void reset(){resets++;inner.reset();}
}

/// Throttles real HLS segment delivery and races a manual switch with ABR.
///
/// 对真实HLS分片限速，并让手动换档紧随ABR。
Future<void> abr() async {
  Future<void> throttle(bool on) async {final h=HttpClient();try{await(await(await h.getUrl(Uri.parse('http://127.0.0.1:18084/throttle/${on?'on':'off'}'))).close()).drain<void>();}finally{h.close();}}
  final policy=GatedAbr();
  final a=createMovaEngine(preciseFirstFrame:true,options:MovaOpts(abr:MovaAbrConfig(policy:policy)));
  final local=<MovaEvent>[];c.observe(a);a.events.listen(local.add);c.screen.value=a;await c.settle(250);
  try {
    await a.open(MovaSource('http://127.0.0.1:18084/master.m3u8?t=${DateTime.now().microsecondsSinceEpoch}',mpvOptions:const {'cache':'no','demuxer-max-bytes':'65536','demuxer-readahead-secs':'0'}));
    await a.loadQualities();final high=a.state.qualities.firstWhere((q)=>!q.isAuto);
    await a.switchQuality(high);await c.until(()=>a.state.rendered&&c.latest.position.inSeconds>=5,seconds:30);
    policy.inner.reset();policy.armed=true;final before=c.latest.position.inMilliseconds;
    await throttle(true);
    await c.until(()=>local.whereType<MovaAbrDownShift>().isNotEmpty,seconds:60);
    final down=local.whereType<MovaAbrDownShift>().first;
    c.mark('ABR_REAL',{'before':before,'from':down.from.label,'to':down.to.label,'resets':policy.resets,'state':c.snapshot(a)});
    policy.armed=false;await throttle(false);await a.switchQuality(high);
    await c.until(()=>a.state.duration>Duration.zero&&!a.state.buffering);await c.settle(400);
    c.check('F3.abrBackToBack',c.latest.position.inMilliseconds>=before-200,'beforeStall=$before afterSwitch=${c.latest.position.inMilliseconds}');
  }finally{await throttle(false);c.screen.value=null;await c.settle(150);await a.dispose();}
}

/// Reuses the two-epoch ad probe, reading the committed native playhead.
///
/// 复用广告两次换指判据，读回提交后的原生播放头。
Future<void> adResume() async {
  for(var run=0;run<5;run++) {
    final players=<Player>[];
    const opts=MovaOpts(ads:MovaAdConfig(enabled:true),cutover:MovaCutoverConfig(enabled:true,trigger:MovaEagerWarm()));
    MovaEngine factory(){
      final p=Player();players.add(p);
      final k=MovaMpvKernel(player:p,lazyVideo:true,observeNativeEvents:true,backendFactory:(n,address)=>createFfiMpvEventBackend(n,address,pollInDebug:false));
      return createMovaEngine(kernel:k,options:opts);
    }
    final a=MovaCutoverEngine(engineFactory:factory);c.observe(a);c.screen.value=a;await c.settle(300);
    final ctl=MovaAds(a,cutover:a);
    int? last,target,actual,readLatency;
    var epoch=0;
    a.progress.listen((p)=>last=p.position.inMilliseconds);
    a.states.listen((s){
      if(s.renderEpoch==epoch){return;}epoch=s.renderEpoch;
      if(epoch==1){target=last;}
      last=null;
      if(epoch==2){
        final started=c.clock.elapsedMilliseconds;
        unawaited((()async{final native=players.last.platform as NativePlayer;final value=await native.getProperty('time-pos');readLatency=c.clock.elapsedMilliseconds-started;actual=(double.parse(value)*1000).round();})());
      }
    });
    await ctl.load(c.source());await c.until(()=>last!=null&&last!>=4000);
    await ctl.playAdNow(MovaAdBreak(kind:MovaAdBreakKind.mid,source:c.source('ad.mp4'),skippableAfter:Duration.zero));
    await c.until(()=>a.state.renderEpoch==1);await c.until(()=>last!=null&&last!>=3000&&a.cutoverPhase==MovaCutoverPhase.ready,seconds:25);
    ctl.skip();await c.until(()=>actual!=null,seconds:20);
    final error=actual!-target!;
    c.check('F4.adResume',error.abs()<100,'run=$run target=$target nativeAfter=$actual error=$error nativeReadLatency=$readLatency epoch=${a.state.renderEpoch}');
    c.screen.value=null;await c.settle(200);await ctl.dispose();await a.dispose();
  }
}

/// Exercises the two-phase and eager cutover APIs with native audio-only engines.
///
/// 用原生仅音频引擎验证两阶段和立即切换接口。
Future<void> cutover() async {
  for(final enabled in [false,true]) {
    final made=<MovaEngine>[];
    MovaEngine factory(){final e=createMovaEngine(audioOnly:true,options:MovaOpts(cutover:MovaCutoverConfig(enabled:enabled,readyTimeout:const Duration(seconds:2))));made.add(e);return e;}
    final a=MovaCutoverEngine(engineFactory:factory);c.observe(a);
    await a.open(c.source());await c.until(()=>a.state.rendered);
    if(!enabled){
      await a.prepare(c.source('ad.mp4'));final committed=await a.commit(waitForReady:true);
      final swapped=await a.cutoverTo(c.source('ad.mp4'));
      c.check('C11.off',!committed&&!swapped&&made.length==1&&a.state.renderEpoch==0,'engines=${made.length} epoch=${a.state.renderEpoch}');
    }else{
      await a.prepare(c.source('ad.mp4'),at:const Duration(seconds:6),plan:const MovaWarmPlan(trigger:MovaEagerWarm(),pauseWhenReady:true,rate:1.5));
      await c.until(()=>a.cutoverPhase==MovaCutoverPhase.ready);
      final ok=await a.commit(waitForReady:true);await c.until(()=>a.state.renderEpoch==1);
      await c.settle(200);c.check('A24.commit',ok&&a.state.rate==1.5,'epoch=${a.state.renderEpoch} rate=${a.state.rate} position=${c.latest.position.inMilliseconds}');
      c.check('A24.retired',!await made.first.open(c.source()),'retired engine rejects open');
      final before=made.length;
      await a.prepare(c.source(),cue:const MovaWarmCue(remaining:Duration(milliseconds:500),total:Duration(seconds:2)));
      c.check('A24.short',made.length==before&&a.cutoverPhase==MovaCutoverPhase.idle,'short warm declined engines=${made.length}');
      await a.prepare(c.source(),plan:const MovaWarmPlan(trigger:MovaEagerWarm()));
      final abandoned=made.last;await a.abandon();
      c.check('A24.abandon',a.cutoverPhase==MovaCutoverPhase.idle&&!await abandoned.open(c.source()),'shadow disposed');
      await a.prepare(c.source('hang'),plan:const MovaWarmPlan(trigger:MovaEagerWarm()));
      final timed=await a.commit(waitForReady:true);
      c.check('A24.timeout',!timed&&a.cutoverPhase==MovaCutoverPhase.idle,'commit timeout returned=$timed');
      final eager=await a.cutoverTo(c.source(),rate:1);
      await c.settle(150);c.check('A24.cutoverTo',eager&&a.state.renderEpoch==2&&a.state.rate==1,'epoch=${a.state.renderEpoch} rate=${a.state.rate}');
    }
    await a.dispose();
  }
}

/// Checks all roll positions, deferred loading, click reporting and skip.
///
/// 验证前中后贴、延迟解析、点击上报和跳过。
Future<void> ads() async {
  final received=<MovaAdEvent>[];
  MovaAdBreak br(MovaAdBreakKind kind,String label,{bool? wait})=>MovaAdBreak(kind:kind,source:MovaSource(c.source('ad.mp4').uri,title:label),offset:const Duration(seconds:3),duration:const Duration(seconds:1),skippableAfter:Duration.zero,waitForReady:wait,clickThroughUrl:'https://example.invalid/coverage');
  final pre=br(MovaAdBreakKind.pre,'PRE'),mid=br(MovaAdBreakKind.mid,'MID'),post=br(MovaAdBreakKind.post,'POST');
  final config=MovaAdConfig(enabled:true,breaks:[pre,mid,post],onAdEvent:(e){received.add(e);c.mark('AD_EVENT',{'type':e.type.name,'kind':e.adBreak.kind.name,'title':e.adBreak.source.title,'error':'${e.error}','click':e.adBreak.clickThroughUrl});});
  c.check('C9.waits',!config.waitsFor(pre)&&config.waitsFor(mid)&&!config.waitsFor(post)&&!config.waitsFor(br(MovaAdBreakKind.mid,'OVERRIDE',wait:false)), 'pre=false mid=true post=false breakOverride=false');
  final a=createMovaEngine(audioOnly:true,options:MovaOpts(ads:config));c.observe(a);
  final ctl=MovaAds(a);await ctl.loadDeferred(()async=>c.source('ad.mp4'));
  await c.until(()=>received.any((e)=>e.type==MovaAdEventType.started&&e.adBreak.source.title=='PRE'));
  ctl.notifyClicked();ctl.skip();
  await c.until(()=>!ctl.isShowingAd&&c.latest.position.inMilliseconds>500);
  final manual=br(MovaAdBreakKind.mid,'MANUAL');await ctl.playAdNow(manual);
  await c.until(()=>received.any((e)=>e.type==MovaAdEventType.started&&e.adBreak.source.title=='MANUAL'));
  ctl.skip();
  await c.until(()=>received.any((e)=>e.type==MovaAdEventType.completed&&e.adBreak.source.title=='POST'),seconds:45);
  c.check('A27.rolls',[pre,mid,post].every((b)=>received.any((e)=>e.type==MovaAdEventType.started&&identical(e.adBreak,b)))&&received.any((e)=>e.type==MovaAdEventType.clicked),'events=${received.map((e)=>'${e.adBreak.source.title}:${e.type.name}').toList()}');
  await ctl.dispose();await a.dispose();
}

/// Measures lazy controller construction while immediately mounting the surface.
///
/// 测量控制器懒构造，并立即挂载渲染面。
Future<void> lazy() async {
  var made=0;
  final k=MovaMpvKernel(lazyVideo:true,observeNativeEvents:false,videoControllerFactory:(p){made++;return VideoController(p);});
  final a=createMovaEngine(kernel:k);c.observe(a);
  c.check('A3.lazyBefore',made==0,'controllers=$made');
  await a.open(c.source());await c.settle(300);
  c.check('A3.lazyOpened',made==0,'controllers=$made size=${a.state.width}x${a.state.height}');
  final handle=a.renderHandle;c.screen.value=a;
  await c.until(()=>a.state.width>0);
  c.check('A3.lazyRead',made==1 && handle!=null,'controllers=$made handle=${handle.runtimeType} size=${a.state.width}x${a.state.height}');
  c.screen.value=null;await c.settle(150);await a.dispose();
}

/// Runs one visible VOD lifecycle through natural EOF, with event assertions.
///
/// 通过自然EOF执行完整可视点播生命周期并校验事件。
Future<void> lifecycle() async {
  final local=<MovaEvent>[];
  final a=createMovaEngine(preciseFirstFrame:true);c.observe(a);a.events.listen(local.add);c.screen.value=a;
  await c.settle(300);await a.open(c.source());
  await c.until(()=>a.state.rendered && c.latest.position.inSeconds>=2);
  await a.seek(const Duration(seconds:5));await c.settle(200);await a.setRate(1.5);
  await a.setFullscreen(true);await c.settle(500);await a.setFullscreen(false);
  await a.open(c.source('ad.mp4'));await a.setRate(2);
  await c.until(()=>local.whereType<MovaDone>().isNotEmpty,seconds:35);
  c.mark('LIFECYCLE',{'events':local.map((e)=>e.runtimeType.toString()).toList(),'errors':local.whereType<MovaErrorEvent>().map((e)=>'${e.error}').toList()});
  c.check('F1',local.whereType<MovaErrorEvent>().isEmpty && local.whereType<MovaDone>().length==1,'natural done=1 errors=${local.whereType<MovaErrorEvent>().length}');
  c.screen.value=null;await c.settle(200);await a.dispose();
}

/// Runs the certificate matrix against four local HTTPS endpoints.
///
/// 对四个本地 HTTPS 端点执行证书矩阵。
Future<void> tls() async {
  final client=HttpClient();
  final response=await(await client.getUrl(Uri.parse('http://127.0.0.1:18084/ca.pem'))).close();
  final bytes=<int>[]; await for(final chunk in response){bytes.addAll(chunk);} client.close();
  final ca=File('${Directory.systemTemp.path}/coverage-ca.pem');await ca.writeAsBytes(bytes);
  for(var run=0;run<5;run++) {
    for(final verify in [false,true]) {
      for(var i=0;i<4;i++) {
        final local=<MovaEvent>[];
        final a=createMovaEngine(audioOnly:true,tlsVerify:verify,tlsCaFile:ca.path);
        c.observe(a);a.events.listen(local.add);
        try{await a.open(MovaSource('https://127.0.0.1:${18443+i}/low/index.m3u8?t=${DateTime.now().microsecondsSinceEpoch}&run=$run'));}
        catch(e){c.mark('TLS_OPEN_THROW',{'error':'$e'});}
        await c.until(()=>a.state.rendered || local.whereType<MovaErrorEvent>().isNotEmpty,seconds:18);
        final success=a.state.rendered;
        c.check('C16.matrix',success==(!verify || i==0),'run=$run verify=$verify cert=$i rendered=$success errors=${local.whereType<MovaErrorEvent>().map((e)=>e.error).toList()}');
        await a.dispose();
      }
    }
  }
}

/// Distinguishes IP-name verification from CA and nested HLS handling.
///
/// 区分IP名称校验、CA加载及嵌套HLS处理。
Future<void> tlsProbe() async {
  final client=HttpClient();final response=await(await client.getUrl(Uri.parse('http://127.0.0.1:18084/ca.pem'))).close();
  final bytes=<int>[];await for(final chunk in response){bytes.addAll(chunk);}client.close();
  final ca=File('${Directory.systemTemp.path}/coverage-ca-probe.pem');await ca.writeAsBytes(bytes);
  for(var run=0;run<3;run++) {
    for(final endpoint in ['127.0.0.1:18443','localhost:18447']) {
      for(final path in ['vod.mp4','low/index.m3u8']) {
        final p=Player();final k=MovaMpvKernel(player:p,audioOnly:true,observeNativeEvents:false,tlsVerify:true,tlsCaFile:ca.path);
        final a=createMovaEngine(kernel:k);c.observe(a);final local=<MovaEvent>[];a.events.listen(local.add);
        p.stream.log.listen((line){if(line.level=='error'||line.text.toLowerCase().contains('certificate')){c.mark('TLS_NATIVE_LOG',{'prefix':line.prefix,'text':line.text});}});
        final n=p.platform as NativePlayer;
        try{await a.open(MovaSource('https://$endpoint/$path?t=${DateTime.now().microsecondsSinceEpoch}&run=$run'));}catch(e){c.mark('TLS_THROW',{'error':'$e'});}
        await c.until(()=>a.state.rendered||local.whereType<MovaErrorEvent>().isNotEmpty,seconds:15);
        c.mark('TLS_READBACK',{'endpoint':endpoint,'path':path,'verify':await n.getProperty('tls-verify'),'ca':await n.getProperty('tls-ca-file'),'caBytes':bytes.length});
        c.check('C16.probe',a.state.rendered,'run=$run endpoint=$endpoint path=$path errors=${local.whereType<MovaErrorEvent>().map((e)=>'${e.error}').toList()}');
        await a.dispose();
      }
    }
  }
}

/// Ends a real network stall before closing the session, preserving its count.
///
/// 在关闭会话前释放真实网络卡顿，测量完整卡顿次数和时长。
Future<void> stallRelease() async {
  final reports=<MovaReportEvent>[];
  final a=createMovaEngine(audioOnly:true,options:const MovaOpts(report:MovaReportConfig(qoe:true)),reporter:MovaCallbackReporter((r){reports.add(r);c.mark('REPORT',{'name':r.name.value,'params':r.params});}));
  c.observe(a);final src=c.source('stall.mp4');await a.open(src);await c.until(()=>a.state.rendered);await c.until(()=>a.state.buffering);
  final start=c.clock.elapsedMilliseconds;await c.settle(4000);
  final h=HttpClient();final key=Uri.parse(src.uri).queryParameters['t']!;
  await(await(await h.getUrl(Uri.parse('http://127.0.0.1:18080/release?t=$key'))).close()).drain<void>();h.close();
  await c.until(()=>reports.any((r)=>r.name==MovaReportName.rebuffer),seconds:25);
  c.mark('STALL_MEASURE',{'observedBufferWindow':c.clock.elapsedMilliseconds-start});await c.settle(500);await a.dispose();await c.settle(300);
}

/// Swipes a three-engine native audio pool, including overlapping requests.
///
/// 连续切换三引擎原生音频池，包含并发切换。
Future<void> feed() async {
  final made=<MovaApi>[];
  final pool=MovaFeedEnginePool(engineFactory:(){ final a=createMovaEngine(audioOnly:true); made.add(a); return a; });
  final controller=MovaFeed(pool:pool,loader:(i) async => i<0 || i>150 ? null : MovaFeedItem(source:c.source('vod.mp4?feed=$i')));
  await controller.ensure(0); await controller.activate(0);
  for(var i=1;i<=100;i++) {
    await controller.activate(i);
    if(i%20==0)c.mark('FEED_SAMPLE',{'index':controller.activeIndex,'engines':made.length,'rss':ProcessInfo.currentRss});
  }
  await Future.wait([for(var i=101;i<=120;i++)controller.activate(i)]);
  c.check('A29.final',controller.activeIndex==120 && made.length==3,'active=${controller.activeIndex} engines=${made.length}');
  c.mark('FEED_ENGINES',{'states':made.map(c.snapshot).toList()});
  controller.dispose(); await pool.dispose().timeout(const Duration(seconds:20));
  c.check('A29.dispose',true,'controller and 3 native engines disposed');
}

/// Exercises real VTT and frame extraction paths with retained images.
///
/// 验证真实 VTT 与抽帧链路并保留图片。
Future<void> preview(Map<String,String> args) async {
  final extract=args['mode']=='extract'||args['mode']=='fallback'||args['mode']=='offline';
  final blocked=args['mode']=='blocked';
  final probe=args['mode']=='probe'?MovaConnectivityNetProbe():null;
  if(probe!=null){c.mark('NETWORK_PROBE',{'allowHeavy':await probe.allowHeavy()});}
  final memory=MovaMemoryThumbCache(maxEntries:2);
  final disk=MovaDiskThumbCache(dir:MovaFixedThumbDirProvider('${Directory.systemTemp.path}/coverage-preview-counted'));
  final cache=CountedCache(memory,disk);await cache.clear();
  final puller=CountedPuller();
  final a=createMovaEngine(audioOnly:true,extractor:extract?puller:null,probe:probe,
    options:MovaOpts(preview:MovaPreviewConfig(enabled:true,
      network:blocked?MovaPreviewNet.never:probe==null?MovaPreviewNet.always:MovaPreviewNet.wifiOnly,
      vttUrl:args['mode']=='offline'?'http://127.0.0.1:9/unreachable.vtt':'http://127.0.0.1:18084/${args['mode']=='fallback'?'missing.vtt':'thumbs.vtt'}',vttEnabled:args['mode']!='extract',extractFallback:extract,
      bucket:const Duration(seconds:2),cache:cache)));
  c.observe(a); await a.open(c.source(),autoPlay:false);
  final thumbs=<MovaThumb?>[]; a.preview.thumbs.listen(thumbs.add);
  for(final sec in [4,8,12,4]) {
    a.preview.requestAt(Duration(seconds:sec));
    if(blocked){await c.settle(500);continue;}
    await c.until(()=>a.preview.current!=null && a.preview.current!.at.inSeconds==sec,seconds:25);
    final t=a.preview.current!;
    c.mark('THUMB',{'requested':sec,'at':t.at.inMilliseconds,'bytes':t.bytes.length,'crop':'${t.crop}','peek':a.preview.peekAt(Duration(seconds:sec))!=null});
    await File('${Directory.systemTemp.path}/coverage-thumb-$sec.jpg').writeAsBytes(t.bytes);
    a.preview.cancel();
  }
  c.mark('PREVIEW_END',{'mode':args['mode'],'thumbs':thumbs.length,'current':'${a.preview.current}',
    'extractCalls':puller.calls,'writes':cache.writes,'diskHits':cache.diskHits,'memoryHits':cache.memoryHits});
  if(extract){c.check('A30.diskHit',puller.calls==3 && cache.diskHits>=1,'extractCalls=${puller.calls} diskHits=${cache.diskHits}');}
  if(!extract&&!blocked){c.check('N22.crop',cache.writes==0,'cropped VTT writes=${cache.writes}');}
  await a.preview.clear(); await a.dispose();
}

/// Counts real extraction calls while delegating to the native extractor.
///
/// 对真实原生抽帧器的调用计数。
class CountedPuller implements MovaFramePuller {
  final MovaFrameExtractor inner=MovaFrameExtractor();
  int calls=0;
  @override
  Future<Uint8List?> extract(String uri,Duration at,{required int width,required bool hwdec}) {calls++;return inner.extract(uri,at,width:width,hwdec:hwdec);}
  @override
  Future<void> release()=>inner.release();
  @override
  Future<void> dispose()=>inner.dispose();
}

/// Counts both cache levels without replacing their actual implementations.
///
/// 在保留真实两级缓存实现的前提下计数命中。
class CountedCache implements MovaThumbCache {
  CountedCache(this.memory,this.disk):inner=MovaTwoLevelCache(memory:memory,disk:disk);
  final MovaMemoryThumbCache memory;
  final MovaDiskThumbCache disk;
  final MovaTwoLevelCache inner;
  int writes=0,diskHits=0,memoryHits=0;
  @override
  Uint8List? peek(String key) {final b=inner.peek(key);if(b!=null){memoryHits++;}return b;}
  @override
  Future<Uint8List?> read(String key) async {final resident=memory.peek(key)!=null;final b=await inner.read(key);if(b!=null){if(resident){memoryHits++;}else{diskHits++;}}return b;}
  @override
  Future<void> write(String key,Uint8List bytes){writes++;return inner.write(key,bytes);}
  @override
  Future<void> clear()=>inner.clear();
  @override
  Future<void> dispose()=>inner.dispose();
}

/// Fails one start and succeeds the next so STT rollback can be observed.
///
/// 首次启动失败、第二次成功，用于观察STT回滚。
class RetrySttEngine extends MovaNoopSttEngine {
  int calls=0;
  @override
  List<String> get languages=>['en'];
  @override
  Future<void> start(Duration atPosition) async {calls++;if(calls==1){throw StateError('coverage missing model');}}
}

/// Verifies no-engine blocking and failed-start retry on a real device host.
///
/// 验证无引擎阻断及启动失败后可重试。
Future<void> stt() async {
  final none=createMovaEngine(audioOnly:true,options:const MovaOpts(stt:MovaSttConfig(enabled:true)));
  c.observe(none);await none.open(c.source(),autoPlay:false);await none.stt.start();await none.stt.stop();
  c.mark('STT_NO_ENGINE',{'running':none.stt.isRunning,'languages':none.stt.languages});await none.dispose();
  final engine=RetrySttEngine();
  final a=createMovaEngine(audioOnly:true,options:MovaOpts(stt:MovaSttConfig(enabled:true,engine:engine)));
  c.observe(a);await a.open(c.source(),autoPlay:false);
  try{await a.stt.start();}catch(e){c.mark('STT_EXPECTED_THROW',{'error':'$e','running':a.stt.isRunning});}
  c.check('N22.sttRollback',!a.stt.isRunning,'after first failure running=${a.stt.isRunning}');
  await a.stt.start();c.check('N22.sttRetry',engine.calls==2&&a.stt.isRunning,'calls=${engine.calls} running=${a.stt.isRunning}');
  await a.stt.stop();await a.dispose();
}

/// Leaves a VOD stalled beyond an explicit deadline with the watchdog disabled.
///
/// 关闭卡顿看门狗，让点播卡顿超过显式期限。
Future<void> watchoff() async {
  final local=<MovaEvent>[];
  final a=createMovaEngine(audioOnly:true,options:const MovaOpts(recovery:MovaRecoveryConfig(enabled:true,stallTimeout:Duration(seconds:1),stallWatchdog:false)));
  c.observe(a);a.events.listen(local.add);await a.open(c.source('stall.mp4'));
  await c.until(()=>a.state.rendered);await c.until(()=>a.state.buffering,seconds:20);await c.settle(5000);
  c.check('N2.watchoff',local.whereType<MovaPlayFailure>().isEmpty,'rendered=${a.state.rendered} buffering=${a.state.buffering} failures=${local.whereType<MovaPlayFailure>().length}');
  await a.dispose();
}

/// Captures complete session reports, timing only from emitted reports/events.
///
/// 采集完整会话报告，时间只取报告及事件。
Future<void> qoe(Map<String,String> args) async {
  final mode=args['mode']??'ended';
  final reports=<MovaReportEvent>[];
  final local=<MovaEvent>[];
  final a=createMovaEngine(audioOnly:true,options:const MovaOpts(report:MovaReportConfig(qoe:true)),
    reporter:MovaCallbackReporter((r){reports.add(r);c.mark('REPORT',{'name':r.name.value,'params':r.params});}));
  c.observe(a); a.events.listen(local.add);
  if(mode=='abandoned') {
    unawaited(a.open(c.source('hang'))); await c.settle(30); await a.dispose();
  }else if(mode=='failed') {
    try{await a.open(c.source('404.mp4'));}catch(e){c.mark('OPEN_THROW',{'error':'$e'});}
    await c.until(()=>local.whereType<MovaErrorEvent>().isNotEmpty,seconds:20); await a.dispose();
  }else {
    await a.open(mode=='truncated'?MovaSource('http://127.0.0.1:18084/truncated.mp4?t=${DateTime.now().microsecondsSinceEpoch}'):c.source(mode=='stall'?'stall.mp4':'ad.mp4'));
    if(mode=='ended'||mode=='truncated'){await c.until(()=>local.any((e)=>e is MovaDone),seconds:45);}
    else if(mode=='stopped'){await c.until(()=>c.latest.position.inSeconds>3);}
    else {await c.settle(25000);}
    await a.dispose();
  }
  await c.settle(300);
  c.mark('QOE_END',{'mode':mode,'reports':reports.length});
}

/// Switches real local HLS variants and records seek completion errors.
///
/// 切换真实本地 HLS 档位并记录续播落点误差。
/// Logs actual kernel seek calls without changing library code.
///
/// 不修改库，记录真实内核seek调用。
class RetestKernel extends MovaMpvKernel {
  RetestKernel(Player p):super(player:p,observeNativeEvents:true,
    backendFactory:(n,address)=>createFfiMpvEventBackend(n,address,pollInDebug:false));
  @override
  Future<void> seek(Duration position) async {
    c.mark('KERNEL_SEEK_CALL',{'target':position.inMilliseconds});
    await super.seek(position);
    c.mark('KERNEL_SEEK_RETURN',{'target':position.inMilliseconds});
  }
}

/// Waits on native readback; timeout only prevents hangs.
///
/// 等待原生读回，超时只防挂死。
Future<void> nativeUntil(FutureOr<bool> Function() predicate,{int seconds=20}) async {
  final end=c.clock.elapsedMilliseconds+seconds*1000;
  while(!await predicate()) {
    if(c.clock.elapsedMilliseconds>end) throw TimeoutException('native condition');
    await c.settle(40);
  }
}

/// Checks repeated disposal for real audio-only engines and proxies.
///
/// 检查真实仅音频引擎和代理的重复销毁。
Future<void> retestDispose() async {
  for(final proxy in [false,true]) {
    MovaEngine factory()=>createMovaEngine(audioOnly:true,options:MovaOpts(cutover:MovaCutoverConfig(enabled:proxy)));
    final MovaApi a=proxy?MovaCutoverEngine(engineFactory:factory):factory();
    c.observe(a);await a.open(c.source(),autoPlay:false);
    await c.until(()=>a.state.duration>Duration.zero);
    c.mark('DISPOSE_OPEN',{'cutover':proxy,'audioOnly':true,'state':c.snapshot(a)});
    for(var call=1;call<=2;call++) {
      try {await a.dispose().timeout(const Duration(seconds:10));c.mark('DISPOSE_RESULT',{'cutover':proxy,'call':call,'exception':null});}
      catch(e,s){c.mark('DISPOSE_RESULT',{'cutover':proxy,'call':call,'exception':'$e','stack':'$s'});}
    }
  }
}

Future<void> hls(Map<String,String> args) async {
  final count=int.parse(args['count']??'5');
  final paused=args['paused']=='true';
  final proxy=args['cutover']=='true';
  var iteration=-1;
  late Player player;
  late MovaMpvKernel kernel;
  MovaEngine factory() {
    player = Player();
    kernel = RetestKernel(player);
    return createMovaEngine(kernel: kernel, preciseFirstFrame: true,
      options: MovaOpts(cutover: MovaCutoverConfig(enabled: proxy)));
  }
  final MovaApi a = proxy ? MovaCutoverEngine(engineFactory: factory) : factory();
  final native = player.platform as NativePlayer;
  Future<int> position() async => ((double.tryParse(await native.getProperty('time-pos')) ?? -1) * 1000).round();
  var restarts = <int>[];
  var observedRestarts = <int>[];
  String? expectedUri;
  var qualitySeen = false;
  var gateMs = -1;
  Future<bool> variantReady() async {
    final path = await native.getProperty('path');
    if (qualitySeen && a.state.duration > Duration.zero && path == expectedUri) {
      if (gateMs < 0) {
        gateMs = c.clock.elapsedMilliseconds;
        c.mark('HLS_VARIANT_READY', {'run': iteration, 'path': path,
          'duration': a.state.duration.inMilliseconds, 'qualitySeen': qualitySeen});
      }
      return true;
    }
    return false;
  }
  var pending = Future<void>.value();
  c.observe(a);
  final eventSub = a.events.listen((e) {
    if (e is MovaQualityChange && e.quality.uri == expectedUri) qualitySeen = true;
    c.mark('HLS_EVENT', {'type': '${e.runtimeType}',
    'position': player.state.position.inMilliseconds, 'duration': a.state.duration.inMilliseconds,
    'playing': a.state.playing, 'intent': a.state.playbackIntent, 'rendered': a.state.rendered,
    if (e is MovaQualityChange) 'qualityUri': e.quality.uri,
    if (e is MovaErrorEvent) 'error': '${e.error}'});
  });
  final progressSub = player.stream.position.listen((p) => c.mark('NATIVE_PROGRESS', {'position': p.inMilliseconds}));
  final sub = kernel.playbackRestarts.listen((_) {
    final run = iteration;
    pending = pending.then((_) async {
      final p = await position();
      final path = await native.getProperty('path');
      await variantReady();
      final eligible = gateMs >= 0 && path == expectedUri;
      restarts.add(p);
      if (eligible) observedRestarts.add(p);
      c.mark('HLS_RESTART', {'run': run, 'position': p, 'path': path, 'eligible': eligible,
        'pause': await native.getProperty('pause')});
    });
  });
  c.screen.value = a;
  await c.settle(400);
  await a.open(MovaSource('http://127.0.0.1:18084/master.m3u8?t=${DateTime.now().microsecondsSinceEpoch}'));
  await nativeUntil(() async => a.state.rendered && await position() >= 8000, seconds: 40);
  await a.loadQualities();
  await nativeUntil(() => a.state.qualities.where((q) => !q.isAuto).length >= 2);
  final variants = a.state.qualities.where((q) => !q.isAuto).toList()
    ..sort((a, b) => b.label.compareTo(a.label));
  c.mark('HLS_QUALITIES', {'qualities': variants.map((q) => {'label': q.label, 'uri': q.uri}).toList(),
    'cutoverEnabled': a.options.cutover.enabled, 'video': true});
  if (paused) await a.pause();
  for (var i = 0; i < count; i++) {
    iteration = i;
    // Reset far from EOF; every target must first have real native progress >=8s.
    // 远离EOF重设进度；每次target须先由原生读回确认至少8秒。
    if (await position() > 20000 || await position() < 8000) {
      await a.seek(const Duration(seconds: 9));
      await nativeUntil(() async => (await position() - 9000).abs() <= 250);
    }
    // Wait until the engine's source progress stream catches the native readback.
    // 等引擎所读进度与原生值对齐，避免旧锚点造成验证工具误报。
    await nativeUntil(() async => (player.state.position.inMilliseconds - await position()).abs() <= 100);
    await pending;
    restarts = <int>[];
    final target = await position();
    final q = variants[i % 2];
    expectedUri = q.uri; qualitySeen = false; gateMs = -1;
    observedRestarts = <int>[];
    c.mark('HLS_SWITCH', {'run': i, 'cutover':proxy, 'paused':paused, 'target': target, 'quality': q.label, 'uri': q.uri,
      'streamPosition': player.state.position.inMilliseconds, 'pause': await native.getProperty('pause')});

    await a.switchQuality(q);
    try { await nativeUntil(variantReady, seconds: 6); }
    on TimeoutException { /* Retain as harness-invalid, never count as a result. */ }
    final harnessInvalid = gateMs < 0;
    var landed = -1;
    try {
      await nativeUntil(() async {
        await pending;
        final matches = observedRestarts.where((p) => (p - target).abs() <= 500);
        if (matches.isNotEmpty) { landed = matches.first; return true; }
        return false;
      }, seconds: 6);
    } on TimeoutException { /* Failure is retained with the complete journal. */ }
    var continued = await position();
    var continues = false;
    if (!paused && landed >= 0) {
      try {
        await nativeUntil(() async { continued = await position(); return continued >= landed + 250; }, seconds: 6);
        continues = true;
      } on TimeoutException { continues = false; }
    } else if (paused) {
      continues = (continued - target).abs() <= 500 && await native.getProperty('pause') == 'yes';
    }
    await pending;
    c.mark('HLS_RESULT', {'run': i, 'cutover':proxy, 'paused':paused, 'target': target, 'landed': landed, 'continued': continued,
      'gateMs': gateMs, 'harnessInvalid': harnessInvalid,
      'observedRestarts': List<int>.of(observedRestarts),
      'restarts': List<int>.of(restarts), 'resumed': landed >= 0, 'continuedOk': continues,
      'pass': !harnessInvalid && landed >= 0 && continues && await native.getProperty('path') == q.uri, 'pause': await native.getProperty('pause'),
      'path': await native.getProperty('path')});
  }
  iteration = -1;
  await pending;
  await sub.cancel(); await eventSub.cancel(); await progressSub.cancel();
  c.screen.value=null; await c.settle(200); await a.dispose();
}

/// Checks per-source mpv restoration and derived timeout values.
///
/// 检查按源 mpv 配置的还原及派生超时。
Future<void> options() async {
  final p = Player();
  final k = MovaMpvKernel(player: p, audioOnly: true, observeNativeEvents: false);
  final a = createMovaEngine(kernel: k, options: const MovaOpts(recovery:
    MovaRecoveryConfig(timeouts: MovaTimeouts(network: Duration(milliseconds: 1200),whepHandshake:Duration(seconds:2),whepFirstFrame:Duration(seconds:3),whepMedia:Duration(seconds:4)))));
  c.observe(a);
  final native = p.platform as NativePlayer;
  Future<Map<String, String>> read() async {
    final out = <String, String>{};
    for (final key in ['network-timeout', 'demuxer-lavf-o', 'cache', 'vid', 'mute']) {
      try { out[key] = await native.getProperty(key); } catch (e) { out[key] = '$e'; }
    }
    return out;
  }
  final before = await read();
  await a.open(MovaSource(c.source().uri, mpvOptions: {'cache':'no', 'network-timeout':'7', 'coverage-invalid':'x'},
    demuxerOptions: {'analyzeduration':'123456'}), autoPlay: false);
  await c.until(() => a.state.duration > Duration.zero);
  final custom = await read();
  c.check('N4.applied', custom['cache'] == 'no' && double.tryParse(custom['network-timeout']??'') == 7 && a.state.error == null, custom);
  await a.open(c.source('ad.mp4'), autoPlay: false);
  await c.until(() => a.state.duration > Duration.zero);
  final restored = await read();
  c.check('N1.network', double.tryParse(restored['network-timeout']??'') == 2, restored);
  c.check('N4.restore', restored['cache'] == before['cache'] && !restored['demuxer-lavf-o']!.contains('analyzeduration=123456'), {'before':before,'custom':custom,'restored':restored});
  try {await a.open(MovaSource('whep+http://127.0.0.1:9/no-service',mpvOptions:const {'network-timeout':'1'},
    demuxerOptions:const {'first_frame_timeout':'8000000'},whepMediaTimeout:const Duration(seconds:6)),autoPlay:false);}
  catch(e){c.mark('WHEP_EXPECTED_LOAD_ERROR',{'error':'$e'});}
  final whepReadback=await read();c.mark('WHEP_OPTIONS_READBACK',whepReadback);
  c.check('N4.whepOptions',whepReadback['demuxer-lavf-o']!.contains('media_timeout=6000000')&&whepReadback['demuxer-lavf-o']!.contains('handshake_timeout=2000000')&&whepReadback['demuxer-lavf-o']!.contains('first_frame_timeout=8000000'),'readback=$whepReadback');
  await a.open(c.source(),autoPlay:false);await c.until(()=>a.state.duration>Duration.zero);
  c.mark('WHEP_OPTIONS_RESTORED',await read());
  const config = MovaRecoveryConfig();
  c.check('N2.derived', config.startTimeoutFor('http://a').inSeconds == 65 && config.startTimeoutFor('whep://a').inSeconds == 85 && config.stallTimeoutFor('whep://a')!.inSeconds == 10 && config.copyWith(stallWatchdog:false).stallTimeoutFor('http://a') == null && config.copyWith(stallTimeout:const Duration(seconds:9)).copyWith(clearStallTimeout:true).stallTimeout == null, 'http=65,whepStart=85,whepStall=10,watchdogOff=null,clear=null');
  const t = MovaTimeouts(whepHandshake:Duration(seconds:2),whepFirstFrame:Duration(seconds:3),whepMedia:Duration(seconds:4));
  const s = MovaSource('whep://a',demuxerOptions:{'media_timeout':'8000000'},whepMediaTimeout:Duration(seconds:6));
  c.mark('NEW_CONFIG', {'whep':s.mpvOptionsFor(s.uri,timeouts:t),'http':s.mpvOptionsFor('http://a',timeouts:t),'defaults':const MovaTimeouts().mpvOptionsFor('http://a')});
  final picked = MovaSource.pick(['',' http://a ','http://a','http://b']);
  c.check('C17.pick', picked!.uris.length == 2 && picked.sameAs(const MovaSource('http://a',alternatives:['http://b'])) && !picked.sameAs(const MovaSource('http://a')), picked.uris);
  await a.open(const MovaSource('http://127.0.0.1:18084/low/index.m3u8',mpvOptions:{'http-header-fields':'X-Coverage: 42'}),autoPlay:false);
  await c.until(()=>a.state.duration>Duration.zero);c.mark('HEADERS_NATIVE',{'options':await native.getProperty('http-header-fields')});
  await a.dispose();
}

/// Records END_FILE driven recovery, failover and repeated live reconnects.
///
/// 记录 END_FILE 驱动恢复、切地址及持续直播重连。
Future<void> recovery(Map<String, String> args) async {
  final mode = args['mode'] ?? 'failover';
  final isLive=['live','liveDefault','liveLegacy','liveAlternatives'].contains(mode);
  final local = <MovaEvent>[];
  final start = c.clock.elapsedMilliseconds;
  final a = createMovaEngine(audioOnly:true, options:MovaOpts(recovery:MovaRecoveryConfig(
    enabled:true,
    liveReconnect:mode!='liveLegacy',
    policy: mode == 'live' ? const MovaLiveReconnect(maxAttempts:7) :
      mode=='liveDefault'||mode=='liveLegacy'?null:
      mode=='liveAlternatives'?const MovaLiveReconnect(initialDelay:Duration(milliseconds:20),retriesPerAddress:2,maxAttempts:2):const MovaFailoverOnly(),
    timeouts: mode == 'hang' ? const MovaTimeouts(network:Duration(seconds:2)) : const MovaTimeouts(),
  )));
  c.observe(a);
  a.events.listen((e) { local.add(e); if(e is MovaPlayFailure) c.mark('FAIL_TIMING',{'mode':mode,'since':c.clock.elapsedMilliseconds-start,'kind':e.fail.kind.name,'attempt':e.fail.attempt,'live':e.fail.isLive,'action':e.action.name}); });
  final uri = mode.startsWith('hang') ? c.source('hang').uri : c.source('not-found.mp4').uri;
  final accepted = await a.open(MovaSource(uri, type:isLive ? MovaStreamType.live : MovaStreamType.vod,
    alternatives:mode == 'failover' ? [c.source().uri] : mode=='liveAlternatives'?[c.source('other404.mp4').uri]:[]));
  c.mark('RECOVERY_OPEN',{'mode':mode,'accepted':accepted});
  if (mode == 'failover') {
    await c.until(() => local.any((e) => e is MovaRecovered),seconds:35);
    c.check('N6.clear',a.state.error == null, 'sourceIndex=${a.state.sourceIndex} error=${a.state.error}');
    c.check('N19.failover',a.state.sourceIndex == 1 && local.whereType<MovaFailover>().length == 1,local.map((e)=>e.runtimeType.toString()).toList());
  } else if(mode=='liveDefault') {
    await c.until(()=>local.whereType<MovaPlayFailure>().length>=3);
    c.check('N3.defaultLive',local.whereType<MovaPlayFailure>().last.action==MovaRecoveryAction.retry,'third failure still retries');
  } else {
    await c.until(() => a.state.error is MovaGiveUpError,seconds:120);
    c.check('N6.giveup',!a.state.buffering,'error=${a.state.error} buffering=${a.state.buffering}');
  }
  c.mark('RECOVERY_END',{'mode':mode,'state':c.snapshot(a),'error':'${a.state.error}'});
  await a.dispose();
}

/// Compares live duration event throttling and live-only seek gating.
///
/// 对比直播时长节流并验证直播 seek 拦截。
Future<void> live(Map<String,String> args) async {
  final step = int.parse(args['step'] ?? '2000');
  final local = <Map<String,Object>>[];
  final a = createMovaEngine(audioOnly:true, options:MovaOpts(live:MovaLiveConfig(durationStep:Duration(milliseconds:step))));
  c.observe(a);
  a.events.listen((e) { if(e is MovaDurationChange) local.add({'ms':c.clock.elapsedMilliseconds,'duration':e.duration.inMilliseconds}); });
  await a.open(MovaSource(c.source('live.flv?gop=50&audio=1').uri,type:MovaStreamType.live));
  await c.until(()=>a.state.rendered,seconds:25);
  final seeks = c.events.whereType<MovaSeek>().length;
  await a.seek(const Duration(seconds:3));
  c.check('A7.live',c.events.whereType<MovaSeek>().length == seeks,'seek events before=$seeks after=${c.events.whereType<MovaSeek>().length}');
  await c.settle(11000);
  await a.backToLiveEdge();
  c.mark('LIVE_DURATION',{'step':step,'samples':local});
  await a.dispose();
}

/// Controllable asynchronous hook used to observe cancellation races.
///
/// 可控异步钩子，用于观察取消竞态。
class ProbeHook extends MovaHook {
  bool reject = false;
  bool throwPlay=false,throwErrors=false;
  int errorCalls=0,delayedOpens=0;
  Completer<bool>? openGate;
  Completer<bool>? playGate;
  Completer<Duration?>? seekGate;
  @override
  Future<bool> beforeOpen(MovaSource source) async {if(openGate!=null && delayedOpens++==0){return openGate!.future;}return !reject;}
  @override
  Future<bool> beforePlay() async {if(throwPlay){throw StateError('coverage hook failure');}return playGate == null ? true : playGate!.future;}
  @override
  Future<Duration?> beforeSeek(Duration target) async => seekGate == null ? target : seekGate!.future;
  @override
  void onError(Object error,StackTrace stack){errorCalls++;if(throwErrors){throw StateError('coverage onError failure');}}
}

/// Exercises accepted/rejected opens and stale hook completions on real media.
///
/// 在真实媒体上验证 open 返回及过期钩子结果。
Future<void> hooks(bool cutover) async {
  final h = ProbeHook();
  final h2=ProbeHook();
  MovaEngine factory()=>createMovaEngine(audioOnly:true,interceptors:[h,h2],options:MovaOpts(playlist:MovaPlaylistConfig(items:[MovaPlaylistItem(source:c.source()),MovaPlaylistItem(source:c.source('ad.mp4'))])));
  final MovaApi a=cutover?MovaCutoverEngine(engineFactory:factory):factory();c.observe(a);
  h.reject=true;
  c.check('N8.reject',!await a.open(c.source()),'beforeOpen=false');
  h.reject=false;
  c.check('N8.accept',await a.open(c.source(),autoPlay:false),'accepted=true');
  await c.until(()=>a.state.duration>Duration.zero);
  h.playGate=Completer<bool>(); final pending = a.play(); await c.settle();
  await a.pause(); h.playGate!.complete(true); await pending; await c.settle();
  c.check('N22.stalePlay',!a.state.playbackIntent && !a.state.playing,c.snapshot(a)); h.playGate=null;
  h.seekGate=Completer<Duration?>(); final seek=a.seek(const Duration(seconds:10)); await c.settle();
  await a.open(c.source('ad.mp4'),autoPlay:false); h.seekGate!.complete(const Duration(seconds:10)); await seek;
  await c.settle(1000); c.mark('HOOK_SEEK_FINAL',c.snapshot(a)); h.seekGate=null;
  final list=MovaPlaylist(a); h.reject=true; await list.jumpTo(1);
  c.mark('HOOK_PLAYLIST',{'index':list.currentIndex}); await list.dispose();
  c.check('N8.playlistRejected',list.currentIndex==0,'rejected jumpTo(1), index=${list.currentIndex}');h.reject=false;
  h.openGate=Completer<bool>();h.delayedOpens=0;
  final first=a.open(c.source(),autoPlay:false);await c.settle(100);
  final second=await a.open(c.source('ad.mp4'),autoPlay:false);h.openGate!.complete(true);
  c.check('N8.superseded',!await first && second,'first=false second=$second');h.openGate=null;
  h.throwPlay=true;try{await a.play();}catch(e){c.mark('HOOK_EXPECTED_THROW',{'error':'$e'});}h.throwPlay=false;
  await a.play();await c.until(()=>a.state.playing);c.check('A32.afterThrow',a.state.playing,'play works after hook exception');await a.pause();
  final seeks=c.events.whereType<MovaSeek>().length;
  h.seekGate=Completer<Duration?>()..complete(null);await a.seek(const Duration(seconds:4));await c.settle(150);
  c.check('A32.seekVeto',c.events.whereType<MovaSeek>().length==seeks,'seek cancelled');h.seekGate=null;
  h.throwErrors=true;try{await a.open(c.source('404.mp4'));}catch(e){c.mark('OPEN_EXPECTED_ERROR',{'error':'$e'});}await c.until(()=>h2.errorCalls>0);
  c.check('A32.onErrorIsolation',h2.errorCalls>0,'firstHook=${h.errorCalls} secondHook=${h2.errorCalls}');
  await a.open(c.source(),autoPlay:false);await c.until(()=>a.state.rendered);
  await a.dispose(); c.check('N8.disposed',!await a.open(c.source()),'disposed=false');
}


// Real transport stalls, default ABR policy; no synthetic buffering events.
Future<void> rerun6Weak(Map<String,String> args) async {
  final manual=args['manual']=='true';
  final count=int.parse(args['count']??'10');
  Future<String> get(String path) async {
    final client=HttpClient();
    try {final res=await(await client.getUrl(Uri.parse('http://127.0.0.1:18085/$path'))).close();return await res.transform(utf8.decoder).join();}
    finally {client.close();}
  }
  for(var run=0;run<count;run++) {
    final a=createMovaEngine(preciseFirstFrame:true);
    c.observe(a);c.screen.value=a;await c.settle(250);
    final local=<MovaEvent>[];
    final sub=a.events.listen(local.add);
    var start=0;String? error;
    try {
      await get('throttle/off');
      final qs=parseHlsMasterPlaylist(await get('master.m3u8'),base:Uri.parse('http://127.0.0.1:18085/master.m3u8'));
      final variants=qs.where((q)=>!q.isAuto).toList();
      final high=variants.first;
      // Start pinned high without a manual switch: seed metadata parsed from
      // the actual master via the existing test hook; all playback is real.
      await a.open(MovaSource('${high.uri}?run=$run&manual=$manual',mpvOptions:const {'cache':'no','demuxer-max-bytes':'65536','demuxer-readahead-secs':'0'}));
      a.debugSetQualities(qs,current:high);
      await c.until(()=>a.state.rendered&&c.latest.position.inMilliseconds>=2000,seconds:30);
      local.clear();start=c.clock.elapsedMilliseconds;
      c.mark('WEAK_START',{'run':run,'manual':manual,'threshold':a.options.abr.stallThreshold,'customPolicy':a.options.abr.policy!=null,'high':high.uri,'low':variants.last.uri,'initialQualitySeeded':true});
      await get('throttle/on');
      if(manual) {
        c.mark('WEAK_MANUAL',{'run':run,'quality':high.label});
        await a.switchQuality(high);
      }
      try {await c.until(()=>local.whereType<MovaAbrDownShift>().isNotEmpty,seconds:150);}
      on TimeoutException catch(e) {error='$e';}
      await c.settle(200);
      final shifts=local.whereType<MovaAbrDownShift>().toList();
      c.mark('WEAK_RESULT',{'run':run,'manual':manual,'startMs':start,'pass':shifts.isNotEmpty&&a.state.currentQuality?.uri==variants.last.uri,'quality':a.state.currentQuality?.label,'uri':a.state.currentQuality?.uri,'abrCount':shifts.length,'error':error,'state':c.snapshot(a)});
    }catch(e,s) {
      c.mark('WEAK_RESULT',{'run':run,'manual':manual,'startMs':start,'pass':false,'error':'$e','stack':'$s','abrCount':local.whereType<MovaAbrDownShift>().length});
    }finally {
      await get('throttle/off');await sub.cancel();c.screen.value=null;await c.settle(150);await a.dispose();
    }
  }
}
