#!/bin/bash
# create_test_fixtures.sh — 在指定目录生成模拟 SD 卡测试数据
# Usage: ./create_test_fixtures.sh <target_dir> [--large]
set -euo pipefail

TARGET="${1:?Usage: create_test_fixtures.sh <target_dir> [--large]}"
LARGE="${2:-}"

echo "📦 Creating test fixtures at: $TARGET"

# --- DCIM 结构 (模拟相机) ---
DCIM="$TARGET/DCIM"
mkdir -p "$DCIM/100CANON" "$DCIM/101CANON" "$DCIM/200SONY"

# JPG 照片
for i in $(seq 1 20); do
  dd if=/dev/urandom of="$DCIM/100CANON/IMG_$(printf '%04d' $i).JPG" bs=1024 count=$((RANDOM % 3000 + 500)) 2>/dev/null
done

# 小写 jpg
for i in $(seq 1 5); do
  dd if=/dev/urandom of="$DCIM/100CANON/photo_$(printf '%03d' $i).jpg" bs=1024 count=$((RANDOM % 2000 + 300)) 2>/dev/null
done

# HEIF
for i in $(seq 1 5); do
  dd if=/dev/urandom of="$DCIM/101CANON/IMG_$(printf '%04d' $i).HEIF" bs=1024 count=$((RANDOM % 4000 + 800)) 2>/dev/null
done

# RAW (ARW, CR2, CR3)
for i in $(seq 1 8); do
  dd if=/dev/urandom of="$DCIM/200SONY/DSC_$(printf '%04d' $i).ARW" bs=1024 count=$((RANDOM % 8000 + 5000)) 2>/dev/null
done
for i in $(seq 1 4); do
  dd if=/dev/urandom of="$DCIM/100CANON/IMG_$(printf '%04d' $i).CR2" bs=1024 count=$((RANDOM % 8000 + 5000)) 2>/dev/null
done
for i in $(seq 1 3); do
  dd if=/dev/urandom of="$DCIM/100CANON/IMG_$(printf '%04d' $i).CR3" bs=1024 count=$((RANDOM % 8000 + 5000)) 2>/dev/null
done

# XML (元数据)
echo '<?xml version="1.0"?><meta>test</meta>' > "$DCIM/100CANON/META.XML"

# 非目标扩展名（用于过滤测试）
for i in $(seq 1 5); do
  dd if=/dev/urandom of="$DCIM/100CANON/LOG_$(printf '%03d' $i).TXT" bs=512 count=10 2>/dev/null
done
for i in $(seq 1 3); do
  dd if=/dev/urandom of="$DCIM/100CANON/THUMB_$(printf '%03d' $i).DB" bs=512 count=5 2>/dev/null
done

# --- CLIP 目录 (视频) ---
CLIP="$TARGET/CLIP"
mkdir -p "$CLIP/C0001" "$CLIP/C0002"

for i in $(seq 1 5); do
  size=$((RANDOM % 50000 + 10000))
  dd if=/dev/urandom of="$CLIP/C0001/C0001_$(printf '%03d' $i).MP4" bs=1024 count=$size 2>/dev/null
done
for i in $(seq 1 3); do
  size=$((RANDOM % 80000 + 20000))
  dd if=/dev/urandom of="$CLIP/C0002/C0002_$(printf '%03d' $i).MOV" bs=1024 count=$size 2>/dev/null
done
# 小写 mov
dd if=/dev/urandom of="$CLIP/C0002/clip_001.mov" bs=1024 count=5000 2>/dev/null

# --- PRIVATE 目录 (Sony 视频) ---
PRIVATE="$TARGET/PRIVATE/M4ROOT/CLIP"
mkdir -p "$PRIVATE"
for i in $(seq 1 3); do
  dd if=/dev/urandom of="$PRIVATE/SONY_$(printf '%04d' $i).MP4" bs=1024 count=$((RANDOM % 30000 + 10000)) 2>/dev/null
done

# --- 特殊文件名测试 ---
mkdir -p "$DCIM/SPECIAL"
echo "space test" > "$DCIM/SPECIAL/file with spaces.JPG"
echo "chinese" > "$DCIM/SPECIAL/照片_测试.JPG"
echo "special" > "$DCIM/SPECIAL/[bracket].JPG"
echo "ampersand" > "$DCIM/SPECIAL/photo&video.JPG"
echo "quote" > "$DCIM/SPECIAL/it's a photo.JPG"

# --- 大文件 (可选) ---
if [[ "$LARGE" == "--large" ]]; then
  echo "📦 Creating large test files (this may take a while)..."
  mkdir -p "$TARGET/LARGE"
  dd if=/dev/urandom of="$TARGET/LARGE/big_video_001.MP4" bs=1048576 count=500 2>/dev/null
  dd if=/dev/urandom of="$TARGET/LARGE/big_video_002.MOV" bs=1048576 count=300 2>/dev/null
fi

# --- 统计 ---
FILE_COUNT=$(find "$TARGET" -type f | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "$TARGET" | cut -f1)
echo "✅ Fixtures created: $FILE_COUNT files, total $TOTAL_SIZE"
