#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Requires macOS with Xcode and the iPhoneOS SDK.' >&2; exit 1
fi
mkdir -p build
COMMON=(-fobjc-arc -fblocks -Wall -Wextra -Werror -I Sources -framework Foundation)
# Native macOS executable tests only the portable JSON transformation, not iOS hooks.
xcrun --sdk macosx clang "${COMMON[@]}" Sources/JSONInterceptor.m Tests/JSONInterceptorTests.m -o build/JSONInterceptorTests
build/JSONInterceptorTests | tee build/tests.txt
if [[ "${1:-}" == --test-only ]]; then exit 0; fi
TARGET_BUNDLE_ID="${TARGET_BUNDLE_ID:-com.tonnom.obdtest}"
if [[ ! "$TARGET_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo 'Invalid bundle ID; expected reverse DNS identifier.' >&2; exit 1
fi
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang "${COMMON[@]}" \
  -target arm64-apple-ios13.0 -isysroot "$SDK" -dynamiclib \
  "-DTO_TARGET_BUNDLE_ID=\"$TARGET_BUNDLE_ID\"" \
  -Wl,-install_name,@rpath/TestOverrides.dylib \
  -Wl,-current_version,1.0 -Wl,-compatibility_version,1.0 \
  Sources/TestOverrides.m Sources/JSONInterceptor.m -o build/TestOverrides.dylib
# Ad hoc signature is for inspection only; IPA re-signing must replace it.
codesign --force --sign - build/TestOverrides.dylib
{
  file build/TestOverrides.dylib
  xcrun lipo -info build/TestOverrides.dylib
  xcrun vtool -show-build build/TestOverrides.dylib
  xcrun otool -L build/TestOverrides.dylib
} | tee build/verification.txt
[[ "$(xcrun lipo -archs build/TestOverrides.dylib)" == arm64 ]]
xcrun vtool -show-build build/TestOverrides.dylib | grep -Eq 'platform IOS$'
codesign --verify --strict build/TestOverrides.dylib
printf '%s\n' "$TARGET_BUNDLE_ID" > build/target-bundle-id.txt
shasum -a 256 build/TestOverrides.dylib > build/SHA256SUMS.txt
echo 'Built iPhoneOS arm64: build/TestOverrides.dylib'
