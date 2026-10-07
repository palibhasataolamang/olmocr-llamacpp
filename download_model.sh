#!/usr/bin/env bash
set -e

# Model download script for olmOCR-2-7B-1025 GGUF
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
mkdir -p "${MODELS_DIR}"

BASE_URL="https://huggingface.co/lmstudio-community/olmOCR-2-7B-1025-GGUF/resolve/main"
MODEL_FILE="olmOCR-2-7B-1025-Q4_K_M.gguf"
MMPROJ_FILE="mmproj-olmOCR-2-7B-1025-F16.gguf"

LOCAL_LMSTUDIO_DIR="${HOME}/.var/app/ai.lmstudio.lm-studio/.lmstudio/models/lmstudio-community/olmOCR-2-7B-1025-GGUF"

download_or_copy() {
    local filename="$1"
    local dest="${MODELS_DIR}/${filename}"

    if [ -f "${dest}" ]; then
        echo "✓ ${filename} already exists in ${MODELS_DIR}."
        return 0
    fi

    # Check local LM Studio cache first to save bandwidth
    if [ -f "${LOCAL_LMSTUDIO_DIR}/${filename}" ]; then
        echo "Found cached file in LM Studio: ${LOCAL_LMSTUDIO_DIR}/${filename}"
        echo "Copying to ${dest}..."
        cp -v "${LOCAL_LMSTUDIO_DIR}/${filename}" "${dest}"
        return 0
    fi

    echo "Downloading ${filename} from Hugging Face..."
    local url="${BASE_URL}/${filename}"

    if command -v aria2c &> /dev/null; then
        aria2c -x 8 -s 8 -c -d "${MODELS_DIR}" -o "${filename}" "${url}"
    elif command -v curl &> /dev/null; then
        curl -L -C - --progress-bar -o "${dest}" "${url}"
    elif command -v wget &> /dev/null; then
        wget -c -O "${dest}" "${url}"
    else
        echo "Error: Neither curl, wget, nor aria2c is installed." >&2
        exit 1
    fi

    echo "✓ Finished downloading ${filename}"
}

echo "=== olmOCR Model Downloader ==="
download_or_copy "${MMPROJ_FILE}"
download_or_copy "${MODEL_FILE}"

echo "=== Model files verified in ${MODELS_DIR} ==="
ls -lh "${MODELS_DIR}"
