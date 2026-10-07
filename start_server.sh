#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
MODEL_FILE="${MODELS_DIR}/olmOCR-2-7B-1025-Q4_K_M.gguf"
MMPROJ_FILE="${MODELS_DIR}/mmproj-olmOCR-2-7B-1025-F16.gguf"

# Default configurations
HOST="127.0.0.1"
PORT="1234"
CTX_SIZE="4096"        # Sized specifically for single-page OCR execution
PARALLEL="1"           # Single slot for 1-by-1 sequential execution
ALIAS="allenai/olmocr-2-7b-1025"

# Auto-detect GPU offloading
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    DEFAULT_NGL=99
else
    DEFAULT_NGL=0
fi
N_GPU_LAYERS="${DEFAULT_NGL}"

usage() {
    cat <<EOF
Usage: $0 [options] [-- <additional llama-server arguments>]

Launcher script for llama.cpp OpenAI-compatible server for olmOCR.

Options:
  -p, --port <port>         Port to listen on (default: ${PORT})
  -h, --host <host>         Host binding (default: ${HOST})
  -g, --ngl <layers>        GPU layers to offload (default: ${DEFAULT_NGL})
  -c, --ctx-size <size>     Context size (default: ${CTX_SIZE}, tuned for single execution)
  -np, --parallel <n>       Parallel slots (default: ${PARALLEL})
  -a, --alias <name>        Model alias (default: ${ALIAS})
  --bin <path>              Explicit path to llama-server binary
  --help                    Show this help message

Environment Variables:
  LLAMA_SERVER_BIN          Custom path to llama-server binary
  PORT                      Port to listen on
  HOST                      Host binding
  N_GPU_LAYERS              GPU layers to offload
  CTX_SIZE                  Context size
  PARALLEL                  Number of parallel slots
EOF
    exit 0
}

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        -g|--ngl)
            N_GPU_LAYERS="$2"
            shift 2
            ;;
        -c|--ctx-size)
            CTX_SIZE="$2"
            shift 2
            ;;
        -np|--parallel)
            PARALLEL="$2"
            shift 2
            ;;
        -a|--alias)
            ALIAS="$2"
            shift 2
            ;;
        --bin)
            LLAMA_SERVER_BIN="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        --)
            shift
            EXTRA_ARGS+=("$@")
            break
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# 1. Ensure model files exist
if [ ! -f "${MODEL_FILE}" ] || [ ! -f "${MMPROJ_FILE}" ]; then
    echo "Model files missing in ${MODELS_DIR}. Triggering downloader..."
    "${SCRIPT_DIR}/download_model.sh"
fi

# 2. Locate llama-server binary
find_llama_server() {
    if [ -n "${LLAMA_SERVER_BIN}" ] && [ -x "${LLAMA_SERVER_BIN}" ]; then
        echo "${LLAMA_SERVER_BIN}"
        return 0
    fi

    if command -v llama-server &> /dev/null; then
        command -v llama-server
        return 0
    fi

    if [ -x "${SCRIPT_DIR}/bin/llama-server" ]; then
        echo "${SCRIPT_DIR}/bin/llama-server"
        return 0
    fi

    # Search LM Studio backends (test candidates with --version to ensure dynamic libraries load)
    local lmstudio_backends="${HOME}/.var/app/ai.lmstudio.lm-studio/.lmstudio/extensions/backends"
    if [ -d "${lmstudio_backends}" ]; then
        for pattern in "*cuda12*" "*cuda*" "*vulkan*" "*avx2*"; do
            while IFS= read -r bin; do
                [ -z "${bin}" ] && continue
                if [ -x "${bin}" ] && "${bin}" --version &> /dev/null; then
                    echo "${bin}"
                    return 0
                fi
            done < <(find "${lmstudio_backends}" -name "llama-server" -path "${pattern}" 2>/dev/null | sort -V -r)
        done
    fi

    return 1
}

LLAMA_SERVER="$(find_llama_server || true)"

if [ -z "${LLAMA_SERVER}" ] || [ ! -x "${LLAMA_SERVER}" ]; then
    echo "Error: llama-server executable not found." >&2
    echo "Please specify the binary using --bin <path> or LLAMA_SERVER_BIN=<path>," >&2
    echo "or place it in ./bin/llama-server or install it in your PATH." >&2
    exit 1
fi

echo "=============================================="
echo " Starting llama-server for olmOCR"
echo " Binary:      ${LLAMA_SERVER}"
echo " Model:       ${MODEL_FILE}"
echo " Multimodal:  ${MMPROJ_FILE}"
echo " Host:        ${HOST}"
echo " Port:        ${PORT}"
echo " Context:     ${CTX_SIZE} (optimized for single execution)"
echo " Parallel:    ${PARALLEL} slot(s)"
echo " GPU Layers:  ${N_GPU_LAYERS}"
echo " Model Alias: ${ALIAS}"
echo " Endpoint:    http://${HOST}:${PORT}/v1"
echo "=============================================="

exec "${LLAMA_SERVER}" \
    -m "${MODEL_FILE}" \
    --mmproj "${MMPROJ_FILE}" \
    --host "${HOST}" \
    --port "${PORT}" \
    -ngl "${N_GPU_LAYERS}" \
    -c "${CTX_SIZE}" \
    -np "${PARALLEL}" \
    --alias "${ALIAS}" \
    --image-min-tokens 1024 \
    "${EXTRA_ARGS[@]}"
