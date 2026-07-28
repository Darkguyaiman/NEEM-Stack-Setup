#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
COMMAND_PATH="$BIN_DIR/neem-stack"
SHORT_COMMAND_PATH="$BIN_DIR/neem"

mkdir -p "$BIN_DIR"
printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$SCRIPT_DIR/neem.sh" > "$COMMAND_PATH"
chmod 0755 "$COMMAND_PATH"
cp "$COMMAND_PATH" "$SHORT_COMMAND_PATH"
chmod 0755 "$SHORT_COMMAND_PATH"

case "${SHELL:-}" in
  */zsh) profile="$HOME/.zshrc" ;;
  */bash) profile="$HOME/.bashrc" ;;
  *) profile="$HOME/.profile" ;;
esac

path_line='export PATH="$HOME/.local/bin:$PATH"'
if [[ ! -f "$profile" ]] || ! grep -Fqx "$path_line" "$profile"; then
  printf '\n# NEEM Stack Setup command\n%s\n' "$path_line" >> "$profile"
fi

printf '\nNEEM command installed.\n'
printf 'Location: %s\n\n' "$COMMAND_PATH"
printf 'Live project: %s\n\n' "$SCRIPT_DIR"
printf 'Open a new terminal, then run:\n'
printf '  neem-stack\n'
printf '  neem\n'
