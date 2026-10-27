from pathlib import Path
import hashlib,json,zipfile,re
R=Path(__file__).resolve().parents[2];O=R/'example/tool/coverage_evidence'
h=lambda b:hashlib.sha256(b).hexdigest()
with zipfile.ZipFile(O/'rerun7-device-pulled.apk') as z:
 aot=z.read('lib/arm64-v8a/libapp.so');native=[]
 for p in (R/'packages/media_kit_libs_android_video_slim_v041/android/src/main/jniLibs/arm64-v8a').glob('*.so'):
  pointer=p.read_bytes();expected=re.search(rb'oid sha256:(\w+)',pointer)
  actual=h(z.read('lib/arm64-v8a/'+p.name));assert actual==(expected[1].decode() if expected else h(pointer))
  native.append({'entry':p.name,'sha256':actual})
stripped=R/'example/build/app/intermediates/stripped_native_libs/release/stripReleaseDebugSymbols/out/lib/arm64-v8a/libapp.so'
assert h(aot)==h(stripped.read_bytes())
merged=R/'example/build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib/arm64-v8a/libapp.so'
candidates=[p for p in (R/'example/.dart_tool/flutter_build').glob('*/arm64-v8a/app.so') if h(p.read_bytes())==h(merged.read_bytes())]
assert candidates
compiler=max(candidates,key=lambda p:p.stat().st_mtime);deps=compiler.parent.parent/'kernel_snapshot_program.d'
assert 'mova/lib/src/core/engine.dart' in deps.read_text(encoding='utf-8').replace('\\','/').replace('//','/')
(O/'rerun7-build-dependencies.txt').write_bytes(deps.read_bytes())
inputs={k.replace(chr(92),'/'):v for k,v in json.loads((O/'rerun7-source-hashes.json').read_text()).items()}
assert all(h((R/p).read_bytes())==v for p,v in inputs.items())
engine=(R/'lib/src/core/engine.dart').read_text();assert re.search(r'_pendingSeekTarget == null &&\s*_lastPosition',engine)
data={'installedStrippedAotSha256':h(aot),'compilerAot':str(compiler.relative_to(R)),'compilerAotSha256':h(compiler.read_bytes()),'mergedAotSha256':h(merged.read_bytes()),'dependenciesContainEngine':True,'engineSha256':inputs['lib/src/core/engine.dart'],'containsNewCriterion':True,'nativeLibraries':native}
(O/'rerun7-build-provenance.json').write_text(json.dumps(data,indent=2))
print(json.dumps(data,indent=2))
