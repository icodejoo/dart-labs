import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import '../main_rerun6_coverage_api.dart' as c;

final coverageWidgetKey=GlobalKey<CoverageWidgetsState>();
final coverageRouteObserver=RouteObserver<ModalRoute<void>>();

/// Mounts the declarative and feed widgets with observable real engines.
///
/// 挂载声明式及feed组件，并观察真实引擎。
class CoverageWidgets extends StatefulWidget {
  const CoverageWidgets({super.key});
  @override
  State<CoverageWidgets> createState()=>CoverageWidgetsState();
}

/// Drives lifecycle changes from the same device HTTP control channel.
///
/// 通过真机HTTP控制通道驱动组件生命周期变更。
class CoverageWidgetsState extends State<CoverageWidgets> {
  String mode='view';
  MovaSource? current=c.source();
  MovaOpts options=const MovaOpts();
  MovaApi? active;
  MovaApi? routeApi;
  final created=<MovaApi>[];
  bool ticker=true;
  int opens=0;

  MovaApi create(MovaOpts opts) {
    final a=createMovaEngine(options:opts,preciseFirstFrame:true,interceptors:const[WidgetFaultHook()]);created.add(a);active=a;c.observe(a);
    a.events.listen((e){if(e is MovaSourceChange){opens++;}});
    c.mark('WIDGET_ENGINE',{'created':created.length});return a;
  }

  Future<void> command(Map<String,String> args) async {
    final action=args['action']??'snapshot';
    switch(action) {
      case 'feed': setState(()=>mode='feed');
      case 'view': setState(()=>mode='view');
      case 'same': setState(()=>current=MovaSource(current!.uri,title:'renamed same media',alternatives:current!.alternatives));
      case 'null': setState(()=>current=null);
      case 'source': setState(()=>current=c.source(args['path']??'ad.mp4'));
      case 'error': setState(()=>current=MovaSource(c.source().uri,title:'THROW'));
      case 'options': setState(()=>options=options.copyWith(theme:const MovaTheme(bufferingSize:60,bufferingStrokeWidth:8,bufferingColor:0xFFFF0000),strings:const MovaStrs(fitContain:'COVERAGE FIT',quality:'COVERAGE QUALITY')));
      case 'ticker': setState(()=>ticker=args['value']=='true');
      case 'route':
        unawaited(Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const Scaffold(body:Center(child:Text('COVERING ROUTE'))))));
        await c.settle(3500);c.mark('ROUTE_HIDDEN',active==null?{}:c.snapshot(active!));
        if(mounted){Navigator.of(context).pop();}
      case 'routePlayer':
        final e=createMovaEngine(preciseFirstFrame:true);routeApi=e;c.observe(e);
        unawaited(Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>Scaffold(body:MovaPlayer(api:e)))).whenComplete(()=>e.dispose()));
        await c.settle(200);await e.open(c.source());e.showControls(sticky:true);
      case 'unmount': setState(()=>mode='none');
    }
    await c.settle(800);
    c.mark('WIDGET',{'action':action,'mode':mode,'created':created.length,'opens':opens,'source':current?.uri,'ticker':ticker,'state':active==null?null:c.snapshot(active!),'routeState':routeApi==null?null:c.snapshot(routeApi!)});
  }

  @override
  Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Column(children:[
    Text('COVERAGE WIDGET $mode'),
    Expanded(child: switch(mode){
      'feed'=>MovaFeedPlayer(engineFactory:()=>create(const MovaOpts()),
        posterUntilFirstFrame:true,placeholderBuilder:(_,i)=>ColoredBox(color:Colors.teal,child:Center(child:Text('FEED POSTER $i'))),
        loader:(i)async=>i<0||i>=10?null:MovaFeedItem(source:c.source('vod.mp4?item=$i'),authorName:'Coverage $i',musicName:'Native audio',
          onLikeChanged:(liked,count)=>c.mark('FEED_LIKE',{'index':i,'liked':liked,'count':count}),onComment:()=>c.mark('FEED_COMMENT',{'index':i}))),
      'view'=>TickerMode(enabled:ticker,child:MovaView(source:current,options:options,engineFactory:create,
        fit:MovaFit.cover,poster:const ColoredBox(color:Colors.teal,child:Center(child:Text('VIEW POSTER'))),
        autoPause:const MovaAutoPauseConfig(),routeObservers:[coverageRouteObserver],
        onOpenError:(e,s)=>c.mark('VIEW_OPEN_ERROR',{'error':'$e'}))),
      _=>const Center(child:Text('UNMOUNTED')),
    }),
  ])));
}

/// Explicit host fault injection for MovaView.onOpenError, not a native error.
///
/// 宿主故障注入，用于onOpenError验证，不冒充原生播放失败。
class WidgetFaultHook extends MovaHook {
  const WidgetFaultHook();
  @override
  Future<bool> beforeOpen(MovaSource source) async {if(source.title=='THROW'){throw StateError('coverage host beforeOpen fault');}return true;}
}
