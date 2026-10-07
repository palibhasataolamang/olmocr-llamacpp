# Local Document OCR with llama.cpp & olmOCR

A lightweight, self-contained batch OCR pipeline for PDFs and images powered by **[allenai/olmocr-2-7b-1025](https://huggingface.co/allenai/olmocr-2-7b-1025)** running locally on **llama.cpp**.

Extract high-fidelity Markdown (including headings, tables, formulas, and formatting) from scans and documents without cloud API costs or privacy concerns.

---

## ✨ Features

* **High-Fidelity Document OCR**: Transcribes documents into structured Markdown rather than plain unformatted text.
* **Multipage PDF Support**: Automatically converts every page of a PDF into JPG, transcribes each page with the vision model sequentially, and consolidates all pages into a single `.md` file with standard page dividers (`---`).
* **Automatic Server Lifecycle**: If `llama-server` is not already running, `ocr.py` automatically launches the local server, waits for initialization, processes the queue, and cleanly shuts it down upon completion to release GPU memory.
* **Low VRAM Footprint**: Tuned specifically for single-execution inference (`--ctx-size 4096`, `--parallel 1`), allowing the 7B vision model and KV cache to fit comfortably inside an 8 GB VRAM GPU (~6.7 GB footprint).
* **Automated Model Retrieval**: Includes a script to download the quantized GGUF weights and multimodal projector from Hugging Face with resume support, or reuse cached files from local LM Studio installations.
* **Format Flexibility**: Accepts `.pdf`, `.png`, `.jpg`, `.jpeg`, `.webp`, and `.bmp`.

---

## 📋 Prerequisites & Installation

### 1. System Dependencies & Python Environment
Run the included setup script to install `poppler-utils` (required for PDF page rendering), create a virtual environment (`venv/`), and install Python packages:

```bash
chmod +x install.sh download_model.sh start_server.sh
./install.sh
```

Alternatively, manually install dependencies:
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y poppler-utils python3-venv python3-pip

# Python virtual environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Model Weights
Download the quantized GGUF weights (`olmOCR-2-7B-1025-Q4_K_M.gguf`) and multimodal projector (`mmproj-olmOCR-2-7B-1025-F16.gguf`):

```bash
./download_model.sh
```
*Model files are saved to `./models/` (approx. 5.7 GB total).*

---

## 🚀 Quick Start

Activate the virtual environment and pass one or more documents to `ocr.py`:

```bash
source venv/bin/activate

# Process a single PDF or image
python ocr.py invoice.pdf

# Process multiple files sequentially
python ocr.py scan1.pdf document.png report.pdf
```

The script will automatically detect if `llama-server` is running, launch it if needed, transcribe the documents page-by-page, write `<filename>.md` for each input, and stop the server when done.

---

## ⚙️ CLI Reference

### `ocr.py`

```text
usage: ocr.py [-h] [--base-url BASE_URL] [--api-key API_KEY]
              [--ctx-size CTX_SIZE] [--keep-server] [--no-auto-server]
              [--save-pages]
              file_paths [file_paths ...]

positional arguments:
  file_paths           One or more paths to input image or PDF files

options:
  -h, --help           Show this help message and exit
  --base-url BASE_URL  OpenAI-compatible base URL (default: http://localhost:1234/v1)
  --api-key API_KEY    API Key (default: 'lm-studio')
  --ctx-size CTX_SIZE  Context size for auto-launched server (default: 4096)
  --keep-server        Keep the auto-launched server running after processing completes
  --no-auto-server     Do not auto-launch server if not detected
  --save-pages         Save converted page images as JPG files alongside the PDF
```

### Examples

* **Save intermediate page images**:
  ```bash
  python ocr.py manual.pdf --save-pages
  ```
  Generates `manual_page_1.jpg`, `manual_page_2.jpg`, etc., alongside `manual.md`.

* **Keep server active across runs**:
  ```bash
  python ocr.py doc1.pdf --keep-server
  python ocr.py doc2.pdf
  ```

---

## 🖥️ Running the Server Standalone (Optional)

If you prefer to keep `llama-server` running persistently in a separate terminal:

```bash
./start_server.sh
```

### Options:
* `-p, --port <port>`: Port to listen on (default: `1234`)
* `-h, --host <host>`: Host to bind to (default: `127.0.0.1`)
* `-g, --ngl <layers>`: GPU layers to offload (default: `99` with NVIDIA GPU, `0` for CPU)
* `-c, --ctx-size <size>`: Context window (default: `4096`, tuned for single document page)
* `-np, --parallel <n>`: Parallel inference slots (default: `1`)
* `-a, --alias <name>`: Model alias (default: `allenai/olmocr-2-7b-1025`)
* `--bin <path>`: Explicit path to `llama-server` binary

When running standalone, `ocr.py` will automatically connect to it without starting a second instance and will leave it running when finished.

---

## 📁 Repository Structure

```text
├── ocr.py               # Main CLI script for sequential OCR processing
├── start_server.sh      # Launcher script for llama-server with CUDA auto-detection
├── download_model.sh    # Downloader script for olmOCR model & projector weights
├── install.sh           # System and virtual environment setup script
├── requirements.txt     # Python dependency specifications
├── .gitignore           # Excludes models, caches, and output files
├── README.md            # Project documentation
└── models/              # Directory for downloaded GGUF weights (gitignored)
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
The olmOCR model weights are provided under their respective licenses by [Allen Institute for AI (AI2)](https://allenai.org).
