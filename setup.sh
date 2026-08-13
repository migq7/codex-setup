#!/usr/bin/env bash
#
# codex-setup — one-click install / self-check / uninstall for the Codex
# LSP bridge (clangd + basedpyright) and the associated developer instructions.
#
# Install first lets you choose which model configurator to run — DeepSeek
# (scripts/codex-deepseek-setup.sh) or OpenCode Go
# (scripts/codex-opencode-go-setup.sh) — so the default Codex model can be
# switched in the same flow; pass --skip-deepseek to skip that step.
#
# The Codex CLI has no built-in LSP configuration, so this project wires
# language servers into Codex through an MCP bridge (codex-lsp-bridge).
# Everything in this script is idempotent: re-running it only fixes what is
# missing and leaves your existing ~/.codex/config.toml values untouched.
#
# Usage:
#   ./setup.sh             install (idempotent) then run the self-check; asks
#                          whether to configure DeepSeek or OpenCode Go first
#   ./setup.sh --skip-deepseek
#                          install without the model-provider menu
#   CODEX_MODEL_PROVIDER=opencode ./setup.sh
#                          skip the prompt and configure OpenCode Go directly
#                          (values: deepseek | opencode | skip)
#   ./setup.sh --check     run the self-check only
#   ./setup.sh --uninstall remove the LSP bridge MCP entry, venv and the
#                           managed developer_instructions block
#   ./setup.sh --help      show this help
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Remember whether CODEX_DIR was explicitly set before the default is applied,
# so the DeepSeek step can target the same directory via CODEX_HOME.
CODEX_DIR_OVERRIDDEN=0
[[ -n "${CODEX_DIR:-}" ]] && CODEX_DIR_OVERRIDDEN=1

# Overridable locations (mainly useful for testing the script).
CODEX_DIR="${CODEX_DIR:-$HOME/.codex}"
CODEX_CONFIG="${CODEX_CONFIG:-$CODEX_DIR/config.toml}"
VENV_DIR="${VENV_DIR:-$CODEX_DIR/lsp-mcp-venv}"
DEEPSEEK_SETUP_SCRIPT="${DEEPSEEK_SETUP_SCRIPT:-$PROJECT_DIR/scripts/codex-deepseek-setup.sh}"
OPENCODE_GO_SETUP_SCRIPT="${OPENCODE_GO_SETUP_SCRIPT:-$PROJECT_DIR/scripts/codex-opencode-go-setup.sh}"

BRIDGE_CONFIG="$PROJECT_DIR/config/lsp-mcp-config.toml"
MCP_NAME="lsp_bridge"
BRIDGE_REPO="https://github.com/CesarPetrescu/lsp-mcp.git"
BRIDGE_PIN="aaa98e777fa807a31e048b1c6d16cdddeaf9ef27"
BASEDPYRIGHT_VERSION="1.39.9"

info() { printf '\033[1;36m[codex-setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[codex-setup]\033[0m WARN: %s\n' "$*" >&2; }
err() { printf '\033[1;31m[codex-setup]\033[0m ERROR: %s\n' "$*" >&2; }

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

check_prereqs() {
  command -v codex >/dev/null 2>&1 || { err "codex CLI not found on PATH (install Codex first)"; exit 1; }
  command -v python3 >/dev/null 2>&1 || { err "python3 >= 3.10 not found"; exit 1; }
  command -v git >/dev/null 2>&1 || { err "git not found (needed to install the bridge from GitHub)"; exit 1; }
  if ! command -v clangd >/dev/null 2>&1; then
    warn "clangd not found on PATH — C/C++/CUDA LSP will not work until you install it"
    warn "e.g. on Debian/Ubuntu: sudo apt install clangd  (or the llvm package for your distro)"
  fi
}

install_venv() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    info "creating venv at $VENV_DIR"
    python3 -m venv "$VENV_DIR"
  fi
  info "upgrading pip in the venv"
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip

  if [[ ! -x "$VENV_DIR/bin/codex-lsp-bridge" ]]; then
    info "installing codex-lsp-bridge (pinned @ $BRIDGE_PIN)"
    "$VENV_DIR/bin/pip" install --quiet "git+$BRIDGE_REPO@$BRIDGE_PIN"
  else
    info "codex-lsp-bridge already installed"
  fi

  if [[ ! -x "$VENV_DIR/bin/basedpyright-langserver" ]]; then
    info "installing basedpyright==$BASEDPYRIGHT_VERSION"
    "$VENV_DIR/bin/pip" install --quiet "basedpyright==$BASEDPYRIGHT_VERSION"
  else
    info "basedpyright already installed"
  fi
}

install_mcp_entry() {
  info "registering '$MCP_NAME' MCP server in $CODEX_CONFIG"
  # --env makes the venv/bin and system paths available to the bridge, so the
  # bridge config can use bare command names and stays portable across machines.
  codex mcp add "$MCP_NAME" \
    --env "PATH=$VENV_DIR/bin:$PATH" \
    -- "$VENV_DIR/bin/codex-lsp-bridge" \
    serve --transport stdio --config "$BRIDGE_CONFIG"
}

install_developer_instructions() {
  if grep -q '^developer_instructions' "$CODEX_CONFIG"; then
    info "developer_instructions already present in $CODEX_CONFIG — leaving untouched"
    return 0
  fi
  local backup="$CODEX_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CODEX_CONFIG" "$backup"
  info "adding developer_instructions (backup: $backup)"
  python3 - "$CODEX_CONFIG" <<'PY'
import sys

path = sys.argv[1]
block = '''# MANAGED BY codex-setup (see ~/codex-setup/README.md)
developer_instructions = """
You have access to MCP tools from the Codex LSP Bridge (clangd for C/C++/CUDA, basedpyright for Python). Use them for precise, semantic code navigation and safe refactors; they understand symbols, types, and project configs. Prefer these tools over text search to avoid false matches and missed references.

How to use:
- Prefer absolute file paths.
- line/column are 0-indexed.
- For rename: call find_references to validate scope, then rename_symbol and apply the WorkspaceEdit.
- workspace_symbols only searches workspaces that have an active LSP client (open a file first).
- Use workspace_root to force a specific repo root (useful for monorepos or nested repos).
- If line/column might be off, set fuzzy=true to try nearby positions.
- If a tool fails, report the error and only then fall back to text search.
"""
'''
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
# Insert before the first TOML table header so the key stays top-level.
idx = next((i for i, line in enumerate(lines) if line.lstrip().startswith("[")), len(lines))
lines[idx:idx] = [block]
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print("  developer_instructions added")
PY
}

run_deepseek_setup() {
  if [[ ! -f "$DEEPSEEK_SETUP_SCRIPT" ]]; then
    err "DeepSeek setup script not found: $DEEPSEEK_SETUP_SCRIPT"
    err "set DEEPSEEK_SETUP_SCRIPT to its location, or pass --skip-deepseek"
    exit 1
  fi
  info "running DeepSeek model setup ($DEEPSEEK_SETUP_SCRIPT)"
  info "pick 1/2 to switch the default model, 3 to restore the default config"
  if [[ "$CODEX_DIR_OVERRIDDEN" -eq 1 ]]; then
    info "CODEX_DIR is set, aligning the DeepSeek step via CODEX_HOME=$CODEX_DIR"
    CODEX_HOME="$CODEX_DIR" bash "$DEEPSEEK_SETUP_SCRIPT"
  else
    bash "$DEEPSEEK_SETUP_SCRIPT"
  fi
}

run_opencode_go_setup() {
  if [[ ! -f "$OPENCODE_GO_SETUP_SCRIPT" ]]; then
    err "OpenCode Go setup script not found: $OPENCODE_GO_SETUP_SCRIPT"
    err "set OPENCODE_GO_SETUP_SCRIPT to its location, or pass --skip-deepseek"
    exit 1
  fi
  info "running OpenCode Go model setup ($OPENCODE_GO_SETUP_SCRIPT)"
  info "pick 1..N to switch the default model, r to restore the default config"
  if [[ "$CODEX_DIR_OVERRIDDEN" -eq 1 ]]; then
    info "CODEX_DIR is set, aligning the OpenCode Go step via CODEX_HOME=$CODEX_DIR"
    CODEX_HOME="$CODEX_DIR" bash "$OPENCODE_GO_SETUP_SCRIPT"
  else
    bash "$OPENCODE_GO_SETUP_SCRIPT"
  fi
}

choose_model_provider() {
  local choice="${CODEX_MODEL_PROVIDER:-}"
  if [[ -z "$choice" ]]; then
    while :; do
      info "请选择要配置的模型提供方："
      info "  1) DeepSeek 官方 API"
      info "  2) OpenCode Go（订阅制，经 opencode.ai/zen/go）"
      info "  s) 跳过模型配置（只装 LSP 桥）"
      if ! read -r -p "[codex-setup] 输入 1 / 2 / s（回车默认 1）: " choice; then
        choice=1
        break
      fi
      [[ -z "$choice" ]] && choice=1
      case "$choice" in
        1|2|s|S) break ;;
      esac
      warn "无效输入，请输入 1、2 或 s。"
    done
  fi

  case "${choice,,}" in
    1|deepseek)
      run_deepseek_setup
      ;;
    2|opencode|opencode-go)
      run_opencode_go_setup
      ;;
    s|skip|none)
      info "skipping model setup"
      ;;
    *)
      err "invalid CODEX_MODEL_PROVIDER: $choice (expected deepseek | opencode | skip)"
      exit 1
      ;;
  esac
}

self_check() {
  info "self-check: verifying the bridge starts and exposes LSP tools"
  [[ -x "$VENV_DIR/bin/codex-lsp-bridge" ]] || { err "bridge binary missing at $VENV_DIR/bin/codex-lsp-bridge"; exit 1; }
  codex mcp list
  VENV_DIR="$VENV_DIR" "$VENV_DIR/bin/python" - "$BRIDGE_CONFIG" <<'PY'
import asyncio
import os
import sys
import tempfile

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

BRIDGE_CFG = sys.argv[1]
BRIDGE = os.path.join(os.environ["VENV_DIR"], "bin", "codex-lsp-bridge")

async def main() -> None:
    env = os.environ.copy()
    env["PATH"] = os.path.join(os.environ["VENV_DIR"], "bin") + os.pathsep + env.get("PATH", "")
    params = StdioServerParameters(
        command=BRIDGE,
        args=["serve", "--transport", "stdio", "--config", BRIDGE_CFG],
        env=env,
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await asyncio.wait_for(session.initialize(), timeout=30)
            tools = await asyncio.wait_for(session.list_tools(), timeout=30)
            names = sorted(t.name for t in tools.tools)
            print(f"  MCP handshake OK: {len(names)} tools exposed")
            print("  " + ", ".join(names))

            # Prove a language server actually starts: run document_symbols on a
            # throwaway Python file.
            fd, tmp = tempfile.mkstemp(suffix=".py", prefix="codex-lsp-check-")
            os.write(fd, b"def greet(name: str) -> str:\n    return 'hi ' + name\n")
            os.close(fd)
            try:
                res = await asyncio.wait_for(
                    session.call_tool("document_symbols", {"file_path": tmp}), timeout=45
                )
                text = res.content[0].text if res.content else "ok"
                print(f"  document_symbols on {os.path.basename(tmp)}: {text}")
                if res.isError or "Error calling tool" in text:
                    raise SystemExit(f"FAILED: language server did not start: {text}")
            finally:
                os.unlink(tmp)

asyncio.run(main())
PY
  info "self-check passed. Start a NEW Codex session to use the LSP tools."
}

remove_developer_instructions() {
  local backup="$CODEX_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CODEX_CONFIG" "$backup"
  info "removing managed developer_instructions block (backup: $backup)"
  python3 - "$CODEX_CONFIG" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()

# Drop the marker comment first, then the whole top-level block.
text = re.sub(r"^# MANAGED BY codex-setup[^\n]*\n(?=developer_instructions\s*=\s*\"\"\")", "", text, flags=re.M)
text, n = re.subn(r'^developer_instructions\s*=\s*"""\n.*?^\s*"""\s*\n', "", text, flags=re.M | re.S)

if n and "Codex LSP Bridge" in text:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"  removed {n} developer_instructions block(s)")
else:
    print("  no managed developer_instructions block found — leaving config untouched")
PY
}

uninstall() {
  if command -v codex >/dev/null 2>&1; then
    info "removing '$MCP_NAME' MCP server"
    codex mcp remove "$MCP_NAME" || true
  fi
  if [[ -d "$VENV_DIR" ]]; then
    info "removing venv $VENV_DIR"
    rm -rf "$VENV_DIR"
  fi
  if [[ -f "$CODEX_CONFIG" ]]; then
    remove_developer_instructions
  fi
  info "done. The project itself (~/codex-setup) was kept; delete it manually if no longer needed."
}

SKIP_MODEL_SETUP=0

install() {
  check_prereqs
  if [[ "$SKIP_MODEL_SETUP" -eq 0 ]]; then
    choose_model_provider
  else
    info "skipping model setup (--skip-deepseek)"
  fi
  install_venv
  install_mcp_entry
  install_developer_instructions
  self_check
}

case "${1:-install}" in
  --help|-h)
    usage
    ;;
  --check)
    check_prereqs
    self_check
    ;;
  --uninstall)
    uninstall
    ;;
  --skip-deepseek|--skip-model)
    SKIP_MODEL_SETUP=1
    install
    ;;
  install|"")
    install
    ;;
  *)
    err "unknown option: $1"
    usage
    exit 1
    ;;
esac
