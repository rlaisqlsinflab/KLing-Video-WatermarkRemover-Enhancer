#!/bin/bash

# 작업 디렉토리 설정
WORK_DIR="/workspace"
OUTPUT_DIR="outputs"
TEMP_DIR="temp_segments"

# 출력 디렉토리 생성
mkdir -p "$OUTPUT_DIR"

# mp4 파일들을 찾아서 처리
find /workspace/有名アプリのデータベース構造を学び、DB設計を理解する3時間 -name "*.mp4" -type f | while read -r video_file; do
  echo "Processing: $video_file"

  # 파일명에서 확장자 제거
  base_name=$(basename "$video_file" .mp4)

  # 임시 디렉토리 생성
  temp_dir="${TEMP_DIR}/${base_name}"
  mkdir -p "$temp_dir"

  # 영상 길이 확인 (초 단위)
  duration=$(ffmpeg -i "$video_file" 2>&1 | grep "Duration" | cut -d ' ' -f 4 | sed s/,// | awk -F: '{print ($1 * 3600) + ($2 * 60) + $3}' | cut -d. -f1)

  echo "Video duration: ${duration} seconds"

  if [ "$duration" -gt 10 ]; then
    echo "Video is longer than 1 minute. Splitting into 1-minute segments..."

    # 1분씩 자르기
    ffmpeg -i "$video_file" -c copy -f segment -segment_time 10 -reset_timestamps 1 "${temp_dir}/segment_%03d.mp4"

    # 각 세그먼트 처리
    processed_segments=()
    for segment in "${temp_dir}"/segment_*.mp4; do
      if [ -f "$segment" ]; then
        echo "Processing segment: $segment"
        segment_name=$(basename "$segment" .mp4)

        # 워터마크 제거
        python3 main.py --input "$segment" --remove-watermark

        # 처리된 파일명 확인 (outputs에 생성되었을 것)
        if [ -f "outputs/${segment_name}_cleaned.mp4" ]; then
          processed_segments+=("outputs/${segment_name}_cleaned.mp4")
        elif [ -f "outputs/${segment_name}.mp4" ]; then
          processed_segments+=("outputs/${segment_name}.mp4")
        fi
      fi
    done

    # 처리된 세그먼트들을 합치기
    if [ ${#processed_segments[@]} -gt 0 ]; then
      # concat 파일 생성
      concat_file="${temp_dir}/concat_list.txt"
      printf "file '%s'\n" "${processed_segments[@]}" >"$concat_file"

      # 세그먼트들을 합치기
      ffmpeg -f concat -safe 0 -i "$concat_file" -c copy "${OUTPUT_DIR}/${base_name}_cleaned.mp4"

      echo "Merged segments into: ${OUTPUT_DIR}/${base_name}_cleaned.mp4"
    fi
  else
    echo "Video is 1 minute or less. Processing directly..."

    # 직접 처리
    python3 main.py --input "$video_file" --remove-watermark

    # 결과 파일을 올바른 위치로 이동
    if [ -f "outputs/${base_name}_cleaned.mp4" ]; then
      echo "File already in correct location: outputs/${base_name}_cleaned.mp4"
    elif [ -f "outputs/${base_name}.mp4" ]; then
      mv "outputs/${base_name}.mp4" "${OUTPUT_DIR}/${base_name}_cleaned.mp4"
      echo "Moved to: ${OUTPUT_DIR}/${base_name}_cleaned.mp4"
    fi
  fi

  # 임시 파일 정리
  rm -rf "$temp_dir"

  echo "Completed processing: $video_file"
  echo "=========================="
done

# 전체 임시 디렉토리 정리
rm -rf "$TEMP_DIR"

echo "All videos processed successfully!"
