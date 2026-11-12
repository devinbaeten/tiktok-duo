#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/tiktok-duo-glass-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -std=c11 -O2 -Wall -Wextra -Werror -pthread \
    tests/TCLGlassBridgeTests.c -o "$test_dir/TCLGlassBridgeTests"
"$test_dir/TCLGlassBridgeTests"
