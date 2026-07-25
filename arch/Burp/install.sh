#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$HOME/Documents/Crack/Burpsuite-Professional"
BURP_VERSION="2026"
JAR_NAME="burpsuite_pro_v$BURP_VERSION.jar"
DOWNLOAD_URL="https://github.com/xiv3r/Burpsuite-Professional/releases/download/burpsuite-pro/$JAR_NAME"

echo "=== Installing Burp Suite Professional (Arch Linux) ==="

# 1. Dependency installation (Pacman handles idempotency via --needed)
echo "Installing dependencies..."
sudo pacman -S --noconfirm --needed jdk21-openjdk git aria2

echo "Setting Java 21 as default..."
sudo archlinux-java set java-21-openjdk 2>/dev/null || sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk/bin/java 2>/dev/null || true

# 2. Repository preparation
if [ -d "$REPO_DIR" ]; then
    echo "Cleaning existing repository at $REPO_DIR..."
    rm -rf "$REPO_DIR"
fi

echo "Cloning Burpsuite-Professional repo..."
git clone https://github.com/xiv3r/Burpsuite-Professional.git "$REPO_DIR"

cd "$REPO_DIR"

# 3. Downloading Burp Suite Pro JAR
echo "Downloading Burp Suite Professional Latest ($JAR_NAME)..."
aria2c --check-certificate=false -s 16 -x 16 -k 1M -o "$JAR_NAME" "$DOWNLOAD_URL"

# Calculate and display checksums
if [ -f "$JAR_NAME" ]; then
    echo "--- File Checksums ---"
    echo "SHA256: $(sha256sum "$JAR_NAME" | cut -d' ' -f1)"
    echo "MD5:    $(md5sum "$JAR_NAME" | cut -d' ' -f1)"
fi

# 4. Copy local config files if present
echo "Copying local assets..."
cp "$SCRIPT_DIR/.config.ini" "$REPO_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/images.png" "$REPO_DIR/" 2>/dev/null || true

# 5. Create launcher binary script
mkdir -p "$HOME/.local/bin"
LAUNCHER_PATH="$HOME/.local/bin/burpsuitepro"

echo "Creating launcher script at $LAUNCHER_PATH..."
cat << EOF > "$LAUNCHER_PATH"
#!/bin/bash
java --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:$REPO_DIR/loader.jar -noverify -jar $REPO_DIR/$JAR_NAME "\$@"
EOF
chmod +x "$LAUNCHER_PATH"

sudo ln -sf "$LAUNCHER_PATH" /usr/local/bin/burpsuitepro 2>/dev/null || true

# 6. Create Desktop Shortcut
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/burpsuitepro.desktop"

echo "Creating desktop entry at $DESKTOP_FILE..."
cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=Burp Suite Professional
Comment=Burp Suite Professional - Web Application Security Testing
Exec=$LAUNCHER_PATH
Icon=$REPO_DIR/images.png
Terminal=false
Type=Application
Categories=Network;Security;
Keywords=burp;suite;pro;web;security;scanner;
Path=$REPO_DIR
EOF

# 7. Start Key Loader & Burp Suite Pro
if [ -f "$REPO_DIR/loader.jar" ]; then
    echo "Starting Key loader.jar in background..."
    (java -jar "$REPO_DIR/loader.jar") &
fi

echo "Starting Burp Suite Professional..."
"$LAUNCHER_PATH" &

echo "=== Burp Suite Professional (Arch Linux) installation completed successfully! ==="
