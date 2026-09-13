# Terminal presentation, shared execution, platform detection, and self-update.
info() { printf '%s[i]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%s[error]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
pause() { [[ $DRY_RUN -eq 1 ]] || read -r -p "Press Enter to continue..." _; }

hyperlink() {
  local label=$1 url=$2 prefix=${3:-"  "}
  if ((SUPPORTS_HYPERLINKS)); then
    printf '%s%s%s\033]8;;%s\033\\%s\033]8;;\033\\%s\n' "$MUTED" "$prefix" "$PAPER" "$url" "$label" "$RESET"
  else
    printf '%s%s <%s>\n' "$prefix" "$label" "$url"
  fi
}

rule() {
  local title=${1:-} width=68 line fill
  if [[ -n "$title" ]]; then
    printf -v line -- '-- %s ' "$title"
    printf -v fill '%*s' "$((width-${#line}))" ''
    printf '%s%s%s%s\n' "$SUBTLE" "$line" "${fill// /-}" "$RESET"
  else
    printf -v fill '%*s' "$width" ''
    printf '%s%s%s\n' "$SUBTLE" "${fill// /-}" "$RESET"
  fi
}

show_brand() {
  printf '\n%s' "$ACCENT"
  printf '  _   _  _____ _____ __  __\n'
  printf ' | \\ | || ____| ____|  \\/  |\n'
  printf ' |  \\| ||  _| |  _| | |\\/| |\n'
  printf ' | |\\  || |___| |___| |  | |\n'
  printf ' |_| \\_||_____|_____|_|  |_|\n'
  printf '%s%s  Stack Setup%s%s  v%s%s\n' "$CREAM" "$BOLD" "$RESET" "$MUTED" "$VERSION" "$RESET"
  printf '%s  Built with care by Mohamed Aiman%s\n' "$MUTED" "$RESET"
  rule
}

show_creator() {
  local cols row left key url line column compact shift source_row=0 last_cols=-1
  local -a art_lines=()
  if [[ -f "$SCRIPT_DIR/ASCI_ART_ME.txt" ]]; then
    while IFS= read -r line; do
      source_row=$((source_row + 1))
      ((source_row % 6 == 0)) && continue
      compact=""
      for ((column=0; column<${#line}; column++)); do
        (((column + 1) % 8 == 0)) || compact+="${line:column:1}"
      done
      for ((shift=0; shift<12 && ${#compact}>0; shift++)); do
        [[ "${compact:0:1}" == " " ]] && compact=${compact# } || break
      done
      art_lines+=("$compact")
    done < "$SCRIPT_DIR/ASCI_ART_ME.txt"
  else
    art_lines=("  ASCII portrait not found.")
  fi
  while true; do
    cols=$(tput cols 2>/dev/null || printf '120')
    if ((cols != last_cols)); then
      clear 2>/dev/null || true
      if ((cols >= 138)); then
        for ((row=0; row<${#art_lines[@]}; row++)); do
          left=${art_lines[row]}
          printf '%s%-104s%s' "$SUBTLE" "$left" "$RESET"
          case "$row" in
            5) printf '%sMOHAMED AIMAN%s\n' "$ACCENT" "$RESET" ;;
            6) printf '%sCreator of NEEM Stack Setup%s\n' "$MUTED" "$RESET" ;;
            9) hyperlink "mohamedaiman103@gmail.com" "mailto:mohamedaiman103@gmail.com" "[1] Email       " ;;
            11) hyperlink "darkguyaiman.com" "https://darkguyaiman.com" "[2] Portfolio   " ;;
            13) hyperlink "linkedin.com/in/darkguyaiman" "https://www.linkedin.com/in/darkguyaiman" "[3] LinkedIn    " ;;
            15) hyperlink "instagram.com/darkguyaiman" "https://www.instagram.com/darkguyaiman" "[4] Instagram   " ;;
            17) hyperlink "x.com/thedarkguyaiman" "https://x.com/thedarkguyaiman" "[5] X / Twitter " ;;
            19) hyperlink "ko-fi.com/darkguyaiman" "https://ko-fi.com/darkguyaiman" "[6] Ko-fi       " ;;
            21) hyperlink "paypal.me/thedarkguyaiman" "https://paypal.me/thedarkguyaiman" "[7] PayPal      " ;;
            25)
              if ((SUPPORTS_HYPERLINKS)); then
                printf '%sCtrl+click a link, or press 1-7 to open.%s\n' "$MUTED" "$RESET"
              else
                printf '%sPress 1-7 to open a link.%s\n' "$MUTED" "$RESET"
              fi
              ;;
            *) printf '\n' ;;
          esac
        done
      else
        printf '%s' "$SUBTLE"
        printf '%s\n' "${art_lines[@]}"
        printf '%s' "$RESET"
        rule "CREATOR"
        printf '  %s%sMohamed Aiman%s | Creator of NEEM Stack Setup\n' "$CREAM" "$BOLD" "$RESET"
        hyperlink "mohamedaiman103@gmail.com" "mailto:mohamedaiman103@gmail.com" "  [1] Email       "
        hyperlink "darkguyaiman.com" "https://darkguyaiman.com" "  [2] Portfolio   "
        hyperlink "linkedin.com/in/darkguyaiman" "https://www.linkedin.com/in/darkguyaiman" "  [3] LinkedIn    "
        hyperlink "instagram.com/darkguyaiman" "https://www.instagram.com/darkguyaiman" "  [4] Instagram   "
        hyperlink "x.com/thedarkguyaiman" "https://x.com/thedarkguyaiman" "  [5] X / Twitter "
        hyperlink "ko-fi.com/darkguyaiman" "https://ko-fi.com/darkguyaiman" "  [6] Ko-fi       "
        hyperlink "paypal.me/thedarkguyaiman" "https://paypal.me/thedarkguyaiman" "  [7] PayPal      "
      fi
      printf '\n%s  Press 1-7 to open a link | Enter or Esc to return | Resize to reflow%s\n' "$MUTED" "$RESET"
      last_cols=$cols
    fi
    if ! IFS= read -rsn1 -t 0.1 key < /dev/tty; then
      continue
    fi
    case "$key" in
      1) url="mailto:mohamedaiman103@gmail.com" ;;
      2) url="https://darkguyaiman.com" ;;
      3) url="https://www.linkedin.com/in/darkguyaiman" ;;
      4) url="https://www.instagram.com/darkguyaiman" ;;
      5) url="https://x.com/thedarkguyaiman" ;;
      6) url="https://ko-fi.com/darkguyaiman" ;;
      7) url="https://paypal.me/thedarkguyaiman" ;;
      ""|$'\e') return ;;
      *) continue ;;
    esac
    if [[ "$OS" == "macos" ]]; then run open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then run xdg-open "$url"
    else warn "Open this address in your browser: $url"
    fi
    last_cols=-1
  done
}

run() {
  printf '%s+%s ' "$BLUE" "$RESET"
  printf '%q ' "$@"
  printf '\n'
  [[ $DRY_RUN -eq 1 ]] || "$@"
}

root_run() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    run "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo "$@"
  else
    die "This action needs root access, but sudo is not installed."
  fi
}

root_run_secret() {
  local token=$1
  printf '%s+%s cloudflared service install <TUNNEL_TOKEN hidden>\n' "$BLUE" "$RESET"
  [[ $DRY_RUN -eq 1 ]] && return 0
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    cloudflared service install "$token"
  elif command -v sudo >/dev/null 2>&1; then
    sudo cloudflared service install "$token"
  else
    die "This action needs root access, but sudo is not installed."
  fi
}

valid_cloudflare_tunnel_token() {
  local token=$1 normalized decoded padding
  [[ "$token" =~ ^eyJ[A-Za-z0-9_-]{20,}$ ]] || return 1
  normalized=${token//-/+}
  normalized=${normalized//_/\/}
  case $((${#normalized} % 4)) in
    2) padding='==' ;;
    3) padding='=' ;;
    1) return 1 ;;
    *) padding='' ;;
  esac
  normalized+=$padding
  decoded=$(printf '%s' "$normalized" | base64 --decode 2>/dev/null ||
    printf '%s' "$normalized" | base64 -D 2>/dev/null || true)
  [[ "$decoded" == \{*\} && "$decoded" == *'"a"'* && "$decoded" == *'"t"'* && "$decoded" == *'"s"'* ]]
}

confirm() {
  local prompt=${1:-"Continue?"} answer
  [[ $DRY_RUN -eq 1 ]] && return 0
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

read_hidden_paste_input() {
  local prompt=$1 character visible_stars=0 maximum_stars=12
  HIDDEN_PASTE_VALUE=""
  printf '%s ' "$prompt"
  while IFS= read -rsn1 character; do
    [[ -n "$character" ]] || break
    case "$character" in
      $'\b'|$'\177')
        if [[ -n "$HIDDEN_PASTE_VALUE" ]]; then
          HIDDEN_PASTE_VALUE=${HIDDEN_PASTE_VALUE%?}
          if ((visible_stars > 0 && ${#HIDDEN_PASTE_VALUE} < maximum_stars)); then
            printf '\b \b'
            visible_stars=$((visible_stars - 1))
          fi
        fi
        ;;
      *)
        HIDDEN_PASTE_VALUE+=$character
        if ((visible_stars < maximum_stars)); then
          printf '*'
          visible_stars=$((visible_stars + 1))
        fi
        ;;
    esac
  done
  printf '\n'
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found."
}

detect_platform() {
  case "$(uname -s)" in
    Darwin)
      OS="macos"
      command -v brew >/dev/null 2>&1 ||
        die "Homebrew is required on macOS. Install it from https://brew.sh and run this again."
      PKG="brew"
      ;;
    Linux)
      OS="linux"
      if command -v apt-get >/dev/null 2>&1; then PKG="apt"
      elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
      elif command -v yum >/dev/null 2>&1; then PKG="yum"
      elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
      elif command -v zypper >/dev/null 2>&1; then PKG="zypper"
      else die "Supported package manager not found (apt, dnf, yum, pacman, or zypper)."
      fi
      ;;
    *) die "Unsupported operating system. On Windows, run neem.ps1 in PowerShell." ;;
  esac
}

update_neem() {
  local repository="https://github.com/Darkguyaiman/NEEM-Stack-Setup.git"
  local archive_url="https://github.com/Darkguyaiman/NEEM-Stack-Setup/archive/refs/heads/main.zip"
  local current latest temp_root temp_base archive source new_version changes backup stamp ancestor_status
  rule "NEEM UPDATE"
  if ((DRY_RUN)); then
    info 'Would fetch the latest NEEM, save local edits automatically, and update program files.'
    return
  fi
  if [[ -e "$SCRIPT_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
    info "Checking GitHub for updates..."
    package_step '' run git -C "$SCRIPT_DIR" fetch origin main || return 1
    current=$(git -C "$SCRIPT_DIR" rev-parse HEAD) || return 1
    latest=$(git -C "$SCRIPT_DIR" rev-parse FETCH_HEAD) || return 1
    changes=$(git -C "$SCRIPT_DIR" status --porcelain) || return 1
    stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    if [[ -n "$changes" ]]; then
      package_step '' run git -c user.name=NEEM -c user.email=neem@localhost -C "$SCRIPT_DIR" stash push --include-untracked -m "NEEM automatic update backup $stamp" || return 1
      backup=$(git -C "$SCRIPT_DIR" rev-parse refs/stash) || return 1
      info "Local edits saved automatically in Git stash $backup."
    fi
    if [[ "$current" == "$latest" ]]; then
      new_version=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")
      ok "NEEM v$new_version is up to date."
      return
    else
      if git -C "$SCRIPT_DIR" merge-base --is-ancestor "$current" "$latest"; then
        package_step 'Applying update' run git -C "$SCRIPT_DIR" merge --ff-only "$latest" || return 1
      else
        ancestor_status=$?
        ((ancestor_status == 1)) || return "$ancestor_status"
        backup="neem-backup-$stamp"
        package_step '' run git -C "$SCRIPT_DIR" branch "$backup" "$current" || return 1
        info "Local commits saved on branch $backup."
        package_step 'Applying update' run git -C "$SCRIPT_DIR" reset --keep "$latest" || return 1
      fi
      new_version=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")
    fi
  else
    warn "This copy was downloaded without Git history."
    confirm "Download the latest files from $repository and replace NEEM program files?" || return
    need_command curl
    need_command unzip
    temp_root=$(mktemp -d)
    archive="$temp_root/neem-main.zip"
    info "Downloading the latest NEEM release files from GitHub..."
    package_step '' run curl --fail --location --output "$archive" "$archive_url" || return 1
    package_step '' run unzip -q "$archive" -d "$temp_root" || return 1
    source=$(find "$temp_root" -mindepth 1 -maxdepth 1 -type d -name 'NEEM-Stack-Setup-*' | head -n1)
    [[ -n "$source" && -r "$source/VERSION" ]] || die "The downloaded NEEM archive was not valid."
    package_step 'Applying update' run cp -R "$source/." "$SCRIPT_DIR/" || return 1
    new_version=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")
    temp_base=${TMPDIR:-/tmp}
    temp_base=${temp_base%/}
    case "$temp_root" in
      "$temp_base"/*) rm -rf -- "$temp_root" ;;
      *) warn "Temporary update files were retained at $temp_root." ;;
    esac
  fi
  package_step '' run bash "$SCRIPT_DIR/install-neem-command.sh" || return 1
  ok "Updated to NEEM v$new_version."
  info 'Run neem to continue.'
}
