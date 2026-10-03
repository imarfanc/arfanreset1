#!/usr/bin/env zsh
# Homebrew's official installer, then brew on the login shell PATH (Apple Silicon or Intel).
# @include lib/style.sh

heading "Homebrew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
if [[ -x /opt/homebrew/bin/brew ]]; then
  line='eval "$(/opt/homebrew/bin/brew shellenv zsh)"'
elif [[ -x /usr/local/bin/brew ]]; then
  line='eval "$(/usr/local/bin/brew shellenv zsh)"'
else
  fail "brew was not found in /opt/homebrew or /usr/local after installing."
  exit 1
fi
touch "$HOME/.zprofile"
if grep -qxF "$line" "$HOME/.zprofile"; then
  ok "brew is already on your PATH in ~/.zprofile"
else
  print -r -- "$line" >> "$HOME/.zprofile"
  ok "Added brew to your PATH in ~/.zprofile"
fi
eval "$line"
info "$(brew --version | head -1)"
