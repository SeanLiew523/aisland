"""Reuse the checked-in website movie's native pixels; remove only the wallpaper matte.

30 fps samples keep recorded time and require no video codec or file-origin canvas
readback in the isolated WKWebView review host. Never redraw task fields or marks.
"""
from pathlib import Path
import json, subprocess
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parent
sources = {'en': root.parents[1] / 'aisland-website/dist/assets/native-demo-en.mp4',
           'zh': root.parents[1] / 'docs/images/readme/native-demo-zh.mp4'}
assets = root / 'assets'
ranges = {'approval': (7.25, 8.98), 'answer': (12.75, 13.88),
          'sessions': (14.3, 16.35), 'completion': (16.85, 18.75),
          'closed': (.05, 1.35)}
fps = 30
manifest = {'sources': {lang:str(path.relative_to(root.parents[1])) for lang,path in sources.items()},
            'fps': fps,
            'processing': 'Recorded pixels; stable source in-points omit the original UI expansion overlap. Crop and wallpaper-only alpha matte; no task/UI redraw. Remaining animation plays at original speed, then holds its last frame.',
            'clips': {}}
for lang,source in sources.items():
    manifest['clips'][lang] = {}
    for kind, (start, end) in ranges.items():
        crop = (1288,0,496,58) if kind == 'closed' else (1066,0,940,900)
        x,y,w,h = crop
        width = 496 if kind == 'closed' else 704
        scaled_height = round(h*width/w)
        result = subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error',
            '-ss', str(start), '-i', str(source), '-t', str(end-start),
            '-vf', f'crop={w}:{h}:{x}:{y},fps={fps}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1'],
            check=True, stdout=subprocess.PIPE)
        raw = np.frombuffer(result.stdout, dtype=np.uint8).reshape((-1,h,w,3))
        frames, heights = [], []
        for rgb in raw:
            # The capture's native dark panel is surrounded by the bright Ventura wallpaper.
            # Retain every original colored/text pixel between the native panel's dark edges.
            dark = np.max(rgb, axis=2) < 60
            has = np.any(dark, axis=1)
            left = np.argmax(dark, axis=1)
            right = w-1 - np.argmax(dark[:,::-1], axis=1)
            xx = np.arange(w)[None,:]
            mask = has[:,None] & (xx >= left[:,None]) & (xx <= right[:,None])
            alpha = (mask * 255).astype(np.uint8)
            rgba = np.dstack((rgb,alpha))
            height = int(np.max(np.where(has)[0])+1) if np.any(has) else 1
            height = min(h,height+2)
            image = Image.fromarray(rgba).resize((width,scaled_height),Image.Resampling.LANCZOS)
            frames.append(image)
            heights.append(round(height*scaled_height/h))
        visible_height = max(heights)
        columns = 2
        pages = []
        for offset in range(0,len(frames),8):
            group = frames[offset:offset+8]
            atlas = Image.new('RGBA',(width*columns,visible_height*((len(group)+columns-1)//columns)))
            for i,image in enumerate(group):
                atlas.paste(image.crop((0,0,width,visible_height)),((i%columns)*width,(i//columns)*visible_height))
            name = f'native-{kind}-{lang}-{len(pages)}.png'
            atlas.save(assets/name,optimize=True)
            pages.append({'file':name,'offset':offset,'frames':len(group)})
        still_index = min(len(frames)-1,round(.65*fps))
        frames[still_index].crop((0,0,width,visible_height)).save(assets/f'native-{kind}-{lang}-still.png',optimize=True)
        manifest['clips'][lang][kind] = {'source_range':[start,end],'source_crop':list(crop),
            'fps':fps,'columns':columns,'pages':pages,'frames':len(frames),
            'width':width,'height':visible_height,'visible_heights':heights,'still_frame':still_index}
        print(lang,kind,len(frames),visible_height,'px',flush=True)
(assets/'native-media.json').write_text(json.dumps(manifest,indent=2)+'\n')
(assets/'native-media.js').write_text('window.AIslandNativeMedia = '+json.dumps(manifest['clips'],separators=(',',':'))+';\n')
