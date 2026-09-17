#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
ARCH="${TOKEN_GALAXY_ARCH:-$(uname -m)}"
OUT="${TOKEN_GALAXY_BUILD_DIR:-$ROOT/Outputs}/Token Galaxy.app"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
xcrun swiftc -target "$ARCH-apple-macosx15.0" -swift-version 5 -O -whole-module-optimization -I "$ROOT/Sources/CSQLite" "$ROOT/Sources/Capabilities.swift" "$ROOT/Sources/WindowControls.swift" "$ROOT/Sources/Telemetry.swift" "$ROOT/Sources/ClaudeTelemetry.swift" "$ROOT/Sources/VisualModel.swift" "$ROOT/Sources/StarField.swift" "$ROOT/Sources/Overview.swift" "$ROOT/Sources/Mapping.swift" "$ROOT/Sources/Spirit.swift" "$ROOT/Sources/App.swift" "$ROOT/Sources/ReviewCapture.swift" "$ROOT/Sources/Validation.swift" "$ROOT/Sources/main.swift" -framework IOKit -framework AppKit -framework QuartzCore -framework Metal -framework MetalKit -lsqlite3 -o "$OUT/Contents/MacOS/TokenGalaxy"
cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.token-galaxy.native</string>
<key>CFBundleName</key><string>Token Galaxy</string>
<key>CFBundleDisplayName</key><string>Token 星簇</string>
<key>CFBundleExecutable</key><string>TokenGalaxy</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>24</string>
<key>CFBundleShortVersionString</key><string>0.7.1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$ROOT/Resources/Cosmos.metal" "$OUT/Contents/Resources/Cosmos.metal"
cp "$ROOT/Resources/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$OUT/Contents/Resources/"
codesign --force --sign - "$OUT"
print "$OUT"
