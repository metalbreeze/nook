#!/usr/bin/env bash
#
# Build, notarize, and staple a distributable Nook.app.
#
# Nook's Release config already signs the app with the "Developer ID
# Application" identity and enables the Hardened Runtime (see project.yml), so
# this script just builds, submits to Apple's notary service, staples the
# ticket, and produces a zip you can attach to a GitHub Release.
#
# ── One-time credential setup (run by YOU, not committed) ────────────────────
# Create an app-specific password at https://appleid.apple.com (Sign-In and
# Security ▸ App-Specific Passwords), then store it in your login keychain so
# this script can run notarytool non-interactively:
#
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#       --apple-id "you@example.com" \
#       --team-id  "MKSL2N4Y23" \
#       --password "abcd-efgh-ijkl-mnop"      # the app-specific password
#
# No credentials are stored in this repo — only the profile NAME is referenced.
#
# Usage:
#   scripts/notarize.sh                # uses profile "NookNotary"
#   NOTARY_PROFILE=MyProfile scripts/notarize.sh
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
PROJECT="Nook.xcodeproj"
SCHEME="Nook"
CONFIG="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-NookNotary}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build/notarize"
DIST_DIR="$REPO_ROOT/dist"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/Nook.app"

# --- 0. Regenerate project (keeps .xcodeproj in sync with project.yml) -------
if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Regenerating Xcode project"
  xcodegen generate
fi

# --- 1. Clean Release build (Developer ID + Hardened Runtime) ----------------
echo "==> Building $SCHEME ($CONFIG)"
rm -rf "$BUILD_DIR"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  | tail -3

[ -d "$APP_PATH" ] || { echo "ERROR: $APP_PATH not found"; exit 1; }

# --- 2. Sanity-check the signature before submitting -------------------------
echo "==> Verifying signature + Hardened Runtime"
codesign --verify --strict --verbose=2 "$APP_PATH"
codesign -dvvv "$APP_PATH" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime|TeamIdentifier" || true

# --- 3. Read version for nicely-named artifacts ------------------------------
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 0.0)"
mkdir -p "$DIST_DIR"
SUBMIT_ZIP="$DIST_DIR/Nook-notarize.zip"
DIST_ZIP="$DIST_DIR/Nook-$VERSION.zip"

# --- 4. Zip for submission (notarytool wants an archive) ---------------------
echo "==> Zipping for notarization"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_ZIP"

# --- 5. Submit and wait ------------------------------------------------------
echo "==> Submitting to Apple notary service (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$SUBMIT_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# --- 6. Staple the ticket onto the .app --------------------------------------
echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true

# --- 7. Package the stapled app for distribution -----------------------------
echo "==> Packaging $DIST_ZIP"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$DIST_ZIP"

echo
echo "Done. Notarized + stapled app:  $APP_PATH"
echo "Distributable archive:          $DIST_ZIP"
