#!/bin/bash
set -e

echo "🚀 Starting Flutter build for Vercel..."

# Install Flutter SDK
echo "📦 Installing Flutter SDK..."
FLUTTER_VERSION="3.24.5"
FLUTTER_SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# Create directory for Flutter
mkdir -p "$HOME/flutter"
cd "$HOME"

# Download and extract Flutter
echo "Downloading Flutter SDK..."
curl -L "$FLUTTER_SDK_URL" -o flutter.tar.xz || {
  echo "Failed to download Flutter SDK, trying alternative method..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter" || exit 1
}

if [ -f flutter.tar.xz ]; then
  tar -xf flutter.tar.xz || exit 1
  rm flutter.tar.xz
fi

# Add Flutter to PATH
export PATH="$HOME/flutter/bin:$PATH"

# Accept Flutter licenses
flutter doctor --android-licenses || true

# Verify Flutter installation
echo "Verifying Flutter installation..."
flutter --version || exit 1

# Navigate to app directory (Vercel sets VERCEL_SOURCE_DIR, fallback to current dir)
if [ -n "$VERCEL_SOURCE_DIR" ]; then
  cd "$VERCEL_SOURCE_DIR"
else
  cd "$(dirname "$0")"
fi
cd po_processor_app || {
  echo "Error: po_processor_app directory not found"
  ls -la
  exit 1
}

# Get dependencies
echo "📚 Getting Flutter dependencies..."
flutter pub get || exit 1

# Build web app
echo "🔨 Building Flutter web app..."
flutter build web --release || exit 1

echo "✅ Build complete!"

