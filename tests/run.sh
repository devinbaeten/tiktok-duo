#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/tiktok-duo-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation tests/TCLCoverEngineTests.m -o "$test_dir/TCLCoverEngineTests"
"$test_dir/TCLCoverEngineTests"
"$test_dir/TCLCoverEngineTests" wrong-abi
"$test_dir/TCLCoverEngineTests" incompatible
"$test_dir/TCLCoverEngineTests" late-classes
"$test_dir/TCLCoverEngineTests" wrong-vertical-abi
"$test_dir/TCLCoverEngineTests" wrong-bottom-abi
"$test_dir/TCLCoverEngineTests" wrong-placement-abi
