#!/usr/bin/env zsh

set -euo pipefail

# @include lib/style.sh

# ── Command Line Tools ──────────────────────────────────────────────────

heading "Command Line Tools"

if xcode-select -p >/dev/null 2>&1; then
  ok "Command Line Tools already installed: $(xcode-select -p)"
  info "$(clang --version 2>/dev/null | head -1)"
  info "$(git --version 2>/dev/null)"
else
  # Trick the system into listing the CLT package
  TRIGGER=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  touch "$TRIGGER"
  trap 'rm -f "$TRIGGER"' EXIT

  # Find the newest CLT label
  CLT=$(softwareupdate -l 2>/dev/null \
    | grep -o 'Label: Command Line Tools for Xcode.*' \
    | sed 's/^Label: //' \
    | sort -V | tail -1)

  if [[ -z "$CLT" ]]; then
    fail "No Command Line Tools package in the Software Update catalog."
    suggest "xcode-select --install"
    exit 1
  fi

  todo "Installing: $CLT"
  info "Asks for your password (sudo). There is no dialog to click through."

  sudo softwareupdate -i "$CLT" --verbose

  if xcode-select -p >/dev/null 2>&1; then
    ok "Installed: $(xcode-select -p)"
    info "$(clang --version 2>/dev/null | head -1)"
    info "$(git --version 2>/dev/null)"
  else
    fail "The install did not finish. Try Apple's installer dialog instead:"
    suggest "xcode-select --install"
    exit 1
  fi
fi
