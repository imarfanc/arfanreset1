#!/usr/bin/env bash
# @include lib/style.sh

heading "Build Ghostty"
cd "$HOME/tmp1/ghostty"
zig_bin="$HOME/.local/bin/zig"
required=$(sed -nE 's/.*\.minimum_zig_version = "([^"]+)".*/\1/p' build.zig.zon)
actual=$("$zig_bin" version)
if [ -z "$required" ] || [ "$actual" != "$required" ]; then
  fail "This checkout requires Zig $required; selected compiler is $actual."
  info "Install the matching Zig version before building."
  exit 1
fi
export PATH="$(brew --prefix gettext)/bin:$PATH"
"$zig_bin" build -Doptimize=ReleaseFast
ok "Built zig-out/Ghostty.app"
open zig-out/Ghostty.app
