#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/tiktok-duo-chrome-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation tests/TCLCoverChromeTests.m -o "$test_dir/TCLCoverChromeTests"
"$test_dir/TCLCoverChromeTests"
"$test_dir/TCLCoverChromeTests" disabled
