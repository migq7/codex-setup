# codex-setup

用 git 维护的 Codex 本机环境配置项目。`./setup.sh install` 的执行顺序是：**先选择模型提供方**（DeepSeek 官方 API 或 OpenCode Go，也可跳过），把 Codex 默认模型切到对应服务，**再装 C++/Python LSP 桥**（clangd + basedpyright）并注入全局 `developer_instructions`。设计目标是：新机器上 clone 下来跑一条命令，Codex 就同时拥有可用的第三方模型和语言服务器级别的语义能力；后续可以继续往这个项目里加其他 MCP server 或 `config.toml` 配置。

## 为什么需要这个项目

Codex CLI 本身没有内置 LSP 配置（官方手册和 CLI 均无此项）。本方案通过社区开源组件 [codex-lsp-bridge](https://github.com/CesarPetrescu/lsp-mcp)（MIT，非 OpenAI 官方项目）把语言服务器的语义能力以 **MCP 工具**的形式暴露给 Codex，包括：跳转定义、找引用、语义重命名、悬停、签名、文档/工作区符号、诊断、代码操作、格式化等。

## 目录结构

```text
codex-setup/
├── README.md
├── setup.sh                      # 一键安装 / 自检 / 卸载（幂等）
├── .gitignore
├── scripts/
│   ├── codex-deepseek-setup.sh   # DeepSeek 官方配置器（v1.0.0，固定版本，原样复制）
│   ├── codex-opencode-go-setup.sh # OpenCode Go 配置器（由 opencode-go-build 生成）
│   └── opencode-go-build/        # OpenCode Go 脚本的模板与构建器（改模型清单后重新生成）
└── config/
    └── lsp-mcp-config.toml       # 语言服务器映射（Python → basedpyright，C/C++/CUDA → clangd）
```

安装产生的 venv 在 `~/.codex/lsp-mcp-venv`，**不进仓库**，脚本会自动重建。仓库里只保留可版本化的配置与脚本。

## 执行流程

`./setup.sh install` 固定按以下顺序执行，**模型提供方选择永远在第一步**（`--skip-deepseek` 或在菜单里选 s 可跳过）：

1. **模型提供方选择**：交互选择 DeepSeek / OpenCode Go / 跳过，再运行对应的配置器
   - DeepSeek：`scripts/codex-deepseek-setup.sh`（菜单 1/2 切换模型，3 还原）
   - OpenCode Go：`scripts/codex-opencode-go-setup.sh`（菜单 1..N 切换模型，r 还原）
2. **LSP 桥 venv**：把 codex-lsp-bridge + basedpyright 装进 `~/.codex/lsp-mcp-venv`
3. **MCP 注册**：`codex mcp add` 写入 `[mcp_servers.lsp_bridge]`
4. **注入 `developer_instructions`**：写入全局提示词（已存在则跳过）
5. **自检**：MCP 握手 + 真实调用一次语言服务器

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

# 3. ./setup.sh 的第一步弹出模型提供方菜单：选 1 配置 DeepSeek，选 2 配置 OpenCode Go
#    （DeepSeek 首次会要 API key，可先 export DEEPSEEK_API_KEY=sk-xxx；
#     OpenCode Go 可先 export OPENCODE_GO_API_KEY=sk-xxx；
#     都不需要则用 ./setup.sh --skip-deepseek 跳过）

# 4. 重开一个 Codex 会话，LSP 工具与所选模型即生效
```

脚本是幂等的：重复执行只会补齐缺失的部分，不会覆盖你 `~/.codex/config.toml` 里已有的其他配置。两个模型配置器自身也都有备份机制，已安装过时会走“仅切换模型”的快路径。

## 命令

| 命令 | 作用 |
| --- | --- |
| `./setup.sh` | 安装（幂等）并自检；先弹出模型提供方菜单（DeepSeek / OpenCode Go / 跳过），再装 LSP 桥 |
| `CODEX_MODEL_PROVIDER=opencode ./setup.sh` | 跳过菜单直接配置 OpenCode Go（取值 `deepseek` / `opencode` / `skip`） |
| `./setup.sh --skip-deepseek` | 安装但跳过模型提供方配置，只装 LSP 桥 |
| `./setup.sh --check` | 只做自检（MCP 握手 + 工具列表 + 真实调用一次语言服务器） |
| `./setup.sh --uninstall` | 移除 MCP 条目、删除 venv、移除托管注入的 `developer_instructions`（操作前备份 config.toml；**不还原**模型配置，需要还原请运行对应配置器：DeepSeek 选 3，OpenCode Go 选 r） |
| `./setup.sh --help` | 帮助 |

## 配置管理

下面按 `./setup.sh install` 的执行顺序介绍各块配置。

### 1. 模型提供方配置（DeepSeek / OpenCode Go）

安装流程的第一步是交互选择提供方，然后执行仓库内对应的配置器。两者都会做“手术式”改写：只改与目标 provider 冲突的顶层 key，其余配置（`[mcp_servers.*]`、`[projects.*]`、`developer_instructions` 等）原样保留。

#### DeepSeek（`scripts/codex-deepseek-setup.sh`）

仓库内固定版本（v1.0.0，原样复制）的 DeepSeek 官方配置器，把 Codex 默认模型切换为 DeepSeek。它自己的行为如下：

- 交互菜单：选 1 = `deepseek-v4-flash`，选 2 = `deepseek-v4-pro`（当前版本脚本尚未启用，选 2 会提示后退出），选 3 = 还原默认配置（删除 models.json、恢复安装前备份）。
- API key：优先用环境变量 `DEEPSEEK_API_KEY`（必须以 `sk-` 开头），否则交互输入；key 会写入 `~/.codex/config.toml` 的 `[model_providers.deepseek] experimental_bearer_token`（注意：这是明文存在本机配置里）。
- 备份在 `~/.codex/backup-deepseek/`；已安装过时再选 1/2 只改 `config.toml` 的 `model` 字段，不触碰其他配置（包括本项目注入的 `[mcp_servers.lsp_bridge]` 和 `developer_instructions`）。
- 首次安装会对 `config.toml` 做“手术”：改写/删除与 DeepSeek 冲突的顶层 key（如 `profile`、`model_context_window` 等），其余 key 与未知 section（如 `[mcp_servers.*]`、`[projects.*]`）原样保留；`model`、`model_provider` 等顶层 key 始终写在文件最前面。
- 自定义来源：可用 `DEEPSEEK_SETUP_SCRIPT=/path/to/newer/script ./setup.sh` 指向仓库外的更新版本；仓库内副本是固定版本，想升级就把新文件复制到 `scripts/codex-deepseek-setup.sh` 并 `cmp` 校验后提交。
- 卸载：`./setup.sh --uninstall` 不会还原模型配置；想恢复默认 Codex 配置，运行 `bash scripts/codex-deepseek-setup.sh` 后选 3（会删除 models.json 并恢复备份）。

#### OpenCode Go（`scripts/codex-opencode-go-setup.sh`）

由本仓库 `scripts/opencode-go-build/` 生成的配置器，把 Codex 默认模型切换到 OpenCode Go 订阅服务。行为：

- 交互菜单：选 1..N 切换模型（默认 `deepseek-v4-flash`，推荐；另有 pro / luna / kimi / glm / grok / hy3 / mimo 等），`c` 输入自定义模型 ID，`r` 还原默认配置。
- API key：优先用环境变量 `OPENCODE_GO_API_KEY`（必须以 `sk-` 开头），否则交互输入；key 会写入 `~/.codex/config.toml` 的 `[model_providers.opencode-go] experimental_bearer_token`（明文，脚本会 chmod 600）。
- 端点固定为 `https://opencode.ai/zen/go/v1`，`wire_api = "responses"`（Codex 目前只支持 Responses 协议；因此仅走 Anthropic `/v1/messages` 的 MiniMax M 系列与部分 Qwen 模型无法用于 Codex）。
- 备份在 `~/.codex/backup-opencode-go/`，包含安装前的 `config.toml` 与 `models.json`；已安装过时再运行只改 `config.toml` 的 `model` 字段。
- 会生成 `~/.codex/models.json` 模型目录（含上下文窗口、推理档位、系统提示词等元数据）；OpenCode Go 模型清单有变化时，编辑 `scripts/opencode-go-build/` 里的模板并重新运行构建器。
- 已知情况：`deepseek-v4-flash` 的 Responses 支持最稳；`deepseek-v4-pro` 目前多轮/工具调用可能 400（opencode 官方 issue 跟踪中）；`gpt-5.6-luna` 原生支持 Responses 但流式输出可能整体缓冲。安装末尾可主动发一个最小测试请求验证所选模型。
- 自定义来源：可用 `OPENCODE_GO_SETUP_SCRIPT=/path/to/script ./setup.sh` 指向其他位置；不想交互选择可用 `CODEX_MODEL_PROVIDER=opencode ./setup.sh` 直接配置。

如果不想在 install 时看到菜单（比如自动化环境），用 `./setup.sh --skip-deepseek` 或 `CODEX_MODEL_PROVIDER=skip` 跳过，模型配置不受影响。

### 2. 语言服务器（`config/lsp-mcp-config.toml`）

按扩展名把文件路由到对应的语言服务器命令。当前：

- Python：`basedpyright-langserver`（类型检查、语义跳转）
- C/C++/CUDA：`clangd`（`.c/.cc/.cpp/.cxx/.cu/.cuh/.h/.hpp/.hxx`）

改完这个文件后重跑 `./setup.sh` 即可（脚本会用 `codex mcp add` 刷新 MCP 条目的参数）。命令名按 PATH 解析，脚本注入 MCP 时会自动把 venv 的 `bin/` 加进 PATH。

### 3. developer_instructions（全局提示词）

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
