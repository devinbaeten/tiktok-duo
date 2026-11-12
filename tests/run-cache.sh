#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/tiktok-duo-cache-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
    tests/TCLAdaptiveCacheTests.c -o "$test_dir/TCLAdaptiveCacheTests"
"$test_dir/TCLAdaptiveCacheTests"
