#!/usr/bin/env bash
set -e

echo "=== Installing System Dependencies ==="

# 1. Detect OS and install Poppler
OS="$(uname -s)"
case "${OS}" in
    Linux*)
        if command -v apt-get &> /dev/null; then
            echo "Detected Debian/Ubuntu. Installing poppler-utils..."
            sudo apt-get update && sudo apt-get install -y poppler-utils python3-venv python3-pip
        elif command -v dnf &> /dev/null; then
            echo "Detected RHEL/Fedora. Installing poppler-utils..."
            sudo dnf install -y poppler-utils
        elif command -v pacman &> /dev/null; then
            echo "Detected Arch Linux. Installing poppler..."
            sudo pacman -S --noconfirm poppler
        else
            echo "Package manager not auto-detected. Ensure 'poppler-utils' is installed."
        fi
        ;;
    Darwin*)
        if command -v brew &> /dev/null; then
            echo "Detected macOS. Installing poppler via Homebrew..."
            brew install poppler
        else
            echo "Homebrew not found. Please install Homebrew (https://brew.sh) then run 'brew install poppler'."
            exit 1
        fi
        ;;
    *)
        echo "Unsupported OS: ${OS}. Please install Poppler manually."
        ;;
esac

# 2. Create Python virtual environment
echo -e "\n=== Setting up Python Virtual Environment ==="
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "Created virtual environment in ./venv"
fi

# 3. Activate environment and install packages
source venv/bin/activate
echo "Upgrading pip..."
pip install --upgrade pip

echo "Installing required Python packages..."
pip install -r requirements.txt

echo -e "\n=== Setup Complete! ==="
echo "To run your Python script, activate the environment first:"
echo "  source venv/bin/activate"
echo "  python ocr.py <file_path_1> [file_path_2 ...]"

