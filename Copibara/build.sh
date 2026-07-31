#!/bin/bash
set -euo pipefail

# ============================================================
# Copibara — Build, Sign, Notarize & Staple Script
# Creates a Developer ID–signed .app bundle, a DMG installer,
# notarizes it with Apple, and staples the ticket.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load credentials from .env ────────────────────────────────
ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "❌ Missing ${ENV_FILE} — copy .env.example and fill in your credentials."
    exit 1
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"

# Validate required vars
for var in APPLE_ID APP_SPECIFIC_PASSWORD TEAM_ID SIGNING_IDENTITY; do
    if [ -z "${!var:-}" ]; then
        echo "❌ ${var} is not set in .env"
        exit 1
    fi
done

if [ "${APPLE_ID}" = "YOUR_APPLE_ID_EMAIL_HERE" ]; then
    echo "❌ Please set your real Apple ID email in .env"
    exit 1
fi

# ── Configuration ─────────────────────────────────────────────
APP_NAME="Copibara"
BUNDLE_ID="com.copibara.app"
VERSION="1.4.2"
BUILD_DIR="${SCRIPT_DIR}/.build/release"
APP_DIR="${SCRIPT_DIR}/dist/${APP_NAME}.app"
DMG_PATH="${SCRIPT_DIR}/dist/Copibara-Yapivo-v${VERSION}.dmg"

# ── Step 1: Build ─────────────────────────────────────────────
echo "🔨 Building ${APP_NAME} (release)..."
swift build -c release 2>&1

# ── Step 2: Create .app bundle ────────────────────────────────
echo "📦 Creating .app bundle..."
rm -rf "${SCRIPT_DIR}/dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy app icon
ICON_SRC="${SCRIPT_DIR}/Sources/Resources/AppIcon.icns"
if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
    echo "   ✅ App icon copied"
else
    echo "⚠️  No AppIcon.icns found at ${ICON_SRC} — building without icon"
fi

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Copy the SPM resource bundle (bundled models/assets) so Bundle.module resolves
# in the shipped .app — e.g. the waifu2x upscale model.
#
# It MUST go in Contents/Resources, not Contents/MacOS: a nested .bundle beside
# the executable makes codesign reject the whole app with "bundle format
# unrecognized, invalid, or unsuitable". Contents/Resources is both the valid
# layout and one of the paths Bundle.module searches (Bundle.main.resourceURL).
RES_BUNDLE="${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${RES_BUNDLE}" ]; then
    cp -R "${RES_BUNDLE}" "${APP_DIR}/Contents/Resources/"
    echo "   ✅ Resource bundle copied ($(basename "${RES_BUNDLE}"))"
fi

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Copibara</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# ── Step 3: Developer ID Code Signing ─────────────────────────
echo "🔏 Signing with Developer ID (hardened runtime)..."
codesign --force --deep --options runtime \
    --sign "${SIGNING_IDENTITY}" \
    --entitlements "${SCRIPT_DIR}/Copibara.entitlements" \
    --timestamp \
    "${APP_DIR}"
echo "   ✅ Signed: ${APP_DIR}"

# Verify signature
codesign --verify --deep --strict "${APP_DIR}" 2>&1
echo "   ✅ Signature verified"

# ── Step 4: Create DMG ────────────────────────────────────────
echo "💿 Creating DMG installer..."
rm -f "${DMG_PATH}"

DMG_STAGING="${SCRIPT_DIR}/dist/dmg_staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_DIR}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" 2>&1

rm -rf "${DMG_STAGING}"
echo "   ✅ DMG created: ${DMG_PATH}"

# Sign the DMG itself
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"
echo "   ✅ DMG signed"

# ── Step 5: Notarize ──────────────────────────────────────────
echo "📤 Submitting to Apple for notarization (this may take 1-5 minutes)..."
xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --password "${APP_SPECIFIC_PASSWORD}" \
    --team-id "${TEAM_ID}" \
    --wait 2>&1

echo "   ✅ Notarization approved"

# ── Step 6: Staple ────────────────────────────────────────────
echo "📎 Stapling notarization ticket to DMG..."
xcrun stapler staple "${DMG_PATH}" 2>&1
echo "   ✅ Stapled"

# ── Step 7: Release-ready copy ────────────────────────────────
# copibara.com's download button points at the latest-release permalink, which
# resolves by ASSET FILENAME. GitHub names an asset after the file you upload —
# `gh release upload file#name` sets the asset's *label*, not its name — so
# uploading the versioned DMG silently 404s the site's download link.
#
# Emit a correctly-named copy here so publishing can't get it wrong. Copied
# after stapling so it carries the notarization ticket.
RELEASE_DMG="${SCRIPT_DIR}/dist/Copibara-Yapivo.dmg"
PERMALINK="https://github.com/saulfloresjr/Copibara/releases/latest/download/Copibara-Yapivo.dmg"
cp "${DMG_PATH}" "${RELEASE_DMG}"
echo "   ✅ Release-ready copy: $(basename "${RELEASE_DMG}")"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "✅ Build complete! (Signed + Notarized + Stapled)"
echo ""
echo "   App:  ${APP_DIR}"
echo "   DMG:  ${DMG_PATH}"
echo ""
echo "   To install:"
echo "   1. Open the DMG"
echo "   2. Drag 'Copibara' to Applications"
echo "   3. Open from Applications"
echo "   4. Grant Accessibility permissions when prompted"
echo ""
echo "   Verify notarization:"
echo "   spctl --assess --type open --context context:primary-signature ${DMG_PATH}"
echo "   xcrun stapler validate ${DMG_PATH}"
echo ""
echo "   Publish — upload RELEASE_DMG (already named correctly) with --latest:"
echo "   gh release create v${VERSION}-yapivo '${RELEASE_DMG}' --latest --title '...' --notes '...'"
echo "   Then confirm the site's link actually serves it:"
echo "   curl -sL ${PERMALINK} -o /tmp/x.dmg -w '%{http_code} %{size_download}\\n'"
echo "============================================"
