#!/bin/sh
# Reformat the approved 20-second native recordings for GitHub.
# Widen the close-up and keep enough height for the fully expanded answer panel.
# The opaque display border works in both GitHub themes; no fade covers native UI.
# Recorded timing and native UI remain unchanged.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
language=${1:-en}
case "$language" in
  en) task_output="$task_root/docs/images/aisland-demo.gif" ;;
  zh) task_output="$task_root/docs/images/aisland-demo-zh.gif" ;;
  *) printf '%s\n' 'Usage: sh scripts/export-readme-demo.sh [en|zh]' >&2; exit 1 ;;
esac
ffmpeg -hide_banner -loglevel error -y \
  -i "$task_root/docs/images/readme/native-demo-$language.mp4" \
  -filter_complex "[0:v]fps=15,crop=1440:900:816:0,scale=928:580:flags=lanczos,pad=960:612:16:16:color=0x111116,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -an -loop 0 "$task_output"
