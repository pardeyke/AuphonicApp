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
echo " Notarizing .app"
echo "═══════════════════════════════════════"

# 5. Zip the .app for submission (notarytool requires a zip for .app bundles)
APP_ZIP="${BUILD_DIR}/${APP_NAME}.zip"
rm -f "${APP_ZIP}"
ditto -c -k --keepParent "${APP_PATH}" "${APP_ZIP}"

# 6. Submit .app for notarization
xcrun notarytool submit "${APP_ZIP}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

rm -f "${APP_ZIP}"

# 7. Staple the ticket directly onto the .app
xcrun stapler staple "${APP_PATH}"
echo "✓ .app notarized and stapled"

echo ""
echo "═══════════════════════════════════════"
echo " Creating DMG"
echo "═══════════════════════════════════════"

# 8. Remove old DMG
rm -f "${DMG_PATH}"

# 9. Create DMG with Applications symlink (contains the already-stapled .app)
STAGING_DIR=$(mktemp -d)
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo "✓ DMG created at ${DMG_PATH}"

# 10. Sign DMG
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"
echo "✓ DMG signed"

echo ""
echo "═══════════════════════════════════════"
echo " Notarizing DMG"
echo "═══════════════════════════════════════"

# 11. Submit DMG for notarization
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

# 12. Staple the ticket onto the DMG
xcrun stapler staple "${DMG_PATH}"
echo "✓ DMG notarized and stapled"

echo ""
echo "═══════════════════════════════════════"
echo " Verification"
echo "═══════════════════════════════════════"

APP_BINARY="${APP_PATH}/Contents/MacOS/${APP_NAME}"

echo ""
echo "── Staple validation ──"
xcrun stapler validate "${APP_PATH}"  && echo "✓ .app staple valid"  || echo "✗ .app staple INVALID"
xcrun stapler validate "${DMG_PATH}"  && echo "✓ DMG staple valid"   || echo "✗ DMG staple INVALID"

echo ""
echo "── Gatekeeper assessment ──"
spctl --assess --type exec --verbose "${APP_PATH}" 2>&1
spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}" 2>&1

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
echo " ✓ Done!"
echo "═══════════════════════════════════════"
echo ""
echo " Distributable DMG: ${DMG_PATH}"
echo ""
