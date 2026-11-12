#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/tiktok-duo-shop-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation tests/TCLCoverShopTests.m -o "$test_dir/TCLCoverShopTests"
"$test_dir/TCLCoverShopTests"
"$test_dir/TCLCoverShopTests" disabled
"$test_dir/TCLCoverShopTests" bad-abi
