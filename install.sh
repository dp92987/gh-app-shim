#!/usr/bin/env bash
#
# Installer for gh-app-shim. Idempotent — safe to re-run.
#
#   1. Requires a real `gh` binary to already be installed (see
#      https://github.com/cli/cli#installation).
#   2. Symlinks bin/gh into ~/.local/bin/gh so it shadows the real gh on PATH.
#   3. Seeds ~/.config/gh-app-shim/config.env from config.example.env.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM_SRC="$REPO_DIR/bin/gh"
SHIM_DST="${SHIM_DST:-$HOME/.local/bin/gh}"
CONFIG_DIR="$HOME/.config/gh-app-shim"
CONFIG_FILE="$CONFIG_DIR/config.env"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

# --- 1. real gh -------------------------------------------------------------
find_existing_gh() {
  local shim_resolved cand resolved
  shim_resolved=$(readlink -f "$SHIM_DST" 2>/dev/null || true)
  for cand in $(type -ap gh 2>/dev/null); do
    resolved=$(readlink -f "$cand" 2>/dev/null || printf '%s' "$cand")
    [[ -n "$shim_resolved" && "$resolved" == "$shim_resolved" ]] && continue
    [[ "$resolved" == "$SHIM_SRC" ]] && continue
    printf '%s' "$cand"
    return 0
  done
  return 1
}

REAL_GH_PATH=""
if existing=$(find_existing_gh); then
  REAL_GH_PATH="$existing"
  log "using existing gh: $REAL_GH_PATH"
else
  die "no real gh found on PATH. Install the GitHub CLI first
        (https://github.com/cli/cli#installation), then re-run this script.
        If gh lives somewhere off PATH, set REAL_GH in $CONFIG_FILE."
fi

# --- 2. shim symlink --------------------------------------------------------
chmod +x "$SHIM_SRC"
mkdir -p "$(dirname "$SHIM_DST")"
ln -sf "$SHIM_SRC" "$SHIM_DST"
log "linked shim: $SHIM_DST -> $SHIM_SRC"

case ":$PATH:" in
  *":$(dirname "$SHIM_DST"):"*) ;;
  *) warn "$(dirname "$SHIM_DST") is not on your PATH — add it so the shim takes effect" ;;
esac

# --- 3. config --------------------------------------------------------------
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
if [[ -f "$CONFIG_FILE" ]]; then
  log "config already present: $CONFIG_FILE (left untouched)"
else
  cp "$REPO_DIR/config.example.env" "$CONFIG_FILE"
  # Pin REAL_GH so the shim never has to guess.
  {
    echo ""
    echo "REAL_GH=$REAL_GH_PATH"
  } >> "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log "seeded config: $CONFIG_FILE"
fi

cat <<EOF

Done. Final steps:
  1. Put the GitHub App private key at the KEY_PATH from $CONFIG_FILE
     (default: $CONFIG_DIR/app.pem), then: chmod 600 that file.
  2. Verify the values in $CONFIG_FILE (APP_ID, INSTALLATION_ID).
  3. Test as the bot:   CLAUDECODE=1 gh api /installation/repositories --jq '.repositories[].full_name'
     Test as yourself:  gh api user --jq .login                 # -> your login
EOF
