# killport
killport() {
  if [ -z "$1" ]; then
    echo "Usage: killport <port>"
    return 1
  fi
  PORT="$1" uv run --with rich --quiet ~/developer/github/t1/scripts/killport1.py
}
