from rerun6_extra import call,unlocked,adb,request,note
import time,sys
# Restart the same installed package, retaining every completed batch separately.
unlocked();adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
for _ in range(100):
 try:
  d=request('/');assert any(x.get('build')=='rerun6-20261027' for x in d['records']);break
 except Exception:time.sleep(.25)
else:raise RuntimeError('page missing')
mode=sys.argv[1] if len(sys.argv)>1 else 'both'
count=sys.argv[2] if len(sys.argv)>2 else '10'
for name,manual in [('automatic','false'),('manual','true')]:
 if mode not in ['both',name]:continue
 call('rerun6-weak-'+name,'new',case='rerun6Weak',manual=manual,count=count)
