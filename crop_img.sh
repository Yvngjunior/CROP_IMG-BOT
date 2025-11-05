#!/data/data/com.termux/files/usr/bin/bash
#
# crop_bot.sh
# Usage:
#   ./crop_bot.sh preview  -> crops a single sample image for checking
#   ./crop_bot.sh batch    -> crops all png/jpg in the input dir
#   ./crop_bot.sh watch    -> watches input dir and crops new images automatically
#
# This script uses ImageMagick (magick convert). Adjust CROP_AREA if needed.

# ----- USER CONFIG -----
INPUT_DIR="$HOME/storage/shared/Preview"
OUTPUT_DIR="$HOME/storage/shared/Preview/Cropped"
# Crop settings for your screenshot example:
# crop_area="WIDTHxHEIGHT+XOFFSET+YOFFSET"
# For the sample screenshot we discussed: 1536x326, start Y=180, start X=0
CROP_AREA="720x698+0+320"

# Alternate more-robust option using gravity (center) if widths vary:
# GRAVITY_CROP="1080x1080+0+0"   # example if you want centered square crops
# Use GRAVITY_MODE=true to use -gravity center -crop instead of fixed coords
GRAVITY_MODE=false
GRAVITY_SIZE="1536x326+0+0" # used only if GRAVITY_MODE=true
# ------------------------

mkdir -p "$OUTPUT_DIR"

# helper: crop one file
crop_file() {
  local infile="$1"
  local outfile="$2"
  if [ "$GRAVITY_MODE" = true ]; then
    magick convert "$infile" -gravity center -crop "$GRAVITY_SIZE" +repage "$outfile"
  else
    magick convert "$infile" -crop "$CROP_AREA" +repage "$outfile"
  fi
}

# Preview mode: crop the newest image (safe check)
if [ "$1" = "preview" ]; then
  sample=$(ls -t "$INPUT_DIR"/*.{png,jpg,jpeg} 2>/dev/null | head -n1)
  if [ -z "$sample" ]; then
    echo "No images found in $INPUT_DIR"
    exit 1
  fi
  base=$(basename "$sample")
  out="$OUTPUT_DIR/preview_$base"
  echo "Preview cropping: $sample -> $out"
  crop_file "$sample" "$out"
  echo "Preview saved. Open this file on your phone to inspect the crop."
  exit 0
fi

# Batch mode: process all images
if [ "$1" = "batch" ]; then
  shopt -s nullglob
  count=0
  for img in "$INPUT_DIR"/*.{png,jpg,jpeg}; do
    filename=$(basename "$img")
    out="$OUTPUT_DIR/$filename"
    crop_file "$img" "$out" && echo "Cropped: $filename" && count=$((count+1))
  done
  echo "Done. Cropped $count files. Output dir: $OUTPUT_DIR"
  exit 0
fi

# Watch mode: auto-crop new files as they appear
if [ "$1" = "watch" ]; then
  echo "Watching $INPUT_DIR for new images..."
  inotifywait -m "$INPUT_DIR" -e create --format "%f" |
  while read file; do
    # simple check for extension
    case "$file" in
      *.png|*.jpg|*.jpeg|*.PNG|*.JPG|*.JPEG)
        sleep 0.5  # wait a little to ensure file is fully written
        src="$INPUT_DIR/$file"
        dst="$OUTPUT_DIR/$file"
        echo "New file detected: $file"
        crop_file "$src" "$dst" && echo "Auto-cropped: $file"
        ;;
      *) ;;
    esac
  done
  exit 0
fi

# If no param provided, show usage
cat <<EOF
Usage: $0 {preview|batch|watch}
  preview  - crop newest image to preview output (safe)
  batch    - crop all images in $INPUT_DIR and save to $OUTPUT_DIR
  watch    - continuously watch $INPUT_DIR and auto-crop new images
Current crop_area: $CROP_AREA
GRAVITY_MODE: $GRAVITY_MODE
EOF
exit 0
