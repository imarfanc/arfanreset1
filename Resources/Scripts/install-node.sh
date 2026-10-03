#!/usr/bin/env bash
# nvm is installed separately. A fresh interactive login shell loads its normal setup.
exec /bin/zsh -lic '
  if ! command -v nvm >/dev/null 2>&1; then
    print -u2 "nvm is not available. Install nvm from its card first, then retry Node.js."
    exit 1
  fi
  nvm install 26
'
