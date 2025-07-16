#!/bin/bash

echo "🔧 Updating and installing base dependencies..."
apt update && apt install -y curl gnupg openssh-server unzip libssl-dev

echo "🔐 Setting up SSH..."
mkdir -p /var/run/sshd

# Append SSH config only if not already present
if ! grep -q "PermitRootLogin yes" /etc/ssh/sshd_config; then
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
fi
if ! grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
fi
service ssh restart

# ✅ Setup GitHub public key only if not already present
if [ ! -f /root/.ssh/authorized_keys ]; then
    echo "🔑 Installing authorized GitHub SSH key..."
    mkdir -p /root/.ssh
    curl -fsSL https://github.com/hyperfall.keys -o /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
else
    echo "🔑 Authorized key already set. Skipping."
fi

echo "📁 Ensuring Ollama directory exists..."
mkdir -p /workspace/ollama
chown -R root:root /workspace/ollama
chmod -R 755 /workspace/ollama

# ✅ Only install Ollama if not present
if [ ! -f /workspace/ollama/bin/ollama ]; then
    echo "🧠 Installing Ollama to /workspace/ollama..."
    curl -fsSL https://ollama.com/install.sh | OLLAMA_DIR=/workspace/ollama sh
else
    echo "🧠 Ollama already installed. Skipping."
fi

# ✅ Start Ollama server only if not already running
if ! pgrep -f "ollama serve" > /dev/null; then
    echo "🚀 Starting Ollama server..."
    echo "" > /workspace/ollama/ollama.log
    nohup /workspace/ollama/bin/ollama serve > /workspace/ollama/ollama.log 2>&1 &
else
    echo "🟢 Ollama server already running. Skipping."
fi

# ✅ Only pull Mistral model if not already downloaded
if ! /workspace/ollama/bin/ollama list | awk '{print $1}' | grep -q '^mistral:latest$'; then
    echo "📦 Pulling Mistral model..."
    /workspace/ollama/bin/ollama pull mistral
else
    echo "📦 Mistral already downloaded. Skipping."
fi

# ✅ Ensure autostart is added to .bashrc only once
if ! grep -Fxq "bash /workspace/init.sh" ~/.bashrc; then
    echo "bash /workspace/init.sh" >> ~/.bashrc
    echo "🧠 Auto-start added to .bashrc ✅"
else
    echo "⚙️ Auto-start already configured."
fi
# ✅ Install Python search library for web augmentation
pip install pip install ddgs >/dev/null 2>&1

echo "✅ Setup complete. Ollama + Mistral ready."


