#!/bin/bash
set -e

echo "🚀 Starting Flutter build for Vercel..."

# Save the original directory (repository root)
ORIGINAL_DIR="$(pwd)"
echo "Original directory: $ORIGINAL_DIR"

# Install Flutter SDK
echo "📦 Installing Flutter SDK..."
# Use latest stable Flutter that includes Dart 3.9.2+
FLUTTER_VERSION="3.27.1"
FLUTTER_SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# Create directory for Flutter
mkdir -p "$HOME/flutter"
cd "$HOME"

# Download and extract Flutter
# Use git clone to get latest stable (which has Dart 3.9.2+)
echo "Cloning Flutter SDK (stable branch)..."
if [ ! -d "$HOME/flutter" ] || [ ! -f "$HOME/flutter/bin/flutter" ]; then
  echo "Flutter not found, cloning..."
  rm -rf "$HOME/flutter" 2>/dev/null || true
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter" || {
    echo "Git clone failed, trying direct download..."
    rm -rf "$HOME/flutter" 2>/dev/null || true
    curl -L "$FLUTTER_SDK_URL" -o flutter.tar.xz || exit 1
    tar -xf flutter.tar.xz || exit 1
    rm flutter.tar.xz
  }
  
  # Verify clone/download succeeded
  if [ ! -d "$HOME/flutter" ]; then
    echo "Error: Flutter directory was not created"
    exit 1
  fi
  
  echo "Flutter directory created, checking contents..."
  ls -la "$HOME/flutter" | head -20 || true
fi

# Fix git safe directory issue (Vercel runs as root) - do this BEFORE adding to PATH
git config --global --add safe.directory /vercel/flutter || true
git config --global --add safe.directory "$HOME/flutter" || true

# Add Flutter to PATH
export PATH="$HOME/flutter/bin:$PATH"

# Verify Flutter binary exists
if [ ! -f "$HOME/flutter/bin/flutter" ]; then
  echo "Error: Flutter binary not found at $HOME/flutter/bin/flutter"
  ls -la "$HOME/flutter/bin/" || true
  exit 1
fi

# Make flutter executable
chmod +x "$HOME/flutter/bin/flutter" || true

# Accept Flutter licenses
"$HOME/flutter/bin/flutter" doctor --android-licenses || true

# Verify Flutter installation
echo "Verifying Flutter installation..."
"$HOME/flutter/bin/flutter" --version || exit 1

# Navigate back to repository root
echo "Navigating back to repository root: $ORIGINAL_DIR"
cd "$ORIGINAL_DIR" || {
  echo "Error: Could not navigate back to repository root"
  echo "Trying alternative: looking for po_processor_app in current location"
  # Try to find po_processor_app from current location
  if [ -d "po_processor_app" ]; then
    echo "Found po_processor_app in current directory"
  else
    # List current directory to debug
    echo "Current directory: $(pwd)"
    echo "Directory contents:"
    ls -la
    exit 1
  fi
}

# Verify we're in the right place
echo "Current directory: $(pwd)"
echo "Checking for po_processor_app directory..."
if [ ! -d "po_processor_app" ]; then
  echo "Error: po_processor_app directory not found"
  echo "Current directory contents:"
  ls -la
  exit 1
fi

# Navigate to app directory
echo "Navigating to po_processor_app..."
cd po_processor_app
echo "Now in: $(pwd)"

# Get dependencies
echo "📚 Getting Flutter dependencies..."
flutter pub get || exit 1

# Build web app
echo "🔨 Building Flutter web app..."
flutter build web --release || exit 1

echo "✅ Build complete!"

