#!/bin/zsh
# Builds 隨手藏.app without Xcode (Command Line Tools are enough).
# Usage:  ./build.sh            -> build/隨手藏.app
#         ./build.sh install    -> also copies it to /Applications
set -euo pipefail
cd "${0:A:h}"

APP=build/隨手藏.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

[[ -f MenuHide/AppIcon.icns ]] || swift tools/make_icon.swift

swiftc -O -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  MenuHide/*.swift -o "$APP/Contents/MacOS/MenuHide"

cp MenuHide/AppIcon.icns "$APP/Contents/Resources/"

# LSUIElement keeps the app out of the Dock and ⌘-Tab; it lives only in the menu bar.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>隨手藏</string>
	<key>CFBundleDisplayName</key><string>隨手藏</string>
	<key>CFBundleIdentifier</key><string>com.jeff.menuhide</string>
	<key>CFBundleExecutable</key><string>MenuHide</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>2026.a1</string>
	<key>CFBundleVersion</key><string>2026.a1</string>
	<key>CFBundleDevelopmentRegion</key><string>zh_TW</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Accessibility access is granted to an app by its signature. An ad-hoc signature changes with
# every build, which would lose the access each time; a certificate of one's own keeps it.
# Make one with Keychain Access (Certificate Assistant → Create a Certificate, type Code
# Signing) named as below; without it the build is signed ad hoc.
IDENTITY="MenuHide Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
  echo "No \"$IDENTITY\" certificate: signed ad hoc, so Accessibility access must be granted again after each build." >&2
fi
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  if pgrep -x MenuHide >/dev/null; then
    osascript -e 'tell application id "com.jeff.menuhide" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -x MenuHide >/dev/null || break; sleep 0.5; done
  fi
  rm -rf "/Applications/隨手藏.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/隨手藏.app"
fi
