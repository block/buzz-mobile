#!/bin/sh
# Run by the Runner target. Builds the Apple Watch app and puts it inside the
# phone app, which is how a watch app reaches a watch and what lets the two
# talk to each other. Does nothing unless a developer opts in with
# `BUZZ_EMBED_WATCH_APP = YES` in ios/Flutter/AppOverrides.xcconfig, so
# ordinary and release builds are unchanged.
set -eu

[ "${BUZZ_EMBED_WATCH_APP:-NO}" = "YES" ] || exit 0

case "$PLATFORM_NAME" in
  iphonesimulator) sdk=watchsimulator ;;
  iphoneos) sdk=watchos ;;
  *) echo "error: no watch app for $PLATFORM_NAME" >&2; exit 1 ;;
esac
[ "$CONFIGURATION" = "Debug" ] && configuration=Debug || configuration=Release
products="$DERIVED_FILE_DIR/BuzzWatch"

# A clean environment: the phone build's settings must not leak into this one.
# The identifier, team and version are passed on so the pair always match.
env -i PATH="$PATH" HOME="$HOME" DEVELOPER_DIR="${DEVELOPER_DIR:-}" \
  xcodebuild build \
  -project "$SRCROOT/BuzzWatch/BuzzWatch.xcodeproj" \
  -scheme BuzzWatch \
  -configuration "$configuration" \
  -sdk "$sdk" \
  -derivedDataPath "$products" \
  BUNDLE_IDENTIFIER="$PRODUCT_BUNDLE_IDENTIFIER" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
  MARKETING_VERSION="${FLUTTER_BUILD_NAME:-0.1}" \
  CURRENT_PROJECT_VERSION="${FLUTTER_BUILD_NUMBER:-1}" \
  -quiet

destination="$TARGET_BUILD_DIR/$WRAPPER_NAME/Watch"
rm -rf "$destination"
mkdir -p "$destination"
cp -R "$products/Build/Products/$configuration-$sdk/BuzzWatch.app" "$destination/"
