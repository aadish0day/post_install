#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$HOME/Documents/Crack/Burpsuite-Professional"
BURP_VERSION="2026"

echo "Installing Burp Suite Professional..."

if ! dpkg -l | grep -q "^ii  openjdk-21-jre "; then
    echo "Installing Java 21..."
    sudo nala install -y openjdk-21-jre
fi

echo "Setting Java 21 as default..."
sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java 2>/dev/null || true

echo "Installing dependencies..."
sudo nala install -y git aria2

if [ -d "$REPO_DIR" ]; then
    rm -rf "$REPO_DIR"
fi

echo "Cloning Burpsuite-Professional..."
git clone https://github.com/xiv3r/Burpsuite-Professional.git "$REPO_DIR"

cd "$REPO_DIR"

echo "Downloading Burp Suite Professional Latest..."
aria2c --check-certificate=false -o "burpsuite_pro_v$BURP_VERSION.jar" "https://github.com/xiv3r/Burpsuite-Professional/releases/download/burpsuite-pro/burpsuite_pro_v$BURP_VERSION.jar"

echo "Copying local config files..."
cp "$SCRIPT_DIR/.config.ini" "$REPO_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/images.png" "$REPO_DIR/" 2>/dev/null || true

echo "Creating launcher..."
mkdir -p "$HOME/.local/bin"
tee "$HOME/.local/bin/burpsuitepro" > /dev/null << EOF
#!/bin/bash
java --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:$REPO_DIR/loader.jar -noverify -jar $REPO_DIR/burpsuite_pro_v$BURP_VERSION.jar
EOF
chmod +x "$HOME/.local/bin/burpsuitepro"

echo "Creating desktop entry..."
mkdir -p "$HOME/.local/share/applications"
tee "$HOME/.local/share/applications/burpsuitepro.desktop" > /dev/null << EOF
[Desktop Entry]
Name=Burp Suite Professional
Comment=Burp Suite Professional - Web Application Security Testing
Exec=$HOME/.local/bin/burpsuitepro
Icon=$REPO_DIR/images.png
Terminal=false
Type=Application
Categories=Network;Security;
Keywords=burp;suite;pro;web;security;scanner;
Path=$REPO_DIR
EOF

echo "Starting Key loader.jar..."
(java -jar "$REPO_DIR/loader.jar") &

echo "Starting Burp Suite Professional..."
("$HOME/.local/bin/burpsuitepro") &

echo "Burp Suite Professional installation complete!"
