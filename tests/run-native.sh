#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/tiktok-duo-native-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation tests/TCLCoverNativeTests.m -o "$test_dir/TCLCoverNativeTests"
for scenario in on off default pending busy changed-slot bad-prefix readonly vertical-changed-slot vertical-bad-prefix; do
    "$test_dir/TCLCoverNativeTests" "$scenario"
done
