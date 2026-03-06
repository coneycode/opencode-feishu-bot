#!/usr/bin/env bash
# =============================================================================
# opencode-feishu-bot — One-click installer
# https://github.com/coneycode/opencode-feishu-bot
# =============================================================================

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/coneycode/opencode-feishu-bot/main"
PLUGIN_SRC="$REPO_URL/src/index.ts"
OPENCODE_DIR="$HOME/.config/opencode"
PLUGINS_DIR="$OPENCODE_DIR/plugins"
PKG_FILE="$OPENCODE_DIR/package.json"
ENV_FILE="$OPENCODE_DIR/.env"
LARK_SDK="@larksuiteoapi/node-sdk"
LARK_SDK_VERSION="^1.37.0"
KEYCHAIN_SERVICE="opencode-feishu-bot"
KEYCHAIN_ACCOUNT="feishu-bot"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[✓]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[✗]${NC}    $*" >&2; }
step()    { echo -e "\n${BOLD}$*${NC}"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

check_deps() {
  local missing=()
  for cmd in curl bun; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing[*]}"
    echo ""
    if [[ " ${missing[*]} " == *" bun "* ]]; then
      echo "  Install bun:  curl -fsSL https://bun.sh/install | bash"
    fi
    exit 1
  fi
}

# Merge a dependency into package.json (creates file if missing)
ensure_dependency() {
  local pkg_file="$1"
  local dep_name="$2"
  local dep_version="$3"

  if [[ ! -f "$pkg_file" ]]; then
    echo '{"dependencies":{}}' > "$pkg_file"
  fi

  # Check if dep already present
  if python3 -c "
import json, sys
data = json.load(open('$pkg_file'))
deps = data.get('dependencies', {})
sys.exit(0 if '$dep_name' in deps else 1)
" 2>/dev/null; then
    info "$dep_name already in package.json — skipping"
    return
  fi

  # Add the dependency
  python3 -c "
import json
data = json.load(open('$pkg_file'))
data.setdefault('dependencies', {})['$dep_name'] = '$dep_version'
open('$pkg_file', 'w').write(json.dumps(data, indent=2) + '\n')
"
  success "Added $dep_name@$dep_version to package.json"
}

keychain_read() {
  security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true
}

keychain_write() {
  local secret="$1"
  security add-generic-password \
    -a "$KEYCHAIN_ACCOUNT" \
    -s "$KEYCHAIN_SERVICE" \
    -w "$secret" \
    -U
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo -e "${BOLD}=== opencode-feishu-bot installer ===${NC}"
  echo "   https://github.com/coneycode/opencode-feishu-bot"
  echo ""

  # ── 0. Dependency check ───────────────────────────────────────────────────
  step "Step 0  Checking dependencies..."
  check_deps
  success "bun and curl are available"

  # macOS-only: Keychain
  if [[ "$(uname)" != "Darwin" ]]; then
    warn "macOS Keychain not available on this OS."
    warn "You will need to set FEISHU_APP_SECRET in your .env manually."
    SKIP_KEYCHAIN=1
  else
    SKIP_KEYCHAIN=0
  fi

  # ── 1. Create directories ─────────────────────────────────────────────────
  step "Step 1  Creating directories..."
  mkdir -p "$PLUGINS_DIR"
  success "Plugins dir ready: $PLUGINS_DIR"

  # ── 2. Download plugin file ───────────────────────────────────────────────
  step "Step 2  Downloading plugin..."
  curl -fsSL "$PLUGIN_SRC" -o "$PLUGINS_DIR/feishu-bot.ts"
  success "Plugin saved to: $PLUGINS_DIR/feishu-bot.ts"

  # ── 3. Update package.json ────────────────────────────────────────────────
  step "Step 3  Updating package.json..."
  ensure_dependency "$PKG_FILE" "$LARK_SDK" "$LARK_SDK_VERSION"

  # ── 4. Install npm deps ───────────────────────────────────────────────────
  step "Step 4  Installing dependencies..."
  bun install --cwd "$OPENCODE_DIR"
  success "Dependencies installed"

  # ── 5. Configure credentials ──────────────────────────────────────────────
  step "Step 5  Configure Feishu credentials"
  echo ""
  echo "  You need two credentials from your Feishu self-built app:"
  echo "  → App ID    (non-sensitive, stored in .env)"
  echo "  → App Secret (sensitive, stored in macOS Keychain)"
  echo ""
  echo "  If you haven't created an app yet:"
  echo "  https://open.feishu.cn/app  →  Create app  →  Enable Bot  →  Enable long connection events"
  echo ""

  # ── App ID ────────────────────────────────────────────────────────────────
  local current_app_id=""
  if [[ -f "$ENV_FILE" ]]; then
    current_app_id=$(grep -E '^FEISHU_APP_ID=' "$ENV_FILE" | cut -d= -f2 | tr -d ' ' || true)
  fi

  if [[ -n "$current_app_id" ]]; then
    echo -e "  Current App ID: ${YELLOW}$current_app_id${NC}"
    read -rp "  Keep it? [Y/n] " keep_id
    if [[ "${keep_id:-Y}" =~ ^[Nn]$ ]]; then
      current_app_id=""
    fi
  fi

  if [[ -z "$current_app_id" ]]; then
    while true; do
      read -rp "  Enter your Feishu App ID (cli_...): " input_app_id
      input_app_id="${input_app_id// /}"
      if [[ "$input_app_id" =~ ^cli_ ]]; then
        current_app_id="$input_app_id"
        break
      else
        warn "App ID should start with 'cli_', please try again."
      fi
    done
  fi

  # Write/update App ID in .env
  if [[ -f "$ENV_FILE" ]] && grep -q '^FEISHU_APP_ID=' "$ENV_FILE"; then
    # Update existing
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^FEISHU_APP_ID=.*|FEISHU_APP_ID=$current_app_id|" "$ENV_FILE"
    else
      sed -i "s|^FEISHU_APP_ID=.*|FEISHU_APP_ID=$current_app_id|" "$ENV_FILE"
    fi
  else
    echo "" >> "$ENV_FILE" 2>/dev/null || true
    echo "FEISHU_APP_ID=$current_app_id" >> "$ENV_FILE"
  fi
  success "App ID written to $ENV_FILE"

  # ── App Secret ────────────────────────────────────────────────────────────
  if [[ "$SKIP_KEYCHAIN" == "0" ]]; then
    local existing_secret
    existing_secret=$(keychain_read)

    if [[ -n "$existing_secret" ]]; then
      echo ""
      echo -e "  App Secret already stored in Keychain (service=$KEYCHAIN_SERVICE)"
      read -rp "  Update it? [y/N] " update_secret
      if [[ "${update_secret:-N}" =~ ^[Yy]$ ]]; then
        existing_secret=""
      fi
    fi

    if [[ -z "$existing_secret" ]]; then
      echo ""
      read -rsp "  Enter your Feishu App Secret (input hidden): " input_secret
      echo ""
      if [[ -n "$input_secret" ]]; then
        keychain_write "$input_secret"
        success "App Secret saved to macOS Keychain"
      else
        warn "No secret entered — skipping Keychain write. Plugin will not start without it."
      fi
    else
      success "App Secret already in Keychain — skipped"
    fi
  else
    warn "Skipping Keychain setup (non-macOS)."
    warn "Manually add to $ENV_FILE:  FEISHU_APP_SECRET=<your_secret>"
  fi

  # ── 6. Summary ────────────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}=== Installation complete! ===${NC}"
  echo ""
  echo "  Plugin: $PLUGINS_DIR/feishu-bot.ts"
  echo "  Config: $ENV_FILE"
  echo ""
  echo -e "  ${GREEN}Next step: run ${BOLD}opencode${NC}${GREEN} and you should see:${NC}"
  echo "  [feishu-bot] 飞书机器人已启动（长连接模式），appId=cli_xxx***"
  echo ""
  echo "  Need help? → https://github.com/coneycode/opencode-feishu-bot"
  echo ""
}

main "$@"
