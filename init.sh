#!/bin/bash

echo "🔧 Updating and installing base dependencies..."
apt update && apt install -y curl gnupg openssh-server unzip libssl-dev

echo "🔐 Setting up SSH..."
mkdir -p /var/run/sshd
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
service ssh restart

# ✅ Setup GitHub public key
echo "🔑 Installing authorized GitHub SSH key..."
mkdir -p /workspace/.ssh
curl -fsSL https://github.com/rxhlrr.keys -o /workspace/.ssh/authorized_keys

# ✅ Set key on startup
mkdir -p ~/.ssh
cp /workspace/.ssh/authorized_keys ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

echo "📁 Ensuring Ollama directory exists..."
mkdir -p /workspace/ollama

# ✅ Only install Ollama if not present
if [ ! -f /workspace/ollama/bin/ollama ]; then
    echo "🧠 Installing Ollama to /workspace/ollama..."
    curl -fsSL https://ollama.com/install.sh | OLLAMA_DIR=/workspace/ollama sh
else
    echo "🧠 Ollama already installed. Skipping."
fi

# ✅ Start Ollama server in background (with log reset)
echo "🚀 Starting Ollama server..."
echo "" > /workspace/ollama/ollama.log
nohup /workspace/ollama/bin/ollama serve > /workspace/ollama/ollama.log 2>&1 &

# ✅ Only pull Mistral if not already downloaded
if ! /workspace/ollama/bin/ollama list | grep -q 'mistral'; then
    echo "📦 Pulling Mistral model..."
    /workspace/ollama/bin/ollama pull mistral
else
    echo "📦 Mistral already downloaded. Skipping."
fi

# ✅ Ensure autostart in .bashrc only added once
if ! grep -Fxq "bash /workspace/init.sh" ~/.bashrc; then
    echo "bash /workspace/init.sh" >> ~/.bashrc
    echo "🧠 Auto-start added to .bashrc ✅"
else
    echo "⚙️ Auto-start already configured."
fi

echo "✅ Setup complete. Ollama + Mistral ready."
