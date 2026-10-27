"""Build diagnostic contact sheets; original screenshots remain untouched."""
from pathlib import Path
from PIL import Image,ImageDraw
import json,sys
O=Path(__file__).resolve().parent/'coverage_evidence'
stems=['rerun-batch16-engine-fit-contain','rerun-batch16-engine-fit-cover','rerun-batch16-engine-fit-fill',
 'rerun-batch25-controls','rerun-batch25-danmaku','rerun-batch25-preview-bubble','rerun-batch25-spinner-custom','rerun-batch25-spinner-disabled',
 'rerun-batch25-error-visible','rerun-batch25-error-disabled','rerun-batch25-mini-tap','rerun-batch25-nextup',
 'rerun-batch25-ad-countdown','rerun-batch25-ad-skippable','rerun-batch25-ad-skip','rerun-batch25-route-player',
 'rerun-batch25-route-back','rerun-batch25-feed-after','rerun-batch22-minimal-no-gesture','rerun-batch3-29-skin-mini',
 'rerun-batch16-engine-customSurface','rerun-batch16-engine-patch','rerun-batch22-mini-drag','rerun-batch22-mini-landscape',
 'rerun-batch22-mini-portrait','rerun-batch22-mini-fling','rerun-batch28-poster-covered','rerun-batch28-fade-0',
 'rerun-batch28-fade-3','rerun-batch28-fade-7','rerun-batch28-fade-11','rerun-batch28-final']
safe='--safe' in sys.argv
if safe:stems=[s.replace('rerun-batch25-','rerun-safe-visual-').replace('rerun-batch28-','rerun-safe-transition-') for s in stems]
existing=[s for s in stems if (O/(s+'.png')).exists()]
manifest=[]
for page in range(0,len(existing),8):
    names=existing[page:page+8]
    canvas=Image.new('RGB',(1200,1380),'#eeeeee');draw=ImageDraw.Draw(canvas)
    for index,name in enumerate(names):
        x=index%4*300;y=index//4*690
        im=Image.open(O/(name+'.png')).convert('RGB');im.thumbnail((296,650))
        canvas.paste(im,(x+(300-im.width)//2,y+38))
        label=name.replace('rerun-batch','')
        draw.text((x+3,y+3),label[:39],fill='black')
    dest=O/f'rerun-{"safe-" if safe else ""}contact-{page//8+1}.jpg';canvas.save(dest,quality=90)
    manifest.append({'file':dest.name,'screenshots':names})
(O/('rerun-safe-contact-manifest.json' if safe else 'rerun-contact-manifest.json')).write_text(json.dumps({'pages':manifest,'missing':[s for s in stems if s not in existing]},indent=2),encoding='utf-8')
print(manifest)
