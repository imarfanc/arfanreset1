#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v brew >/dev/null 2>&1; then
  printf '%s\n' 'Homebrew was not found. Complete the Homebrew step in ArfanReset1, or use the Google download link.'
  exit 1
fi
brew install --cask google-chrome
