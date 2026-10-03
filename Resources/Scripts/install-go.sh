#!/usr/bin/env bash
# @include lib/style.sh

heading "Go 1.27.1"
[ "$(uname -m)" = arm64 ] || { fail "Use a native Apple Silicon Terminal for this download."; exit 1; }
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
cd "$work_dir"
todo "Downloading the Apple Silicon installer"
curl -fL --retry 3 -o go.pkg https://go.dev/dl/go1.27.1.darwin-arm64.pkg
printf '%s  %s\n' 81aee79ea3bd85f00624c216e9105674fa72626dd0479fc85a632939d6c5986b go.pkg | shasum -a 256 -c -
sudo /usr/sbin/installer -pkg go.pkg -target /
ok "Installed: $(/usr/local/go/bin/go version)"
