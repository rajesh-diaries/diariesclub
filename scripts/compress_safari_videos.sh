#!/usr/bin/env bash
# Compress Safari Club trait videos for mobile asset bundles.
# Outputs 720p H.264 MP4s to assets/videos/.
#
# Usage:
#   ./scripts/compress_safari_videos.sh rafi_source.mp4 gerry_source.mov ellie_source.mp4 zena_source.mp4
#
# The output filenames are fixed as:
#   assets/videos/rafi_brave.mp4
#   assets/videos/gerry_curious.mp4
#   assets/videos/ellie_kind.mp4
#   assets/videos/zena_creative.mp4
set -euo pipefail

OUTPUT_DIR="assets/videos"
mkdir -p "$OUTPUT_DIR"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <source-video>..."
  echo "Example: $0 rafi.mp4 gerry.mov ellie.mp4 zena.mp4"
  exit 1
fi

# Map positional inputs to fixed output names.
declare -a OUTPUT_NAMES=(
  "rafi_brave.mp4"
  "gerry_curious.mp4"
  "ellie_kind.mp4"
  "zena_creative.mp4"
)

for i in "${!OUTPUT_NAMES[@]}"; do
  input="${1:-}"
  if [ -z "$input" ]; then
    echo "Warning: no source provided for ${OUTPUT_NAMES[$i]}, skipping."
    continue
  fi

  if [ ! -f "$input" ]; then
    echo "Error: file not found: $input"
    exit 1
  fi

  output="$OUTPUT_DIR/${OUTPUT_NAMES[$i]}"
  echo "==> Compressing $input -> $output"

  ffmpeg -y -i "$input" \
    -vf "scale=720:-2,format=yuv420p" \
    -c:v libx264 -profile:v high -level:v 4.1 \
    -preset medium -crf 23 \
    -movflags +faststart \
    -c:a aac -b:a 128k -ar 48000 \
    "$output"

done

echo "==> Done. Compressed videos are in $OUTPUT_DIR/"
echo "    Now update lib/features/safari/safari_screen.dart trait 'video' fields to:"
echo "      assets/videos/rafi_brave.mp4"
echo "      assets/videos/gerry_curious.mp4"
echo "      assets/videos/ellie_kind.mp4"
echo "      assets/videos/zena_creative.mp4"
