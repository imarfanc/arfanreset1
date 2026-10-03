#!/usr/bin/env bash
# @include lib/style.sh

heading "Zig 0.16.0"
[ "$(uname -m)" = arm64 ] || { fail "Use a native Apple Silicon Terminal for this download."; exit 1; }
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
cd "$work_dir"
todo "Downloading the Apple Silicon archive"
curl -fL --retry 3 -o zig.tar.xz https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz
printf '%s  %s\n' b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489 zig.tar.xz | shasum -a 256 -c -
mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
if [ ! -e "$HOME/.local/opt/zig-aarch64-macos-0.16.0" ]; then
  tar -xf zig.tar.xz -C "$HOME/.local/opt"
fi
ln -sfn "$HOME/.local/opt/zig-aarch64-macos-0.16.0/zig" "$HOME/.local/bin/zig"
path_line='export PATH="$HOME/.local/bin:$PATH"'
touch "$HOME/.zprofile"
grep -qxF "$path_line" "$HOME/.zprofile" || printf '%s\n' "$path_line" >> "$HOME/.zprofile"
export PATH="$HOME/.local/bin:$PATH"
ok "Installed: zig $(zig version) in ~/.local/bin"
