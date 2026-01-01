#!/bin/bash

if [ "$(uname)" = "Darwin" ]; then
  # macOS specific env:
  export PYTORCH_ENABLE_MPS_FALLBACK=1
  export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
elif [ "$(uname)" != "Linux" ]; then
  echo "Unsupported operating system."
  exit 1
fi

# Check if conda is available
if ! command -v conda >/dev/null 2>&1; then
  echo "Conda is not installed or not in PATH. Please install conda first."
  exit 1
fi

# Function to check and install aria2
check_and_install_aria2() {
  if ! command -v aria2c >/dev/null 2>&1; then
    echo "aria2 not found. Attempting to install..."
    if [ "$(uname)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
      brew install aria2
    elif [ "$(uname)" = "Linux" ]; then
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y aria2
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y aria2
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y aria2
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm aria2
      else
        echo "Error: Could not find a package manager to install aria2."
        echo "Please install aria2 manually: https://aria2.github.io/"
        exit 1
      fi
    else
      echo "Error: Unsupported operating system for automatic aria2 installation."
      echo "Please install aria2 manually: https://aria2.github.io/"
      exit 1
    fi
    
    # Verify installation
    if ! command -v aria2c >/dev/null 2>&1; then
      echo "Error: aria2 installation failed. Please install it manually."
      exit 1
    fi
    echo "aria2 installed successfully."
  else
    echo "aria2 is already installed."
  fi
}

# Function to detect NVIDIA GPU
detect_nvidia_gpu() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
      gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
      echo "${gpu_name}"
      return 0
    fi
  fi
  return 1
}

# Function to show GPU selection menu and return requirements file
select_gpu_config() {
  local default_choice=1
  local nvidia_detected=""
  local gpu_name=""
  
  # Detect NVIDIA GPU
  if gpu_name=$(detect_nvidia_gpu 2>/dev/null); then
    nvidia_detected=" (Detected: ${gpu_name})"
    default_choice=1
  fi
  
  echo "" >&2
  echo "==========================================" >&2
  echo "  GPU Configuration Selection" >&2
  echo "==========================================" >&2
  echo "" >&2
  echo "Please select your graphics card configuration:" >&2
  echo "" >&2
  echo "  1) NVIDIA graphics cards${nvidia_detected}" >&2
  echo "  2) AMD/Intel graphics cards on Windows (DirectML)" >&2
  echo "  3) Intel ARC graphics cards on Linux/WSL (Python 3.10)" >&2
  echo "  4) AMD graphics cards on Linux (ROCm)" >&2
  echo "" >&2
  
  if [ -n "${nvidia_detected}" ]; then
    echo "NVIDIA GPU detected and preselected." >&2
  fi
  echo "" >&2
  echo -n "Enter your choice [${default_choice}]: " >&2
  read choice
  
  # Use default if empty
  choice=${choice:-${default_choice}}
  
  case $choice in
    1)
      echo "Selected: NVIDIA graphics cards" >&2
      echo "requirements.txt"
      ;;
    2)
      echo "Selected: AMD/Intel graphics cards on Windows (DirectML)" >&2
      echo "requirements-dml.txt"
      ;;
    3)
      echo "Selected: Intel ARC graphics cards on Linux/WSL" >&2
      echo "requirements-ipex.txt"
      ;;
    4)
      echo "Selected: AMD graphics cards on Linux (ROCm)" >&2
      echo "requirements-amd.txt"
      ;;
    *)
      echo "Invalid choice. Using default: NVIDIA graphics cards" >&2
      echo "requirements.txt"
      ;;
  esac
}

# Always use "rvc" as the environment name
env_name="rvc"

# Check if conda environment exists
env_exists=false
if conda env list | grep -q "^${env_name} "; then
  env_exists=true
  echo "Activate conda environment: ${env_name}..."
  eval "$(conda shell.bash hook)"
  conda activate "${env_name}"
else
  echo "Create conda environment: ${env_name}..."
  # Create new conda environment with Python 3.10
  conda create -n "${env_name}" python=3.10 -y
  eval "$(conda shell.bash hook)"
  conda activate "${env_name}"
fi

# Check and install aria2 if needed
check_and_install_aria2

# Always show GPU selection menu
requirements_file=$(select_gpu_config)

# Install requirements if environment was just created
if [ "$env_exists" = false ]; then
  if [ -f "${requirements_file}" ]; then
    echo "Installing packages from ${requirements_file}..."
    # Remove aria2 from requirements file temporarily since it's a system package
    if grep -q "^aria2$" "${requirements_file}" 2>/dev/null; then
      temp_requirements=$(mktemp)
      grep -v "^aria2$" "${requirements_file}" > "${temp_requirements}"
      pip install -r "${temp_requirements}"
      rm "${temp_requirements}"
    else
      pip install -r "${requirements_file}"
    fi
  else
    echo "Warning: ${requirements_file} not found. Skipping package installation."
  fi
fi

# Download models
chmod +x tools/dlmodels.sh
./tools/dlmodels.sh

if [ $? -ne 0 ]; then
  exit 1
fi

# Run the main script
python infer-web.py --pycmd python
