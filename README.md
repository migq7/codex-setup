# codex-setup

用 git 维护的 Codex 本机环境配置项目。当前包含 **C++/Python LSP 桥**（clangd + basedpyright）和一段全局 `developer_instructions`，设计目标是：新机器上 clone 下来跑一条命令，Codex 就能拥有语言服务器级别的语义能力；后续可以继续往这个项目里加其他 MCP server 或 `config.toml` 配置。

## 为什么需要这个项目

Codex CLI 本身没有内置 LSP 配置（官方手册和 CLI 均无此项）。本方案通过社区开源组件 [codex-lsp-bridge](https://github.com/CesarPetrescu/lsp-mcp)（MIT，非 OpenAI 官方项目）把语言服务器的语义能力以 **MCP 工具**的形式暴露给 Codex，包括：跳转定义、找引用、语义重命名、悬停、签名、文档/工作区符号、诊断、代码操作、格式化等。

## 目录结构

```text
codex-setup/
├── README.md
├── setup.sh                      # 一键安装 / 自检 / 卸载（幂等）
├── .gitignore
└── config/
    └── lsp-mcp-config.toml       # 语言服务器映射（Python → basedpyright，C/C++/CUDA → clangd）
```

安装产生的 venv 在 `~/.codex/lsp-mcp-venv`，**不进仓库**，脚本会自动重建。仓库里只保留可版本化的配置与脚本。

## 依赖

- `codex` CLI（已安装）
- `python3` >= 3.10（创建独立 venv 用）
- `git`（从 GitHub 安装桥组件用）
- `clangd`：C/C++/CUDA 需要；Debian/Ubuntu 可 `sudo apt install clangd`（或对应发行版的 llvm 包）。Python 部分不依赖它。

## 快速开始（新机器）

```bash
# 1. 安装 clangd（C++ 需要；Python 可跳过）
sudo apt install clangd

# 2. clone 本项目并执行
git clone <your-repo-url> ~/codex-setup
cd ~/codex-setup
./setup.sh

# 3. 重开一个 Codex 会话，LSP 工具即生效
```

脚本是幂等的：重复执行只会补齐缺失的部分，不会覆盖你 `~/.codex/config.toml` 里已有的其他配置。

## 命令

| 命令 | 作用 |
| --- | --- |
| `./setup.sh` | 安装（幂等）并自检 |
| `./setup.sh --check` | 只做自检（MCP 握手 + 工具列表 + 真实调用一次语言服务器） |
| `./setup.sh --uninstall` | 移除 MCP 条目、删除 venv、移除托管注入的 `developer_instructions`（操作前备份 config.toml） |
| `./setup.sh --help` | 帮助 |

## 配置管理

### 语言服务器（`config/lsp-mcp-config.toml`）

按扩展名把文件路由到对应的语言服务器命令。当前：

- Python：`basedpyright-langserver`（类型检查、语义跳转）
- C/C++/CUDA：`clangd`（`.c/.cc/.cpp/.cxx/.cu/.cuh/.h/.hpp/.hxx`）

改完这个文件后重跑 `./setup.sh` 即可（脚本会用 `codex mcp add` 刷新 MCP 条目的参数）。命令名按 PATH 解析，脚本注入 MCP 时会自动把 venv 的 `bin/` 加进 PATH。

### developer_instructions（全局提示词）

由 `setup.sh` 自动注入到 `~/.codex/config.toml`，带 `# MANAGED BY codex-setup` 标记，内容是：优先用 LSP 工具做语义导航/重构而不是文本搜索。若你自己已配置了 `developer_instructions`，脚本会跳过不动。想改内容就改 `setup.sh` 里的模板再卸载重装，或直接改 config.toml。

### 添加其他 MCP server

```bash
# HTTP/流式
codex mcp add <name> --url <url>

# 本地命令
codex mcp add <name> --env "KEY=value" -- /path/to/server args...
```

需要纳入一键迁移的话，把命令写进 README，或按 `setup.sh` 的模式加一段 install 逻辑。

## 验证与使用

```bash
codex mcp list          # 应看到 lsp_bridge: enabled
./setup.sh --check      # 完整自检
```

然后在新的 Codex 会话里直接说，例如：

> 用 LSP 找到 `UserRepository` 的所有引用，然后重命名为 `AccountRepository`。

模型会根据注入的 developer_instructions 优先调用 `find_references` / `rename_symbol` 等工具。

## 注意事项

- C++ 的跳转精度依赖项目的 `compile_commands.json`（CMake 加 `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` 生成，或 symlink 到项目根目录）。没有时 clangd 用 fallback 参数，跳转可能为空。
- MCP server 按会话加载，改完配置要**重开 Codex 会话**。
- basedpyright 只做类型检查，不支持格式化（`textDocument/formatting` 未实现），这是它的限制而非配置问题；需要 lint/autofix 可再加 ruff-lsp。
- 桥组件是第三方社区项目，代码只在本机拉起语言服务器子进程、无外部网络行为，但请知悉其非官方属性；要升级时改 `setup.sh` 里的 `BRIDGE_PIN` / `BASEDPYRIGHT_VERSION`。

## 排障

```bash
codex mcp list                 # 条目是否启用
codex mcp get lsp_bridge       # 查看实际 command/args/env
codex doctor                   # Codex 安装/配置健康检查
```

桥进程本身的日志会出现在 Codex 会话的 MCP 面板里；也可以在终端手动跑 `~/.codex/lsp-mcp-venv/bin/codex-lsp-bridge serve --transport stdio --config ~/codex-setup/config/lsp-mcp-config.toml` 观察启动报错。
