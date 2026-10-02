"""Export sharp animation media from the app's unchanged native vector component."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('repository', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('assets', type=Path)
parser.add_argument('--commit', default='111b21950f2319213432e4464c3f6ee6862ff95b')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
sources = []
hashes = {}
for name in ['BloubStatusGlyph.swift', 'UnifiedBars.swift']:
    source = subprocess.check_output(['git', '-C', str(args.repository), 'show',
                                     f'{args.commit}:Sources/OpenIslandApp/Views/{name}'])
    target = args.output / name
    target.write_bytes(source)
    sources.append(str(target))
    hashes[name] = hashlib.sha256(source).hexdigest()
binary = args.output / 'status-capture'
subprocess.run(['swiftc', '-parse-as-library', *sources,
                str(Path(__file__).with_name('StatusCapture.swift')), '-o', str(binary)], check=True)
subprocess.run([str(binary), str(args.output.resolve())], check=True)

for name in ['idle', 'thinking', 'approval', 'answer']:
    paths = sorted((args.output / name).glob('*.png'))
    frames = [Image.open(path).convert('RGBA') for path in paths]
    assert frames and all(frame.size == (384, 384) for frame in frames)
    unique = len({hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames})
    assert unique > 2, f'{name}: native animation did not move'
    frames[0].save(args.assets / f'status-{name}-hd.webp', save_all=True,
                   append_images=frames[1:], duration=50, loop=0, lossless=True, method=4)
    frames[0].save(args.assets / f'status-{name}-hd.png')
    print(name, len(frames), 'native vector frames;', unique, 'distinct;', frames[0].size)
metadata = {
    'source_commit': args.commit,
    'component_sha256': hashes,
    'upstream': 'https://github.com/jeremy-prt/bloub',
    'upstream_port_commit': 'b4bb3c1b5f93c7b87a2e8d620f667c4093d97749',
    'rendering': 'Unchanged BloubLayerView, 192-point bounds, 384-pixel presentation-layer capture; no raster enlargement',
    'fps': 20,
    'period_seconds': {'idle': 12, 'thinking': 1.5, 'approval': 25, 'answer': 25},
    'waiting_motion': 'alive',
    'colors': {'idle': 'paper', 'thinking': 'paper', 'approval': 'approval', 'answer': 'answer'},
    'scope': 'The four states implemented by the installed app; no additional upstream expressions'
}
(args.assets / 'status-provenance.json').write_text(json.dumps(metadata, indent=2) + '\n')
