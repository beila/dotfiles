#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
XMONAD_DIR="$ROOT/xwindow/xmonad.symlink"
XMONAD_WRAPPER=$(command -v xmonad)
XMONAD_GHC=$(sed -n "s/^export XMONAD_GHC='\\(.*\\)'/\\1/p" "$XMONAD_WRAPPER")
XMONAD_GHC=${XMONAD_GHC:-ghc}
BUILD_DIR=$(mktemp -d /tmp/xmonad-test.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$XMONAD_DIR"
"$XMONAD_GHC" \
    --make \
    xmonad.hs \
    test/XMonadConfigTest.hs \
    -i. \
    -ilib \
    -main-is XMonadConfigTest.main \
    -fforce-recomp \
    -outputdir "$BUILD_DIR" \
    -o "$BUILD_DIR/xmonad-test"
"$BUILD_DIR/xmonad-test"
