#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
SSHT_DEVELOPER_DIR="$(xcode-select -p)"
SSHT_TEST_FRAMEWORKS="$SSHT_DEVELOPER_DIR/Library/Developer/Frameworks"
if [[ ! -d "$SSHT_TEST_FRAMEWORKS/Testing.framework" ]]; then
    SSHT_TEST_FRAMEWORKS="$SSHT_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"
fi
swift test --disable-xctest --enable-swift-testing --disable-sandbox --build-system native --cache-path .build/cache -Xswiftc -F -Xswiftc "$SSHT_TEST_FRAMEWORKS" -Xlinker -F -Xlinker "$SSHT_TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$SSHT_TEST_FRAMEWORKS" -Xswiftc -module-cache-path -Xswiftc .build/module-cache
