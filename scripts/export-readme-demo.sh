#!/bin/sh
# Reformat the approved 20-second English native recording for GitHub.
# Crop and a lower-device fade affect presentation only; timing and native UI
# are unchanged. The expanded panel remains above the fade throughout.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ffmpeg -hide_banner -loglevel error -y \
  -i "$task_root/docs/images/readme/native-demo-en.mp4" \
  -filter_complex "[0:v]fps=15,crop=1200:640:936:0,scale=928:494:flags=lanczos,pad=960:520:16:16:color=0x111116,format=gbrp,geq=r='r(X,Y)*(1-clip((Y-440)/70,0,1))+244*clip((Y-440)/70,0,1)':g='g(X,Y)*(1-clip((Y-440)/70,0,1))+244*clip((Y-440)/70,0,1)':b='b(X,Y)*(1-clip((Y-440)/70,0,1))+240*clip((Y-440)/70,0,1)',split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -an -loop 0 "$task_root/docs/images/aisland-demo.gif"
