#!/bin/bash
set -euo pipefail

# ── Configuration ──
TEAM_ID="G87X787LQ9"
APP_NAME="AuphonicApp"
BUNDLE_ID="com.auphonic.app"
ENTITLEMENTS="$(dirname "$0")/AuphonicApp.entitlements"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/AuphonicApp_artefacts/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
SIGNING_IDENTITY="Developer ID Application: Kubeile und Pardeyke GbR (${TEAM_ID})"

# ── Notarization credentials ──
# Store credentials once with:
#   xcrun notarytool store-credentials "AuphonicApp" \
#       --apple-id YOUR_APPLE_ID --team-id G87X787LQ9 --password APP_SPECIFIC_PASSWORD
NOTARY_PROFILE="AuphonicApp"

echo "═══════════════════════════════════════"
echo " Building ${APP_NAME}"
echo "═══════════════════════════════════════"

# 1. Clean build
cmake -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build "${BUILD_DIR}" --config Release --parallel

echo ""
echo "✓ Build complete"

# 2. Verify the app exists
if [ ! -d "${APP_PATH}" ]; then
    echo "✗ App not found at ${APP_PATH}"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════"
echo " Signing"
echo "═══════════════════════════════════════"

# 3. Sign with hardened runtime
codesign --deep --force --options runtime \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${SIGNING_IDENTITY}" \
    --timestamp \
    "${APP_PATH}"

echo "✓ Signed"

# 4. Verify signature
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tail -1
spctl --assess --type exec --verbose "${APP_PATH}" 2>&1 || true

echo ""
echo "═══════════════════════════════════════"
echo " Creating DMG"
echo "═══════════════════════════════════════"

# 5. Remove old DMG
rm -f "${DMG_PATH}"

# 6. Create DMG with Applications symlink
STAGING_DIR=$(mktemp -d)
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo "✓ DMG created at ${DMG_PATH}"

# 7. Sign DMG
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"
echo "✓ DMG signed"

echo ""
echo "═══════════════════════════════════════"
echo " Notarizing"
echo "═══════════════════════════════════════"

# 8. Submit for notarization
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

# 9. Staple the ticket
xcrun stapler staple "${DMG_PATH}"

echo ""
echo "═══════════════════════════════════════"
echo " ✓ Done!"
echo "═══════════════════════════════════════"
echo ""
echo " Distributable DMG: ${DMG_PATH}"
echo ""
