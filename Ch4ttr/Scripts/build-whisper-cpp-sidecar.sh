#!/bin/sh
# Builds a self-contained whisper-cli (Core ML + static ggml) and copies it to Sidecars/whisper-cpp.
# Requires: CMake, Xcode CLTs. Run from the Ch4ttr app folder or pass WHISPER_ROOT.
set -e
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_SRC="${WHISPER_ROOT:-"$ROOT_DIR/../.whisper.cpp"}"
OUT_NAME="whisper-cpp"
BUILD_DIR="$WHISPER_SRC/build-ch4ttr-coreml-static"
DEST="$ROOT_DIR/Sidecars/$OUT_NAME"

if [ ! -f "$WHISPER_SRC/CMakeLists.txt" ]; then
  echo "whisper.cpp not found at: $WHISPER_SRC" >&2
  echo "Set WHISPER_ROOT to your whisper.cpp clone." >&2
  exit 1
fi

cmake -S "$WHISPER_SRC" -B "$BUILD_DIR" \
  -DWHISPER_COREML=1 \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" --config Release

mkdir -p "$(dirname "$DEST")"
install -m 0755 "$BUILD_DIR/bin/whisper-cli" "$DEST"
echo "Installed: $DEST"
otool -L "$DEST" | head -5
