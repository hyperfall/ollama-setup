#!/bin/bash

set -e
set -o pipefail

# ───────────────────────────────────────────────
# 0. Load persistent environment variables
# ───────────────────────────────────────────────
if [ -f /workspace/env.sh ]; then
    echo "🔄 Loading environment from /workspace/env.sh..."
    source /workspace/env.sh
else
    echo "⚠️ No /workspace/env.sh found. Creating a placeholder..."
    echo 'export NGROK_AUTH_TOKEN="your_token_here"' > /workspace/env.sh
    chmod 600 /workspace/env.sh
fi

echo "🔧 [BOOT] Initializing VIREX Runtime on RunPod..."

# ───────────────────────────────────────────────
# 1. Install base + editor dependencies
# ───────────────────────────────────────────────
echo "📦 Installing system packages..."
DEBIAN_FRONTEND=noninteractive apt update -yq && apt install -y \
    curl gnupg openssh-server unzip libssl-dev software-properties-common

apt-add-repository universe -y
apt update -yq && apt install -y nano vim

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
# 3. Inject GitHub SSH key
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
# 4. Prepare Ollama
# ───────────────────────────────────────────────
OLLAMA_BIN="/workspace/ollama/bin/ollama"
mkdir -p /workspace/ollama
chmod -R 755 /workspace/ollama
if [ ! -f "$OLLAMA_BIN" ]; then
    echo "🧠 Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | OLLAMA_DIR=/workspace/ollama sh
else
    echo "🧠 Ollama already installed — skipping."
fi

# ───────────────────────────────────────────────
# 5. Start Ollama server
# ───────────────────────────────────────────────
export OLLAMA_HOST=0.0.0.0
OLLAMA_LOG="/workspace/ollama/ollama.log"
if ! pgrep -f "ollama serve" > /dev/null; then
    echo "🚀 Starting Ollama server..."
    echo "" > "$OLLAMA_LOG"
    nohup "$OLLAMA_BIN" serve > "$OLLAMA_LOG" 2>&1 &
    sleep 5
else
    echo "🟢 Ollama already running — skipping."
fi

# ───────────────────────────────────────────────
# 6. Pull Mistral model
# ───────────────────────────────────────────────
if ! "$OLLAMA_BIN" list | awk '{print $1}' | grep -q '^mistral:latest$'; then
    echo "📦 Pulling Mistral model..."
    "$OLLAMA_BIN" pull mistral
else
    echo "📦 Mistral already exists — skipping."
fi

# ───────────────────────────────────────────────
# 7. Install Python requirement
# ───────────────────────────────────────────────
if ! python3 -c "import ddgs" &> /dev/null; then
    echo "📚 Installing ddgs Python module..."
    pip install ddgs >/dev/null 2>&1
else
    echo "📚 ddgs already installed — skipping."
fi

# ───────────────────────────────────────────────
# 8. Persistent .bashrc setup
# ───────────────────────────────────────────────
BASHRC_LINE1="source /workspace/env.sh"
BASHRC_LINE2="bash /workspace/init.sh"
grep -Fxq "$BASHRC_LINE1" ~/.bashrc || echo "$BASHRC_LINE1" >> ~/.bashrc
grep -Fxq "$BASHRC_LINE2" ~/.bashrc || echo "$BASHRC_LINE2" >> ~/.bashrc

# ───────────────────────────────────────────────
# 9. Setup Ngrok tunnel (persistent config)
# ───────────────────────────────────────────────
echo "🌐 Setting up Ngrok..."

NGROK_CONFIG_PATH="/workspace/ngrok/ngrok.yml"
mkdir -p /workspace/ngrok
export NGROK_CONFIG="$NGROK_CONFIG_PATH"

if ! command -v ngrok &> /dev/null; then
    echo "🔧 Installing Ngrok..."
    curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list
    apt update && apt install -y ngrok
fi

# Prevent ngrok from auto-updating to avoid breaking init.sh
mkdir -p /workspace/ngrok/.ngrok2
touch /workspace/ngrok/.ngrok2/no-autoupdate


if [ -z "$NGROK_AUTH_TOKEN" ]; then
    echo "❌ ERROR: NGROK_AUTH_TOKEN not set in /workspace/env.sh"
else
    echo "🔐 Writing authtoken to $NGROK_CONFIG_PATH"
    ngrok config add-authtoken "$NGROK_AUTH_TOKEN" --config "$NGROK_CONFIG_PATH"

    echo "🚇 Starting Ngrok tunnel..."
    nohup ngrok http 11434 --config "$NGROK_CONFIG_PATH" > /workspace/ngrok.log 2>&1 &
    sleep 5
    OLLAMA_PUBLIC_URL=$(grep -o 'https://[a-z0-9]*\.ngrok.io' /workspace/ngrok.log | head -n 1)
    if [ -n "$OLLAMA_PUBLIC_URL" ]; then
        echo "$OLLAMA_PUBLIC_URL" > /workspace/ollama_public_url.txt
        echo "🌍 Public URL: $OLLAMA_PUBLIC_URL"
    else
        echo "⚠️ Ngrok URL not detected — check /workspace/ngrok.log"
    fi
fi

# ───────────────────────────────────────────────
# ✅ Final echo for external log access
# ───────────────────────────────────────────────
if [ -z "$OLLAMA_PUBLIC_URL" ] && [ -f /workspace/ollama_public_url.txt ]; then
    OLLAMA_PUBLIC_URL=$(cat /workspace/ollama_public_url.txt)
fi

if [ -n "$OLLAMA_PUBLIC_URL" ]; then
    echo ""
    echo "🔗 Ollama API ready at: $OLLAMA_PUBLIC_URL"
    echo "🧪 Test with: curl $OLLAMA_PUBLIC_URL/api/generate -d '{\"model\":\"mistral\",\"prompt\":\"hello\"}'"
    echo ""
else
    echo "⚠️ Public Ngrok URL still not available."
fi

echo "✅ Setup complete. Ollama + SSH + Ngrok persistent and ready."
tail -f /dev/null
