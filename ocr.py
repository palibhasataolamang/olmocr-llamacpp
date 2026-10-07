import argparse
import base64
import io
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from openai import OpenAI
from pdf2image import convert_from_path, pdfinfo_from_path
from PIL import Image

# Configuration
BASE_URL = "http://localhost:1234/v1"
API_KEY = "lm-studio"  # Any non-empty string for local servers
MODEL_NAME = "allenai/olmocr-2-7b-1025"
PROMPT = "Perform high-fidelity OCR on this document and structure the output into clean markdown."
DEFAULT_CTX_SIZE = 4096


def is_server_ready(base_url: str) -> bool:
    """Check if the OpenAI-compatible server endpoint is reachable and responding."""
    try:
        url = f"{base_url.rstrip('/')}/models"
        req = urllib.request.Request(url, headers={"User-Agent": "ocr-client"})
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            return resp.status == 200
    except Exception:
        return False


def start_local_server(base_url: str, ctx_size: int = DEFAULT_CTX_SIZE, timeout: int = 60):
    """Launch start_server.sh with context size and slot count tuned for a single execution."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    server_script = os.path.join(script_dir, "start_server.sh")

    if not os.path.isfile(server_script):
        raise FileNotFoundError(f"Server launcher script not found at {server_script}")

    parsed_url = urllib.parse.urlparse(base_url)
    port = parsed_url.port or 1234
    host = parsed_url.hostname or "127.0.0.1"

    log_path = os.path.join(script_dir, "server.log")
    log_file = open(log_path, "w", encoding="utf-8")

    cmd = [
        server_script,
        "--host", host,
        "--port", str(port),
        "--ctx-size", str(ctx_size),
        "--parallel", "1",
    ]

    print(f"-> Launching server: {' '.join(cmd)}")
    print(f"-> Server logs: {log_path}")

    proc = subprocess.Popen(
        cmd,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        cwd=script_dir,
    )

    start_time = time.time()
    print("Waiting for server to become ready...", end="", flush=True)

    while time.time() - start_time < timeout:
        if proc.poll() is not None:
            log_file.close()
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                tail = "".join(f.readlines()[-20:])
            raise RuntimeError(
                f"\nServer process exited unexpectedly (code {proc.returncode}):\n{tail}"
            )

        if is_server_ready(base_url):
            print(" Ready!\n")
            return proc, log_file

        print(".", end="", flush=True)
        time.sleep(1.0)

    proc.terminate()
    log_file.close()
    raise TimeoutError(f"\nServer failed to respond within {timeout}s. Check {log_path}.")


def stop_local_server(proc: subprocess.Popen, log_file):
    """Gracefully terminate the locally started server process."""
    if proc and proc.poll() is None:
        print("\nStopping locally launched server...")
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        print("✓ Server stopped.")

    if log_file and not log_file.closed:
        log_file.close()


def pil_to_jpeg_data_url(img: Image.Image) -> str:
    """Convert PIL image to a JPEG base64 Data URL."""
    buffer = io.BytesIO()
    if img.mode in ("RGBA", "P"):
        img = img.convert("RGB")
    img.save(buffer, format="JPEG", quality=95)
    encoded_image = base64.b64encode(buffer.getvalue()).decode("utf-8")
    return f"data:image/jpeg;base64,{encoded_image}"


def transcribe_image(image_data_url: str, client: OpenAI) -> str:
    """Send a vision chat completion request and return transcribed markdown text."""
    response = client.chat.completions.create(
        model=MODEL_NAME,
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {"url": image_data_url},
                    },
                ],
            }
        ],
        temperature=0.1,
    )
    return response.choices[0].message.content or ""


def process_single_file(file_path: str, client: OpenAI, save_pages: bool = False) -> str:
    """Process a single file (image or multipage PDF) through OCR and save to one corresponding .md file."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    stem, ext = os.path.splitext(file_path)
    ext = ext.lower()
    page_texts = []

    if ext == ".pdf":
        print(f"Analyzing PDF '{file_path}'...")
        total_pages = None
        try:
            info = pdfinfo_from_path(file_path)
            total_pages = int(info.get("Pages", 1))
        except Exception:
            total_pages = None

        if total_pages is not None:
            print(f"-> PDF has {total_pages} page(s). Converting each page to JPG then transcribing...")
            for page_num in range(1, total_pages + 1):
                print(f"   [Page {page_num}/{total_pages}] Converting to JPG & OCR...")
                images = convert_from_path(file_path, first_page=page_num, last_page=page_num)
                if not images:
                    raise ValueError(f"Failed to convert page {page_num} of '{file_path}'")
                img = images[0]

                if save_pages:
                    jpg_path = f"{stem}_page_{page_num}.jpg"
                    img.save(jpg_path, format="JPEG", quality=95)
                    print(f"   [Saved JPG] {jpg_path}")

                image_data_url = pil_to_jpeg_data_url(img)
                text = transcribe_image(image_data_url, client)
                page_texts.append(text)
        else:
            print("-> Converting all PDF pages to JPG...")
            images = convert_from_path(file_path)
            if not images:
                raise ValueError(f"Failed to convert pages from '{file_path}'")
            total_pages = len(images)
            for page_num, img in enumerate(images, 1):
                print(f"   [Page {page_num}/{total_pages}] Converting to JPG & OCR...")
                if save_pages:
                    jpg_path = f"{stem}_page_{page_num}.jpg"
                    img.save(jpg_path, format="JPEG", quality=95)
                    print(f"   [Saved JPG] {jpg_path}")

                image_data_url = pil_to_jpeg_data_url(img)
                text = transcribe_image(image_data_url, client)
                page_texts.append(text)

    elif ext in [".png", ".jpg", ".jpeg", ".webp", ".bmp"]:
        print(f"Opening image file '{file_path}'...")
        img = Image.open(file_path)
        image_data_url = pil_to_jpeg_data_url(img)
        text = transcribe_image(image_data_url, client)
        page_texts.append(text)
    else:
        raise ValueError(f"Unsupported file format: {ext}")

    # Combine all pages into a single Markdown file per PDF/image
    if len(page_texts) == 1:
        combined_content = page_texts[0].strip() + "\n"
    else:
        combined_content = "\n\n---\n\n".join(t.strip() for t in page_texts if t.strip()) + "\n"

    output_path = f"{stem}.md"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(combined_content)

    pages_desc = f"{len(page_texts)} page(s)" if ext == ".pdf" else "1 image"
    print(f"✓ Finished: {file_path} ({pages_desc}) -> {output_path}")
    return output_path


def main():
    parser = argparse.ArgumentParser(description="OCR images or PDFs sequentially using an OpenAI-compatible endpoint.")
    parser.add_argument(
        "file_paths",
        nargs="+",
        help="One or more paths to input image or PDF files",
    )
    parser.add_argument(
        "--base-url",
        type=str,
        default=BASE_URL,
        help=f"OpenAI-compatible base URL (default: {BASE_URL})",
    )
    parser.add_argument(
        "--api-key",
        type=str,
        default=API_KEY,
        help="API Key (default: 'lm-studio')",
    )
    parser.add_argument(
        "--ctx-size",
        type=int,
        default=DEFAULT_CTX_SIZE,
        help=f"Context size for auto-launched server (default: {DEFAULT_CTX_SIZE})",
    )
    parser.add_argument(
        "--keep-server",
        action="store_true",
        help="Keep the auto-launched server running after processing completes",
    )
    parser.add_argument(
        "--no-auto-server",
        action="store_true",
        help="Do not auto-launch server if not detected",
    )
    parser.add_argument(
        "--save-pages",
        action="store_true",
        help="Save converted page images as JPG files alongside the PDF",
    )
    args = parser.parse_args()

    server_proc = None
    server_log = None

    try:
        if is_server_ready(args.base_url):
            print(f"✓ Connected to running server at {args.base_url}")
        else:
            if args.no_auto_server:
                raise ConnectionError(
                    f"Server not detected at {args.base_url} and --no-auto-server was specified."
                )
            print(f"Server not detected at {args.base_url}. Auto-launching server...")
            server_proc, server_log = start_local_server(
                base_url=args.base_url,
                ctx_size=args.ctx_size,
            )

        client = OpenAI(base_url=args.base_url, api_key=args.api_key)

        total_files = len(args.file_paths)
        print(f"Processing {total_files} file(s) one by one...\n")

        for idx, path in enumerate(args.file_paths, 1):
            print(f"[{idx}/{total_files}] Processing: {path}")
            try:
                process_single_file(path, client, save_pages=args.save_pages)
            except Exception as err:
                print(f"✗ Failed processing '{path}': {err}", file=sys.stderr)

        print("\nProcessing completed.")

    except Exception as err:
        print(f"\nExecution failed: {err}", file=sys.stderr)
    finally:
        if server_proc is not None and not args.keep_server:
            stop_local_server(server_proc, server_log)
        elif server_proc is not None and args.keep_server:
            print(f"Server remains running in background (PID: {server_proc.pid}).")
            if server_log and not server_log.closed:
                server_log.close()


if __name__ == "__main__":
    main()
