#!/bin/bash

set -e  # Exit on error
set -o pipefail

echo "🔧 [BOOT] Initializing VIREX Runtime on RunPod..."

# ───────────────────────────────────────────────
# 1. Install system dependencies (if apt is fresh)
# ───────────────────────────────────────────────
echo "📦 Installing base dependencies (curl, ssh, unzip)..."
DEBIAN_FRONTEND=noninteractive apt update -yq && apt install -y curl gnupg openssh-server unzip libssl-dev

# ───────────────────────────────────────────────
# 2. Setup SSH daemon
# ───────────────────────────────────────────────
echo "🔐 Configuring SSH access..."
mkdir -p /var/run/sshd
SSHD_CONFIG="/etc/ssh/sshd_config"

grep -q "PermitRootLogin yes" "$SSHD_CONFIG" || echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
grep -q "PasswordAuthentication no" "$SSHD_CONFIG" || echo "PasswordAuthentication no" >> "$SSHD_CONFIG"

service ssh restart

# ───────────────────────────────────────────────
# 3. Inject GitHub SSH key (for root access)
# ───────────────────────────────────────────────
if [ ! -f /root/.ssh/authorized_keys ]; then
    echo "🔑 Installing GitHub public key from hyperfall..."
    mkdir -p /root/.ssh
    curl -fsSL https://github.com/hyperfall.keys -o /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
else
    echo "🔑 SSH key already present — skipping."
fi

# ───────────────────────────────────────────────
# 4. Prepare persistent Ollama install path
# ───────────────────────────────────────────────
OLLAMA_BIN="/workspace/ollama/bin/ollama"

echo "📁 Verifying Ollama installation path..."
mkdir -p /workspace/ollama
chmod -R 755 /workspace/ollama

if [ ! -f "$OLLAMA_BIN" ]; then
    echo "🧠 Installing Ollama into /workspace/ollama..."
    curl -fsSL https://ollama.com/install.sh | OLLAMA_DIR=/workspace/ollama sh
else
    echo "🧠 Ollama already installed — skipping."
fi

# ───────────────────────────────────────────────
# 5. Start Ollama server in background
# ───────────────────────────────────────────────
export OLLAMA_HOST=0.0.0.0
OLLAMA_LOG="/workspace/ollama/ollama.log"

if ! pgrep -f "ollama serve" > /dev/null; then
    echo "🚀 Starting Ollama server on 0.0.0.0:11434..."
    echo "" > "$OLLAMA_LOG"
    nohup "$OLLAMA_BIN" serve > "$OLLAMA_LOG" 2>&1 &
    sleep 5
else
    echo "🟢 Ollama server already running — skipping."
fi

# ───────────────────────────────────────────────
# 6. Pull Mistral model (if not present)
# ───────────────────────────────────────────────
if ! "$OLLAMA_BIN" list | awk '{print $1}' | grep -q '^mistral:latest$'; then
    echo "📦 Pulling Mistral model..."
    "$OLLAMA_BIN" pull mistral
else
    echo "📦 Mistral model already exists — skipping."
fi

# ───────────────────────────────────────────────
# 7. Install Python requirements (only ddgs)
# ───────────────────────────────────────────────
if ! python3 -c "import ddgs" &> /dev/null; then
    echo "📚 Installing Python package: ddgs..."
    pip install ddgs >/dev/null 2>&1
else
    echo "📚 ddgs Python module already installed — skipping."
fi

# ───────────────────────────────────────────────
# 8. Autostart this script in future terminals
# ───────────────────────────────────────────────
BASHRC_LINE="bash /workspace/init.sh"
if ! grep -Fxq "$BASHRC_LINE" ~/.bashrc; then
    echo "$BASHRC_LINE" >> ~/.bashrc
    echo "🧠 Added auto-start to ~/.bashrc ✅"
else
    echo "⚙️ Auto-start already exists in ~/.bashrc"
fi

# ───────────────────────────────────────────────
# Done
# ───────────────────────────────────────────────
echo "✅ Setup complete. Ollama + Mistral + SSH ready."

# Keep container alive
tail -f /dev/null
