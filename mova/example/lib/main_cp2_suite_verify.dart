import 'dart:convert';
import 'dart:io';
import 'verify_auto/auto_kit.dart';
import 'verify_auto/cp2_harness.dart';
import 'verify_auto/cp2_adpaths_auto.dart';
import 'verify_auto/cp2_adpause_auto.dart';
import 'verify_auto/cp2_adbg_auto.dart';
import 'verify_auto/cp2_pod2_auto.dart';
import 'verify_auto/cp2_playlist3_auto.dart';
import 'verify_auto/cp2_bgowner_auto.dart';
import 'verify_auto/cp2_audioonly_bg_auto.dart';
import 'verify_auto/cp2_qoe_auto.dart';
Future<void> main() async {
  final client=HttpClient();
  try {
    final req=await client.getUrl(Uri.parse('http://127.0.0.1:18082/group'));
    final parts=(await utf8.decoder.bind(await req.close()).join()).trim().split('|');
    coverageRunsOverride=int.parse(parts[2]);
    final scene=parts[0].replaceFirst('cp2-','');
    cp2BgownerViewOnly=scene=='bgowner' && parts[1]=='view';
    final scripts=<String,Cp2Script>{
'adpaths':runAdpaths,'adpause':runAdpause,'adbg':runAdbg,'pod2':runPod2,'playlist3':runPlaylist3,'bgowner':runBgowner,'audioonly-bg':runAudioonlyBg,'qoe':runQoe,'qoepause':runQoePause30};
    cp2Main(scene,scripts[scene]!,automatic:true);
  } finally {client.close(force:true);}
}
