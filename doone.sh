#!/bin/bash

# 숫자 입력 받기
echo "처리할 파일의 시작 숫자를 입력하세요:"
read -r file_number

# 입력 값 검증
if [[ ! "$file_number" =~ ^[0-9]+$ ]]; then
  echo "Error: 숫자만 입력해주세요."
  exit 1
fi

# 작업 디렉토리 설정
WORK_DIR="/workspace"
OUTPUT_DIR="outputs"
TEMP_DIR="temp_segments"

# 기본 경로 및 S3 설정
BASE_PATH="/workspace/有名アプリのデータベース構造を学び、DB設計を理解する3時間"
S3_DESTINATION="s3://vod-ttest-destination-1dka6y7nswcjj/videos/961f71a8-ab19-4f05-b7b0-2927f5f0c419/test"

# 출력 디렉토리 생성
mkdir -p "$OUTPUT_DIR"

# 특정 숫자로 시작하는 mp4 파일 찾기 (첫 번째 매치만)
video_file=$(find "$BASE_PATH" -name "${file_number}*.mp4" -type f | head -n 1)

if [ -z "$video_file" ]; then
  echo "Error: ${file_number}로 시작하는 mp4 파일을 찾을 수 없습니다."
  exit 1
fi

echo "Found file: $video_file"
echo "Processing: $video_file"

# 파일명에서 확장자 제거
base_name=$(basename "$video_file" .mp4)

# 원본 파일의 상대 경로 계산
relative_path=$(dirname "$video_file" | sed "s|^$BASE_PATH||" | sed 's|^/||')

# 임시 디렉토리 생성
temp_dir="${TEMP_DIR}/${base_name}"
mkdir -p "$temp_dir"

# 영상 길이 확인 (초 단위)
duration=$(ffmpeg -i "$video_file" 2>&1 | grep "Duration" | cut -d ' ' -f 4 | sed s/,// | awk -F: '{print ($1 * 3600) + ($2 * 60) + $3}' | cut -d. -f1)
echo "Video duration: ${duration} seconds"

if [ "$duration" -gt 10 ]; then
  echo "Video is longer than 10 seconds. Splitting into 10-second segments..."

  # 10초씩 자르기
  ffmpeg -i "$video_file" -c copy -f segment -segment_time 10 -reset_timestamps 1 "${temp_dir}/segment_%03d.mp4"

  # 각 세그먼트 처리
  processed_segments=()
  for segment in "${temp_dir}"/segment_*.mp4; do
    if [ -f "$segment" ]; then
      echo "Processing segment: $segment"
      segment_name=$(basename "$segment" .mp4)

      # 워터마크 제
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

    # S3에 업로드
    cleaned_file="${OUTPUT_DIR}/${base_name}_cleaned.mp4"
    if [ -f "$cleaned_file" ]; then
      if [ -n "$relative_path" ]; then
        s3_target_path="${S3_DESTINATION}/${relative_path}/${base_name}_cleaned.mp4"
      else
        s3_target_path="${S3_DESTINATION}/${base_name}_cleaned.mp4"
      fi

      echo "Uploading to S3: $s3_target_path"
      aws s3 cp "$cleaned_file" "$s3_target_path"

      if [ $? -eq 0 ]; then
        echo "Successfully uploaded to S3: $s3_target_path"
      else
        echo "Failed to upload to S3: $s3_target_path"
      fi
    fi
  fi
else
  echo "Video is 10 seconds or less. Processing directly..."

  # 직접 처리
  python3 main.py --input "$video_file" --remove-watermark

  # 결과 파일을 올바른 위치로 이동
  cleaned_file=""
  if [ -f "outputs/${base_name}_cleaned.mp4" ]; then
    cleaned_file="outputs/${base_name}_cleaned.mp4"
    echo "File already in correct location: outputs/${base_name}_cleaned.mp4"
  elif [ -f "outputs/${base_name}.mp4" ]; then
    mv "outputs/${base_name}.mp4" "${OUTPUT_DIR}/${base_name}_cleaned.mp4"
    cleaned_file="${OUTPUT_DIR}/${base_name}_cleaned.mp4"
    echo "Moved to: ${OUTPUT_DIR}/${base_name}_cleaned.mp4"
  fi

  # S3에 업로드
  if [ -n "$cleaned_file" ] && [ -f "$cleaned_file" ]; then
    if [ -n "$relative_path" ]; then
      s3_target_path="${S3_DESTINATION}/${relative_path}/${base_name}_cleaned.mp4"
    else
      s3_target_path="${S3_DESTINATION}/${base_name}_cleaned.mp4"
    fi

    echo "Uploading to S3: $s3_target_path"
    aws s3 cp "$cleaned_file" "$s3_target_path"

    if [ $? -eq 0 ]; then
      echo "Successfully uploaded to S3: $s3_target_path"
    else
      echo "Failed to upload to S3: $s3_target_path"
    fi
  fi
fi

# 임시 파일 정리
rm -rf "$temp_dir"
echo "Completed processing: $video_file"
echo "=========================="

# 전체 임시 디렉토리 정리
rm -rf "$TEMP_DIR"
echo "Processing completed successfully!"
