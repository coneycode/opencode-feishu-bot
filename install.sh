#!/usr/bin/env bash
# =============================================================================
# opencode-feishu-bot — 一键安装脚本
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

info()    { echo -e "${BLUE}[信息]${NC}  $*"; }
success() { echo -e "${GREEN}[✓]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[警告]${NC}  $*"; }
error()   { echo -e "${RED}[✗]${NC}    $*" >&2; }
step()    { echo -e "\n${BOLD}$*${NC}"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

check_deps() {
  local missing=()
  for cmd in curl bun; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "缺少必要工具：${missing[*]}"
    echo ""
    if [[ " ${missing[*]} " == *" bun "* ]]; then
      echo "  安装 bun：  curl -fsSL https://bun.sh/install | bash"
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
    info "$dep_name 已在 package.json 中 — 跳过"
    return
  fi

  # Add the dependency
  python3 -c "
import json
data = json.load(open('$pkg_file'))
data.setdefault('dependencies', {})['$dep_name'] = '$dep_version'
open('$pkg_file', 'w').write(json.dumps(data, indent=2) + '\n')
"
  success "已添加 $dep_name@$dep_version 到 package.json"
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
  echo -e "${BOLD}=== opencode-feishu-bot 安装程序 ===${NC}"
  echo "   https://github.com/coneycode/opencode-feishu-bot"
  echo ""

  # ── 0. Dependency check ───────────────────────────────────────────────────
  step "第 0 步  检查依赖工具..."
  check_deps
  success "bun 和 curl 均已安装"

  # macOS-only: Keychain
  if [[ "$(uname)" != "Darwin" ]]; then
    warn "当前系统非 macOS，无法使用钥匙串存储 App Secret。"
    warn "请手动在 .env 中设置 FEISHU_APP_SECRET。"
    SKIP_KEYCHAIN=1
  else
    SKIP_KEYCHAIN=0
  fi

  # ── 1. Create directories ─────────────────────────────────────────────────
  step "第 1 步  创建目录..."
  mkdir -p "$PLUGINS_DIR"
  success "插件目录已就绪：$PLUGINS_DIR"

  # ── 2. Download plugin file ───────────────────────────────────────────────
  step "第 2 步  下载插件文件..."
  curl -fsSL "$PLUGIN_SRC" -o "$PLUGINS_DIR/feishu-bot.ts"
  success "插件已保存到：$PLUGINS_DIR/feishu-bot.ts"

  # ── 3. Update package.json ────────────────────────────────────────────────
  step "第 3 步  更新 package.json..."
  ensure_dependency "$PKG_FILE" "$LARK_SDK" "$LARK_SDK_VERSION"

  # ── 4. Install npm deps ───────────────────────────────────────────────────
  step "第 4 步  安装依赖..."
  bun install --cwd "$OPENCODE_DIR"
  success "依赖安装完成"

  # ── 5. Configure credentials ──────────────────────────────────────────────
  step "第 5 步  配置飞书凭证"
  echo ""
  echo "  需要从飞书自建应用获取两个凭证："
  echo "  → App ID     （非敏感，保存到 .env）"
  echo "  → App Secret （敏感，保存到 macOS 钥匙串）"
  echo ""
  echo "  还没有飞书应用？请先前往："
  echo "  https://open.feishu.cn/app  →  新建自建应用  →  开启机器人  →  订阅长连接事件"
  echo ""

  # ── App ID ────────────────────────────────────────────────────────────────
  local current_app_id=""
  if [[ -f "$ENV_FILE" ]]; then
    current_app_id=$(grep -E '^FEISHU_APP_ID=' "$ENV_FILE" | cut -d= -f2 | tr -d ' ' || true)
  fi

  if [[ -n "$current_app_id" ]]; then
    echo -e "  当前 App ID：${YELLOW}$current_app_id${NC}"
    read -rp "  保留原有 App ID？[Y/n] " keep_id
    if [[ "${keep_id:-Y}" =~ ^[Nn]$ ]]; then
      current_app_id=""
    fi
  fi

  if [[ -z "$current_app_id" ]]; then
    while true; do
      read -rp "  请输入飞书 App ID（以 cli_ 开头）：" input_app_id
      input_app_id="${input_app_id// /}"
      if [[ "$input_app_id" =~ ^cli_ ]]; then
        current_app_id="$input_app_id"
        break
      else
        warn "App ID 应以 'cli_' 开头，请重新输入。"
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
  success "App ID 已写入 $ENV_FILE"

  # ── App Secret ────────────────────────────────────────────────────────────
  if [[ "$SKIP_KEYCHAIN" == "0" ]]; then
    local existing_secret
    existing_secret=$(keychain_read)

    if [[ -n "$existing_secret" ]]; then
      echo ""
      echo -e "  钥匙串中已存有 App Secret（service=${KEYCHAIN_SERVICE}）"
      read -rp "  是否更新？[y/N] " update_secret
      if [[ "${update_secret:-N}" =~ ^[Yy]$ ]]; then
        existing_secret=""
      fi
    fi

    if [[ -z "$existing_secret" ]]; then
      echo ""
      read -rsp "  请输入飞书 App Secret（输入不可见）：" input_secret
      echo ""
      if [[ -n "$input_secret" ]]; then
        keychain_write "$input_secret"
        success "App Secret 已保存到 macOS 钥匙串"
      else
        warn "未输入 Secret — 跳过钥匙串写入。插件启动时将因缺少凭证而跳过。"
      fi
    else
      success "钥匙串中已有 App Secret — 已跳过"
    fi
  else
    warn "非 macOS 系统，跳过钥匙串配置。"
    warn "请手动在 $ENV_FILE 中添加：FEISHU_APP_SECRET=<你的secret>"
  fi

  # ── 6. Summary ────────────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}=== 安装完成！===${NC}"
  echo ""
  echo "  插件路径：$PLUGINS_DIR/feishu-bot.ts"
  echo "  配置文件：$ENV_FILE"
  echo ""
  echo -e "  ${GREEN}下一步：运行 ${BOLD}opencode${NC}${GREEN}，日志中应出现：${NC}"
  echo "  [feishu-bot] 飞书机器人已启动（长连接模式），appId=cli_xxx***"
  echo ""
  echo "  遇到问题？→ https://github.com/coneycode/opencode-feishu-bot"
  echo ""
}

main "$@"
