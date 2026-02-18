#!/bin/bash
set -euo pipefail

# ── Configuration ──
APP_NAME="AuphonicApp"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/AuphonicApp_artefacts/Release/${APP_NAME}.app"
APP_BINARY="${APP_PATH}/Contents/MacOS/${APP_NAME}"

echo "═══════════════════════════════════════"
echo " Building ${APP_NAME}"
echo "═══════════════════════════════════════"

cmake -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build "${BUILD_DIR}" --config Release --parallel

echo ""
echo "✓ Build complete"

# Verify the app exists
if [ ! -d "${APP_PATH}" ]; then
    echo "✗ App not found at ${APP_PATH}"
    exit 1
fi

echo ""
echo "── Architectures ──"
lipo -info "${APP_BINARY}"

echo ""
echo "── Minimum macOS version ──"
xcrun vtool -show-build "${APP_BINARY}"

echo ""
echo "── Linked libraries (non-system) ──"
otool -L "${APP_BINARY}" \
    | grep -v '/usr/lib\|/System/Library\|@rpath\|@executable_path' \
    || echo "  (none — all system or embedded)"

echo ""
echo "═══════════════════════════════════════"
echo " ✓ Done!  App at: ${APP_PATH}"
echo "═══════════════════════════════════════"
echo ""
