#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SSHT_VERSION="${SSHT_VERSION:-$(cat VERSION)}"
if [[ ! "$SSHT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print -u2 "版本号必须为 x.y.z：$SSHT_VERSION"
    exit 1
fi
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --arch arm64 --disable-sandbox --build-system native -c release --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/module-cache
APP="dist/SSHT.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift -module-cache-path .build/module-cache scripts/icon.swift .build/AppIcon.iconset
python3 scripts/package_icon.py .build/AppIcon.iconset "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/SSHT "$APP/Contents/MacOS/SSHT"
cp -R Sources/SSHT/Resources/Figma "$APP/Contents/Resources/"
cp -R .build/release/SSHT_SSHT.bundle "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SSHT</string>
<key>CFBundleIdentifier</key><string>dev.aristo.ssht</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>SSHT</string>
<key>CFBundleDisplayName</key><string>SSHT</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$SSHT_VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "已生成：$PWD/$APP"
