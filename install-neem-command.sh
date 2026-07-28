#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/neem-stack"
BIN_DIR="$HOME/.local/bin"
COMMAND_PATH="$BIN_DIR/neem-stack"

mkdir -p "$APP_DIR" "$BIN_DIR"
install -m 0755 "$SCRIPT_DIR/neem.sh" "$APP_DIR/neem.sh"
if [[ -f "$SCRIPT_DIR/ASCI_ART_ME.txt" ]]; then
  install -m 0644 "$SCRIPT_DIR/ASCI_ART_ME.txt" "$APP_DIR/ASCI_ART_ME.txt"
fi

printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$APP_DIR/neem.sh" > "$COMMAND_PATH"
chmod 0755 "$COMMAND_PATH"

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
printf 'Open a new terminal, then run:\n'
printf '  neem-stack\n'
