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

# NEW: Delete original files after successful cropping
DELETE_ORIGINALS=false  # Set to true to auto-delete originals
DELETE_CONFIRMATION=true  # Ask before deleting (safety!)
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

# NEW: Safely delete original file after cropping
delete_original() {
  local original_file="$1"
  local cropped_file="$2"
  
  # Safety check: Only delete if cropped file exists and is valid
  if [ ! -f "$cropped_file" ]; then
    echo -e "${RED}⚠ Skipping delete: Cropped file doesn't exist${NC}"
    log_message "DELETE SKIPPED: Cropped file missing - $cropped_file"
    return 1
  fi
  
  # Check cropped file size (should be > 0 bytes)
  if [ ! -s "$cropped_file" ]; then
    echo -e "${RED}⚠ Skipping delete: Cropped file is empty${NC}"
    log_message "DELETE SKIPPED: Cropped file empty - $cropped_file"
    return 1
  fi
  
  # Delete the original
  if rm "$original_file" 2>/dev/null; then
    echo -e "${GREEN}🗑️  Deleted original: $(basename "$original_file")${NC}"
    log_message "DELETED: $original_file"
    return 0
  else
    echo -e "${RED}⚠ Failed to delete: $(basename "$original_file")${NC}"
    log_message "DELETE FAILED: $original_file"
    return 1
  fi
}

# NEW: Ask user for confirmation before deleting
ask_delete_confirmation() {
  echo -e "${YELLOW}⚠ WARNING: This will DELETE original files after cropping!${NC}"
  echo -e "${YELLOW}   Deleted files CANNOT be recovered!${NC}"
  echo ""
  read -p "Are you sure you want to delete originals? (type YES to confirm): " response
  
  if [ "$response" = "YES" ]; then
    return 0  # User confirmed
  else
    echo -e "${BLUE}✓ Keeping original files safe${NC}"
    return 1  # User cancelled
  fi
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
  Delete originals: $DELETE_ORIGINALS

${GREEN}EXAMPLES:${NC}
  # Test your crop settings first:
  $0 preview
  
  # Process all existing images:
  $0 batch
  
  # Run in background to auto-crop new screenshots:
  $0 watch &

${YELLOW}TIP:${NC} Always run 'preview' first to check your crop settings!

${RED}DANGER ZONE:${NC}
  To enable auto-delete of originals, edit the script and set:
    DELETE_ORIGINALS=true
  
  This will permanently delete original files after cropping!
  Use with caution - deleted files cannot be recovered.
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
  
  # Ask for confirmation if delete is enabled
  should_delete=false
  if [ "$DELETE_ORIGINALS" = true ]; then
    if [ "$DELETE_CONFIRMATION" = true ]; then
      if ask_delete_confirmation; then
        should_delete=true
      fi
    else
      should_delete=true
      echo -e "${YELLOW}⚠ DELETE_ORIGINALS is enabled - originals will be deleted!${NC}"
    fi
  fi
  
  echo ""
  
  shopt -s nullglob
  count=0
  skipped=0
  failed=0
  deleted=0
  
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
      
      # Delete original if enabled
      if [ "$should_delete" = true ]; then
        if delete_original "$img" "$out"; then
          deleted=$((deleted+1))
        fi
      fi
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
  if [ $deleted -gt 0 ]; then
    echo -e "🗑️  Deleted: ${BLUE}$deleted${NC} originals"
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
  
  # Show delete status
  if [ "$DELETE_ORIGINALS" = true ]; then
    echo -e "${YELLOW}⚠ DELETE MODE ACTIVE: Originals will be deleted after cropping${NC}"
  fi
  
  echo ""
  
  log_message "Watch mode started (DELETE_ORIGINALS=$DELETE_ORIGINALS)"
  
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
          
          # Delete original if enabled
          if [ "$DELETE_ORIGINALS" = true ]; then
            delete_original "$src" "$dst"
          fi
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
