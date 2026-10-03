#!/usr/bin/env bash
# @include lib/style.sh

heading "Ghostty source"
mkdir -p "$HOME/tmp1"
if [ ! -e "$HOME/tmp1/ghostty" ]; then
  git clone https://github.com/ghostty-org/ghostty.git "$HOME/tmp1/ghostty"
fi
git -C "$HOME/tmp1/ghostty" status --short --branch
