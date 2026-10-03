# Shared output style for reset1's bash and zsh scripts.
# A script pulls it in with an @include line naming lib/style.sh; ArfanReset1 pastes this file in its place,
# so a copied or Terminal-run script still works on a Mac without the repo. Same words as lib/style.py.
BOLD=$'\033[1m' DIM=$'\033[2m' GREEN=$'\033[32m' AMBER=$'\033[33m' RED=$'\033[31m' BLUE=$'\033[34m' RESET=$'\033[0m'
heading() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }      # a section title
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }          # done, or already right
todo() { printf '  %s•%s %s\n' "$AMBER" "$RESET" "$1"; }        # about to change, or still to do
fail() { printf '  %s✕%s %s\n' "$RED" "$RESET" "$1"; }          # did not work
info() { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }            # a quiet detail
suggest() { printf '\n  %s%s%s\n' "$BLUE" "$1" "$RESET"; }      # a command to try next
