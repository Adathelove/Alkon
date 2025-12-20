#!/usr/bin/env bash
# Alkon CLI (init, list; fzf)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/boilerplate.sh" ]]; then
  source "$SCRIPT_DIR/boilerplate.sh"
else
  info() { echo "[Info] $*"; }
  warn() { echo "[Warn] $*"; }
  fail() { echo "[Fail] $*"; }
fi

CONFIG_PATH="Alkon.toml"
TOOL_CHEST=""

show_usage() {
  cat <<'EOF'
Alkon CLI (WIP)
Usage: ./Alkon.sh [--config=Alkon.toml] [command]

Commands:
  init          create or update Alkon.toml with detected GitHub user
  --list        list repos for configured user
  --fzf         fzf-select repo and clone into tool chest

Options:
  --config=PATH   Use alternate config path (default: Alkon.toml in this dir)
  --tool-chest=PATH  Override tool chest path for this run
  -h, --help      Show this help

Status: init, list implemented; fzf clones into tool chest.
EOF
}

CMD=""

parse_args() {
  for arg in "$@"; do
  case "$arg" in
      --config=*)
        CONFIG_PATH="${arg#*=}"
        ;;
      --tool-chest=*)
        TOOL_CHEST="${arg#*=}"
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      init|--list|--fzf)
        CMD="$arg"
        ;;
    esac
  done
}

parse_args "$@"

init_cmd() {
  if [[ -f "$CONFIG_PATH" ]]; then
    warn "Config already exists at $CONFIG_PATH; skipping init."
    exit 0
  fi
  # Detect owner via gh or git config
  detected=""
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    detected="$(gh api user --jq .login 2>/dev/null || true)"
  fi
  if [[ -z "$detected" ]]; then
    detected="$(git config --global github.user 2>/dev/null || true)"
  fi
  if [[ -z "$detected" ]]; then
    detected="$(git config --global user.name 2>/dev/null | awk '{print $1}')"
  fi

  if [[ -n "$detected" ]]; then
    info "Detected GitHub user: $detected"
  else
  warn "Could not detect GitHub user automatically."
fi

read -rp "GitHub owner to use [${detected:-enter username}]: " owner
  if [[ -z "$owner" ]]; then
    owner="$detected"
  fi

  if [[ -z "$owner" ]]; then
    fail "Owner is required."
    exit 1
  fi

  default_tool="${TOOL_CHEST:-AlkonToolChest}"
  read -rp "Tool chest path to use [${default_tool}]: " chest
  if [[ -z "$chest" ]]; then
    chest="$default_tool"
  fi
  if [[ -z "$chest" ]]; then
    fail "Tool chest path is required."
    exit 1
  fi

  cat > "$CONFIG_PATH" <<EOF
[github]
owner = "$owner"
[paths]
tool_chest = "$chest"
EOF

  info "Wrote config to $CONFIG_PATH"
}

list_cmd() {
  if ! [[ -f "$CONFIG_PATH" ]]; then
    fail "Config missing: $CONFIG_PATH (run init first)"
    exit 1
  fi
  owner="$(awk -F'=' '/owner/ {gsub(/[ \t"]/, "", $2); print $2}' "$CONFIG_PATH" | head -n1)"
  if [[ -z "$owner" ]]; then
    fail "Owner not set in $CONFIG_PATH (run init)."
    exit 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    fail "GitHub CLI (gh) is required."
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    fail "gh auth status failed; run 'gh auth login'."
    exit 1
  fi
  info "Listing repos for $owner"
  gh repo list "$owner" --limit 200 --json name,visibility,updatedAt,stargazerCount --jq '.[] | [.name, .visibility, (.stargazerCount|tostring), .updatedAt[0:10]] | @tsv' | column -t
}

fzf_cmd() {
  if ! command -v fzf >/dev/null 2>&1; then
    fail "fzf is required for --fzf."
    warn "Install macOS: brew install fzf && $(brew --prefix fzf)/install"
    warn "Debian/Ubuntu: sudo apt update && sudo apt install fzf"
    warn "Fedora: sudo dnf install fzf"
    warn "Arch: sudo pacman -S fzf"
    exit 1
  fi
  if ! [[ -f "$CONFIG_PATH" ]]; then
    fail "Config missing: $CONFIG_PATH (run init first)"
    exit 1
  fi
  owner="$(awk -F'=' '/owner/ {gsub(/[ \t"]/, "", $2); print $2}' "$CONFIG_PATH" | head -n1)"
  if [[ -z "$owner" ]]; then
    fail "Owner not set in $CONFIG_PATH (run init)."
    exit 1
  fi
  info "DEBUG owner='$owner'"
  chest_cfg="$(awk -F'=' '/tool_chest/ {gsub(/[ \t"]/, "", $2); print $2}' "$CONFIG_PATH" | head -n1)"
  chest="${TOOL_CHEST:-$chest_cfg}"
  info "DEBUG chest_cfg='$chest_cfg' TOOL_CHEST_override='${TOOL_CHEST:-}' resolved_chest='$chest'"
  if [[ -z "$chest" ]]; then
    chest="AlkonToolChest"
  fi

  if ! command -v gh >/dev/null 2>&1; then
    fail "GitHub CLI (gh) is required."
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    fail "gh auth status failed; run 'gh auth login'."
    exit 1
  fi

  info "Fetching repos for ${owner}..."
  repos="$(gh repo list "$owner" --limit 200 --json name,visibility,stargazerCount,sshUrl,updatedAt --jq '.[] | [.name, .visibility, (.stargazerCount|tostring), .updatedAt[0:10], .sshUrl] | @tsv')"
  if [[ -z "$repos" ]]; then
    warn "No repos found for ${owner}"
    exit 0
  fi

  selected="$(printf '%s\n' "$repos" | fzf --with-nth=1,2,3,4 --prompt='Clone repo> ')"
  if [[ -z "$selected" ]]; then
    warn "No repo selected."
    exit 0
  fi

  repo_name="$(printf '%s' "$selected" | awk '{print $1}')"
  repo_url="$(printf '%s' "$selected" | awk '{print $5}')"

  if [[ -z "$repo_url" ]]; then
    fail "Could not parse repo URL from selection."
    exit 1
  fi

  mkdir -p "$chest"
  target="$chest/$repo_name"
  if [[ -d "$target/.git" ]]; then
    warn "Repo already cloned at $target"
    exit 0
  fi

  info "Cloning $repo_name -> $target"
  git clone "$repo_url" "$target"
  info "Done."
}

main() {
  case "$CMD" in
    init)
      init_cmd
      ;;
    --list)
      list_cmd
      ;;
    --fzf)
      fzf_cmd
      ;;
    "")
      show_usage
      ;;
    *)
      fail "Unknown command: $CMD"
      exit 1
      ;;
  esac
}

if [[ -f "$CONFIG_PATH" ]]; then
  info "Found config: $CONFIG_PATH"
else
  warn "Config missing: $CONFIG_PATH"
  warn "Run './Alkon.sh init' to create the config."
fi

main
