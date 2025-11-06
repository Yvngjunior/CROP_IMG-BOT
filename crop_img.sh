#!/data/data/com.termux/files/usr/bin/bash
#
# crop_bot.sh - Smart Image Cropping Bot
# 
# Usage:
#   ./crop_bot.sh preview  -> crops newest image for checking
#   ./crop_bot.sh batch    -> crops all png/jpg in input dir
#   ./crop_bot.sh watch    -> watches input dir and auto-crops new images
#   ./crop_bot.sh help     -> shows detailed help

# ===== USER CONFIG =====
INPUT_DIR="$HOME/storage/shared/Preview"
OUTPUT_DIR="$HOME/storage/shared/Preview/Cropped"

# Crop settings: WIDTHxHEIGHT+X_OFFSET+Y_OFFSET
CROP_AREA="720x698+0+320"

# Advanced: Use gravity-based cropping (centers the crop)
GRAVITY_MODE=false
GRAVITY_SIZE="1536x326+0+0"

# NEW: Log file for tracking what we've done
LOG_FILE="$OUTPUT_DIR/crop_bot.log"

# NEW: Skip files that are already cropped (avoid duplicates)
SKIP_ALREADY_CROPPED=true
# =======================

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create necessary directories
mkdir -p "$OUTPUT_DIR"

# NEW: Logging function
log_message() {
  local message="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

# NEW: Check if ImageMagick is installed
check_dependencies() {
  if ! command -v magick &> /dev/null; then
    echo -e "${RED}ERROR: ImageMagick not found!${NC}"
    echo "Install it with: pkg install imagemagick"
    exit 1
  fi
}

# NEW: Check if file was already processed
is_already_cropped() {
  local filename="$1"
  local outfile="$OUTPUT_DIR/$filename"
  
  if [ "$SKIP_ALREADY_CROPPED" = true ] && [ -f "$outfile" ]; then
    return 0  # true - already exists
  fi
  return 1  # false - not cropped yet
}

# Crop a single file with error handling
crop_file() {
  local infile="$1"
  local outfile="$2"
  
  # Check if input file exists and is readable
  if [ ! -f "$infile" ]; then
    echo -e "${RED}Error: File not found: $infile${NC}"
    log_message "ERROR: File not found - $infile"
    return 1
  fi
  
  # Perform the crop
  if [ "$GRAVITY_MODE" = true ]; then
    magick convert "$infile" -gravity center -crop "$GRAVITY_SIZE" +repage "$outfile" 2>/dev/null
  else
    magick convert "$infile" -crop "$CROP_AREA" +repage "$outfile" 2>/dev/null
  fi
  
  # Check if crop was successful
  if [ $? -eq 0 ] && [ -f "$outfile" ]; then
    log_message "SUCCESS: Cropped $infile -> $outfile"
    return 0
  else
    echo -e "${RED}Error: Failed to crop $infile${NC}"
    log_message "ERROR: Failed to crop $infile"
    return 1
  fi
}

# NEW: Show detailed help
show_help() {
  cat <<EOF
${BLUE}=== CROP BOT - Image Cropping Assistant ===${NC}

${GREEN}USAGE:${NC}
  $0 preview   - Test crop on newest image
  $0 batch     - Crop all images in input folder
  $0 watch     - Auto-crop new images as they arrive
  $0 help      - Show this help message

${GREEN}CURRENT SETTINGS:${NC}
  Input folder:  $INPUT_DIR
  Output folder: $OUTPUT_DIR
  Crop area:     $CROP_AREA
  Gravity mode:  $GRAVITY_MODE
  Log file:      $LOG_FILE

${GREEN}EXAMPLES:${NC}
  # Test your crop settings first:
  $0 preview
  
  # Process all existing images:
  $0 batch
  
  # Run in background to auto-crop new screenshots:
  $0 watch &

${YELLOW}TIP:${NC} Always run 'preview' first to check your crop settings!
EOF
}

# ===== PREVIEW MODE =====
if [ "$1" = "preview" ]; then
  check_dependencies
  
  echo -e "${BLUE}=== Preview Mode ===${NC}"
  
  # Find newest image
  sample=$(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
  
  if [ -z "$sample" ]; then
    echo -e "${RED}No images found in $INPUT_DIR${NC}"
    exit 1
  fi
  
  base=$(basename "$sample")
  out="$OUTPUT_DIR/preview_$base"
  
  echo -e "📸 Source: ${GREEN}$base${NC}"
  echo -e "✂️  Cropping with area: ${YELLOW}$CROP_AREA${NC}"
  
  if crop_file "$sample" "$out"; then
    echo -e "${GREEN}✓ Preview saved: $out${NC}"
    echo -e "${YELLOW}➜ Open this file to check if the crop looks good!${NC}"
  else
    echo -e "${RED}✗ Preview failed${NC}"
    exit 1
  fi
  
  exit 0
fi

# ===== BATCH MODE =====
if [ "$1" = "batch" ]; then
  check_dependencies
  
  echo -e "${BLUE}=== Batch Mode ===${NC}"
  echo "Processing all images in $INPUT_DIR..."
  
  shopt -s nullglob
  count=0
  skipped=0
  failed=0
  
  for img in "$INPUT_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG}; do
    filename=$(basename "$img")
    out="$OUTPUT_DIR/$filename"
    
    # Skip if already cropped
    if is_already_cropped "$filename"; then
      echo -e "${YELLOW}⊙ Skipped (exists): $filename${NC}"
      skipped=$((skipped+1))
      continue
    fi
    
    # Crop the image
    if crop_file "$img" "$out"; then
      echo -e "${GREEN}✓ Cropped: $filename${NC}"
      count=$((count+1))
    else
      failed=$((failed+1))
    fi
  done
  
  echo ""
  echo -e "${GREEN}=== Batch Complete ===${NC}"
  echo -e "✓ Cropped: ${GREEN}$count${NC} files"
  echo -e "⊙ Skipped: ${YELLOW}$skipped${NC} files"
  if [ $failed -gt 0 ]; then
    echo -e "✗ Failed:  ${RED}$failed${NC} files"
  fi
  echo -e "Output: $OUTPUT_DIR"
  
  exit 0
fi

# ===== WATCH MODE =====
if [ "$1" = "watch" ]; then
  check_dependencies
  
  # Check if inotifywait is available
  if ! command -v inotifywait &> /dev/null; then
    echo -e "${RED}ERROR: inotifywait not found!${NC}"
    echo "Install it with: pkg install inotify-tools"
    exit 1
  fi
  
  echo -e "${BLUE}=== Watch Mode ===${NC}"
  echo -e "${GREEN}👀 Watching $INPUT_DIR for new images...${NC}"
  echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
  echo ""
  
  log_message "Watch mode started"
  
  inotifywait -m "$INPUT_DIR" -e create,moved_to --format "%f" 2>/dev/null |
  while read file; do
    # Check file extension
    case "$file" in
      *.png|*.jpg|*.jpeg|*.PNG|*.JPG|*.JPEG)
        sleep 2  # Wait for file to be fully written
        src="$INPUT_DIR/$file"
        dst="$OUTPUT_DIR/$file"
        
        # Skip if already processed
        if is_already_cropped "$file"; then
          echo -e "${YELLOW}⊙ Skipped (exists): $file${NC}"
          continue
        fi
        
        echo -e "${BLUE}📥 New file detected: $file${NC}"
        
        if crop_file "$src" "$dst"; then
          echo -e "${GREEN}✓ Auto-cropped: $file${NC}"
        else
          echo -e "${RED}✗ Failed to crop: $file${NC}"
        fi
        echo ""
        ;;
    esac
  done
  
  exit 0
fi

# ===== HELP OR INVALID COMMAND =====
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  show_help
  exit 0
fi

# No valid parameter provided
echo -e "${YELLOW}Invalid or missing command!${NC}"
echo ""
show_help
exit 1
