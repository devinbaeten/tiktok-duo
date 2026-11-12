#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk" -miphoneos-version-min=15.0 \
  -fobjc-arc -fblocks -Wall -Wextra -Werror -O2 -dynamiclib \
  src/TCLCoverEngine.m src/TCLCoverNative.m src/TCLCoverChrome.m src/TCLCoverShop.m \
  -framework Foundation -framework UIKit -framework CoreGraphics \
  -install_name @executable_path/Frameworks/TikTokDuo.dylib \
  -o build/TikTokDuo.dylib
codesign --force --sign - build/TikTokDuo.dylib
printf 'Built build/TikTokDuo.dylib (ad-hoc signed; app must be re-signed).\n'
