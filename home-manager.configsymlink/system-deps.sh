#!/bin/bash
# System-level dependencies that can't be managed by Home Manager.
# Run this on a new machine before `home-manager switch`.
set -xeuo pipefail

sudo apt install -y \
  ibus-hangul \
  input-remapper
