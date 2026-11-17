# Buzz mobile: development task runner

set dotenv-load := true

# List all available tasks
default:
    @just --list

# Run every check CI runs on a pull request
check: mobile-check

# Format everything
fmt-all: mobile-fmt

mobile_dir := "."

# Install mobile Flutter dependencies
mobile-install:
    unset GIT_DIR GIT_WORK_TREE; cd {{mobile_dir}} && flutter pub get

# Format all Dart code
mobile-fmt:
    unset GIT_DIR GIT_WORK_TREE; cd {{mobile_dir}} && dart format .

# Fix mobile formatting and run analysis
mobile-fix:
    unset GIT_DIR GIT_WORK_TREE; cd {{mobile_dir}} && dart format . && flutter analyze

# Run mobile lint and format checks
mobile-check:
    unset GIT_DIR GIT_WORK_TREE; cd {{mobile_dir}} && dart format --output=none --set-exit-if-changed . && flutter analyze

# Run mobile tests
mobile-test:
    /bin/bash ./scripts/test-mobile-gateway-recipes.sh
    unset GIT_DIR GIT_WORK_TREE; cd {{mobile_dir}} && flutter test
    unset GIT_DIR GIT_WORK_TREE; cd {{mobile_dir}}/packages/buzz_secp256k1 && dart pub get && dart test

# Regenerate the emoji dataset asset from desktop's emoji-mart install.
# Output is committed — rerun after bumping @emoji-mart/data.
mobile-emoji-data:
    node {{mobile_dir}}/scripts/generate-emoji-data.mjs

# Compile an unsigned Android debug APK (worktree-aware debug identity)
mobile-build-android:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/mobile-worktree-overrides.sh
    set -- build apk --debug --no-pub
    if [[ -n "${BUZZ_PUSH_GATEWAY_URL:-}" ]]; then
        set -- "$@" --dart-define="BUZZ_PUSH_GATEWAY_URL=${BUZZ_PUSH_GATEWAY_URL}"
    fi
    unset GIT_DIR GIT_WORK_TREE
    cd {{mobile_dir}}
    flutter "$@"

# Run the mobile app on iOS simulator (worktree-aware debug identity)
mobile-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    developer_dir="$(xcode-select -p)"
    simulator_app="$developer_dir/../Applications/DeviceHub.app"
    if [[ ! -d "$simulator_app" ]]; then
        simulator_app="$developer_dir/Applications/Simulator.app"
    fi
    # Use the selected Xcode even when another version's app is already running.
    open -a "$simulator_app"
    sleep 3
    ./scripts/mobile-worktree-overrides.sh
    gateway_url="${BUZZ_PUSH_GATEWAY_URL:-}"
    overrides_file="{{mobile_dir}}/ios/Flutter/AppOverrides.xcconfig"
    if [[ -z "$gateway_url" && -f "$overrides_file" ]]; then
        gateway_url="$(sed -nE 's/^[[:space:]]*BUZZ_PUSH_GATEWAY_URL[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p' "$overrides_file" | tail -n 1 | sed 's/\$()//g')"
    fi
    set -- run
    if [[ -n "$gateway_url" ]]; then
        set -- "$@" --dart-define="BUZZ_PUSH_GATEWAY_URL=${gateway_url}"
    fi
    cd {{mobile_dir}}
    unset GIT_DIR GIT_WORK_TREE
    flutter "$@"

# Uninstall stale worktree-suffixed Buzz debug installs (production apps kept)
mobile-clean:
    ./scripts/mobile-worktree-clean.sh

