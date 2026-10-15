#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
ARCH="${TOKEN_GALAXY_ARCH:-$(uname -m)}"
PREVIEW="${TOKEN_GALAXY_PREVIEW:-0}"
URL_TYPES=""
case "$PREVIEW" in
    0) DEFAULT_BUILD_DIR="$ROOT/Outputs"; BUNDLE_ID="local.token-galaxy.native"; DISPLAY_NAME="Token 星簇"; AUTOMATIC_UPDATES="true"
       URL_TYPES='<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>local.token-galaxy.native.speed</string><key>CFBundleTypeRole</key><string>Viewer</string><key>CFBundleURLSchemes</key><array><string>token-galaxy</string></array></dict></array>' ;;
    1) DEFAULT_BUILD_DIR="$ROOT/Outputs/TokenSpeedPreview"; BUNDLE_ID="local.token-galaxy.speed-preview"; DISPLAY_NAME="Token 速度预览"; AUTOMATIC_UPDATES="false" ;;
    *) print -u2 "TOKEN_GALAXY_PREVIEW must be 0 or 1"; exit 2 ;;
esac
OUT="${TOKEN_GALAXY_BUILD_DIR:-$DEFAULT_BUILD_DIR}/Token Galaxy.app"
SPARKLE_ROOT=$("$ROOT/scripts/prepare_sparkle.sh")
UPDATE_KEY=$(cat "$ROOT/Resources/UpdatePublicKey.txt")
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Frameworks"
xcrun swiftc -target "$ARCH-apple-macosx15.0" -swift-version 5 -O -whole-module-optimization -I "$ROOT/Sources/CSQLite" "$ROOT/Sources/Capabilities.swift" "$ROOT/Sources/WindowControls.swift" "$ROOT/Sources/Telemetry.swift" "$ROOT/Sources/ClaudeTelemetry.swift" "$ROOT/Sources/TokenSpeed.swift" "$ROOT/Sources/TokenSpeedTests.swift" "$ROOT/Sources/TokenSpeedCLI.swift" "$ROOT/Sources/TokenSpeedView.swift" "$ROOT/Sources/SpeedPreview.swift" "$ROOT/Sources/OverviewLayout.swift" "$ROOT/Sources/VisualModel.swift" "$ROOT/Sources/StarField.swift" "$ROOT/Sources/Overview.swift" "$ROOT/Sources/Mapping.swift" "$ROOT/Sources/Spirit.swift" "$ROOT/Sources/Updater.swift" "$ROOT/Sources/App.swift" "$ROOT/Sources/ReviewCapture.swift" "$ROOT/Sources/Validation.swift" "$ROOT/Sources/main.swift" -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -framework IOKit -framework AppKit -framework QuartzCore -framework Metal -framework MetalKit -lsqlite3 -o "$OUT/Contents/MacOS/TokenGalaxy"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
$URL_TYPES
<key>CFBundleName</key><string>Token Galaxy</string>
<key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
<key>CFBundleExecutable</key><string>TokenGalaxy</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>38</string>
<key>CFBundleShortVersionString</key><string>0.10.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>SUFeedURL</key><string>https://github.com/ssg87/token-galaxy/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>$UPDATE_KEY</string>
<key>SURequireSignedFeed</key><true/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
<key>SUEnableSystemProfiling</key><false/>
<key>SUEnableAutomaticChecks</key><$AUTOMATIC_UPDATES/>
<key>SUAutomaticallyUpdate</key><$AUTOMATIC_UPDATES/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>SUSendProfileInfo</key><false/>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$ROOT/Resources/Cosmos.metal" "$OUT/Contents/Resources/Cosmos.metal"
cp "$ROOT/Resources/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$OUT/Contents/Resources/"
ditto "$SPARKLE_ROOT/Sparkle.framework" "$OUT/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE_ROOT/LICENSE" "$OUT/Contents/Resources/Sparkle-LICENSE"
codesign --force --sign - "$OUT"
codesign --verify --deep --strict "$OUT"
print "$OUT"
