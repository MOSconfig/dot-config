# Claude Code

[English](Claude-Code.md) | 简体中文

在本设置中，Claude Code 使用本机 copilot-relay 服务。

```mermaid
flowchart LR
    C[Claude Code] --> R[127.0.0.1:4142]
    R --> G[GitHub Copilot]
```

源文件在 `config/claude/`。它们安装到 `~/.claude/`。

## 一次设置

```sh
./install.sh
npx copilot-relay auth
./install.sh
```

Claude Code 第一次启动时会问是否允许自定义 `dummy` API key。请选择允许。这个值只是 Claude Code 需要的占位符。真实 GitHub 登录由 copilot-relay 保存。

## 模型路由

受管默认值：

```text
Claude 端名称： claude-opus-5-5[1m]
Picker 别名：   opus[1m]
Opus 保存偏好： xhigh
启动器 effort： xhigh
Relay 路由：    opusModel
上游模型：      claude-opus-5.5
```

Claude Code 保留原生 Opus 5.5 身份。名称包含 `opus`，所以 copilot-relay 会把它发送到 `opusModel`。客户端拼写使用连字符，Copilot 上游 ID 使用小数点，两者不要混用。

其他路由：

| Claude 端名称 | Relay lane | 上游 |
|---|---|---|
| `gpt-6.2-astra[1m]`（Sonnet、Haiku、small-fast、GPT 选择器行） | `gptModel` | `gpt-6.2-astra` |

Opus 保留原生 Anthropic ID。其他槽位直接调用 `gpt-6.2-astra[1m]`，客户端名称已与上游模型一致，不再需要重映射。`/model` 选择器显示易读的标签。Relay 仍会把任何非 Opus 名称发送到 `gptModel`。

`[1m]` 后缀让 Claude Code 使用一百万 token 的 context 计数；relay 向上游发送不带该后缀的规范 ID `claude-opus-5.5`。Haiku 和 small-fast 也使用 `gpt-6.2-astra[1m]`。Context 计数不保证保留完整的 1M-token 对话历史；自动压缩还取决于模型和输出预算。Claude 保存的 Opus 偏好、启动器和状态栏 effort 回退值使用 `xhigh`；保存的 Sonnet 偏好使用 `high`。`config/copilot-relay/config.yaml` 中的 relay 回退值为 `xhigh`。

Claude Code 2.1.281 能识别原生 Opus 5.5 身份。修改模型和 effort 默认值时应同时更新 `config/claude/settings.json`、`config/zsh/claude.zsh` 和 `config/zsh/cc.zsh`；wrapper 的 `--model` 和 `--effort` flags 优先于保存的设置。Relay 的 `thinkEffort`（`xhigh`）是未指定 effort 的请求的独立回退值。独立的 `gptModel` 仍为 `gpt-6.2-astra`，空白的 `webSearchBackend` 仍使用 Astra。

切换模型前，运行 `copilot` 并输入 `/model`，检查账号可用性和 effort 选项。这是 Copilot 的选择器，不是 Claude Code 的选择器，也不是 relay 本地的 `/v1/models`。`scripts/check.sh all` 通过后，运行两次 `./install.sh` 应用配置，再启动新的 shell 和 Claude Code 会话。安装器会保留健康的 relay 进程；恢复不健康的 relay 时可能中断请求。

只修改 `opusModel` 不会让启动时选用 Opus。现在 `ANTHROPIC_MODEL`、保存的 `opus[1m]` 选择、`ANTHROPIC_DEFAULT_OPUS_MODEL` 和两个启动器都指向原生 Opus 5.5。Sonnet、Haiku 和 small-fast 直接调用 GPT-6.2 Astra；不要把 Opus 指向 GPT。Relay 路由和 effort 修改会热重载，无需重启。

[上游 Opus 5.5 验证](https://github.com/D0n9X1n/copilot-relay/issues/81)确认自动工具调用可用，但强制指定 `tool_choice` 为 `tool` 或 `any` 会返回 HTTP 400。Relay 保留该错误，不会静默改成自动选择。

## 主要设置

`config/claude/settings.json` 设置：

| Key | 值或作用 |
|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4142` |
| `ANTHROPIC_AUTH_TOKEN` | 本机占位符 `dummy` |
| `ANTHROPIC_MODEL` | `claude-opus-5-5[1m]` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `claude-opus-5-5[1m]`；解析原生 Opus 别名 |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `gpt-6.2-astra[1m]` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `gpt-6.2-astra[1m]` |
| `ANTHROPIC_SMALL_FAST_MODEL` | `gpt-6.2-astra[1m]` |
| `model` | `opus[1m]`；选择器的原生别名 |
| `modelPicker` | 只有 `Opus 5.5 (1M context)` 和 `GPT-6.2 Astra (1M context)`；替换内置列表 |
| `modelSettings.claude-opus-5-5.effortLevel` | `xhigh`；Opus 5.5 保存的 effort 偏好 |
| `modelSettings.claude-sonnet-5.effortLevel` | `high`；Sonnet 5 保存的 effort 偏好 |
| `MODEL_REASONING_EFFORT` | `xhigh`；状态栏回退值与启动器的 `--effort xhigh` 保持一致 |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `16` |
| `statusLine.refreshInterval` | `2`；单位为秒，使 mermaid-tty 的 `/btw` 项在回答期间显示。脚本约需 30 毫秒 |
| `theme` | `custom:apollo`；生成的主题资源仍保留在本机 |
| `CLAUDE_CODE_TMUX_TRUECOLOR` | `"1"`；跳过 Claude 的 tmux 256 色限制 |
| `autoCompactEnabled` | `true` |
| `autoCompactWindow` | `770000`；保留的配置窗口，不是实测触发阈值 |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"100"`；保留的百分比覆盖值 |
| `feedbackDrafts` | `off` |
| `enableWorkflows` | `true`；启用多 agent Workflow 脚本 |
| `outputStyle` | `Concise`；简短回复，先给结果 |
| `tui` | `fullscreen`；全屏终端界面 |
| `crossSessionInbound` | `accept`；无需确认即可接收本机其他 Claude 会话的消息 |
| `cleanupPeriodDays` | `7`；会话记录闲置 7 天后删除，节省磁盘空间（默认 30） |
| `MERMAID_TTY_BTW_STATUS` | `"file"`；mermaid-tty 为状态栏的 btw 项标记正在回答的 `/btw`，而不是显示自己的状态行 |
| `CLAUDE_CODE_AUTO_MODE_SERVER` | `"0"`；auto 模式使用 Claude Code 自己发出的 classifier 请求，而不是服务端审查。权限检查仍然开启 |

`refreshInterval` 必须放在 `statusLine` 里面。保存的 Opus 偏好使用 `xhigh`；保存的 Sonnet 偏好使用 `high`。`MODEL_REASONING_EFFORT` 是状态栏回退值，不控制 API effort。启动器传入 `--effort xhigh`；`claude` 命令上显式指定的 effort 会覆盖它。不管理顶层 `effortLevel`。[Copilot CLI](Copilot-CLI-zh-CN.md) 保留独立的 Astra/`xhigh` 默认值。

### 模型选择器

`/model` 提供两个最终选择：

| 行 | 模型 | 说明 |
|---|---|---|
| Opus 5.5 (1M context) | `opus[1m]` | Most capable for ambitious work |
| GPT-6.2 Astra (1M context) | `gpt-6.2-astra[1m]` | GPT-6.2 Astra through copilot-relay |

`modelPicker.replaceBuiltInOptions` 隐藏内置行，包括 Haiku 和 `opusplan`。Claude Code 总会加上 **Default** 行；它解析为 Opus 5.5，不能隐藏。GPT 行设置 `behavesAs: claude-sonnet-5`，所以 Claude Code 在 effort 和 1M context 上把它当作 Sonnet 5。

这只改变选择器，不是硬性禁止。没有设置 `availableModels`。`modelPicker` 需要 Claude Code 2.1.242 或更高版本；`behavesAs` 需要 2.1.257 或更高版本。

在 sandbox 中运行的 Claude Code 2.1.286 检查显示正好三行。对本机 mock，默认请求发送 `claude-opus-5-5`。`--model sonnet`、`--model haiku` 和 GPT 行都发送 `gpt-6-astra`，带 `high` effort、adaptive thinking 和 1M context beta。通过 relay 的小型真实请求在每条路径上都返回 `ok`。

独立的 Claude Code 2.1.281 检查（在默认值为 `xhigh` 时运行）验证了仅使用设置、picker 别名和 wrapper 启动时，请求均发送 `model: claude-opus-5-5`、所配置的 `output_config.effort` 和 1M context beta。默认值后来改为 `high`，现已恢复为 `xhigh`。显式指定 Sonnet/`low` 仍优先。检查使用回环 mock、临时 home 和 macOS sandbox，阻止外部网络及真实 home/keychain 访问；没有付费模型调用，也不是上游容量测试。

### 自动压缩

配置窗口不等于压缩触发阈值。`autoCompactWindow: 770000` 和 `100` 百分比覆盖值保持不变。之前的 750,000-token 计算使用 Claude Code 2.1.261 的 Sonnet 输出预留量，不是已验证的 Opus 5.5 阈值。当前离线 Opus 请求允许 128,000 输出 tokens，但单凭请求上限不能确定压缩预留量或触发点。

CLI 版本、模型、输出预算和环境覆盖都可能改变压缩时机；某一轮可能先越过触发点再开始压缩。不要把这些设置当作对话大小硬上限或历史保留保证。编辑源设置后请启动新的 Claude Code 会话。

`~/.claude/settings.json` 和 `~/.claude.json` 是不同文件：

- `settings.json` 是链接的配置，包括 `custom:apollo` 主题偏好。
- `~/.claude.json` 是本机状态。它保存 onboarding、API key 允许项、安装器同步选择的 Apollo 主题、项目数据和导入的 MCP servers。

`install.sh` 会从已验证的规范 Apollo release 生成 `~/.claude/themes/apollo.json`，并在选择 `custom:apollo` 时保留所有无关字段。生成主题是本机状态，不是 Git 源文件。

不要把本机状态文件放进 Git。

## 全局指令

`config/claude/CLAUDE.md` 安装为 `~/.claude/CLAUDE.md`，并设置用户级回复风格。对话文字默认直接、简短。明确要求更多细节时仍按要求回答；代码、命令、检查结果、证据、必要说明、安全信息和技术准确性必须保持完整。

全局文件只保留可复用行为，加一条条件指针：这些设置从 `~/Public/dot-configs` 同步；要修改它们，先读该目录的 `.claude/CLAUDE.md`。仓库专属规则——Wiki 是完整信息源、manifest、检查、双语页面——留在本仓库自己的 `.claude/CLAUDE.md`，这样无关项目不会加载它们。

目标或任务结束时，即使没有 PR，全局规则也要求清理本次工作创建的所有构建文件和临时文件，包括 repo 外的文件，并停止不再需要的任务专属后台进程。保留受跟踪文件、用户文件、共享缓存和归属不明的内容；agent 需要说明删除和保留了什么。

PR 合并后，全局规则要求先完成本机清理，再宣布任务完成：确认合并，移除该 PR 干净且闲置的 worktree 和本地分支，清理失效引用，移除任务创建的临时文件，并停止不再需要的任务专属进程。保留未提交或未合并的工作、stash、活跃会话和锁、无关文件及共享进程。检查最终状态，并说明保留项。这是 agent 指令，不是无人值守的合并 hook。

## 启动器

`config/zsh/claude.zsh` 包装 `claude` 并添加：

```text
--permission-mode bypassPermissions
--model claude-opus-5-5[1m]
--effort xhigh
```

命令行上显式给出 `--model`、`--model=`、`--effort` 或 `--effort=` 时，对应的默认值不再注入；另一个默认值仍然生效。

安装后打开新 shell，或在空闲 shell 提示符中重新加载两个启动器，再启动新的 Claude 会话：

```zsh
source ~/.oh-my-zsh/custom/claude.zsh
source ~/.oh-my-zsh/custom/cc.zsh
```

二进制会拒绝 settings 中的 `permissions.defaultMode: bypassPermissions`。命令行 flag 可以工作。Claude Code 可能在运行时重写 settings，所以 wrapper 也固定模型和 effort。

`settings.json` 是符号链接，因此 CLI 持久化的偏好可能表现为源文件改动。提交前检查 `git diff -- config/claude/settings.json`，只按上面的受支持设置核对变动的键，再运行 `scripts/check.sh all`。不要整份恢复文件，以免丢失其他有意保留的修改。

`cc [标题]` 会设置 SonicTerm 标题，并用相同默认值启动 Claude Code。它先检查 RMUX 并直接重命名其窗口。在原生 tmux 中，通过 `tmux-store` 重命名当前 socket 的当前窗口，不添加 `PATH` shim，也不替换真正的全局 `tmux` 可执行文件。请看 [Tmux](Tmux-zh-CN.md)。

只有当 Claude Code 需要创建 agent-team 窗格时才使用 `rmux claude`。RMUX 会给这个进程一个私有 tmux 兼容 shim。不会安装全局 tmux shim。

## Agent 限制

需要 Claude Code v2.1.217 或更高版本。

原生 admission 值是 16。它不是全局硬上限：

- 用户启动的 `/subtask` 会占一个 slot，但不被同一个边界拦截；
- 恢复的 agent 可以超过设置数量；
- ultracode 不受此限制；
- workflow agents 和 team workers 使用其他限制。

不要恢复旧生命周期计数 hook。

## 状态栏

Claude 与 Copilot 状态栏共享两行设计、本机生成的 Apollo 颜色和每目录五秒 Git cache。最上面是一行留白，然后是：

1. 模型、effort、WakaTime、venv，最后是 context（十格进度条、百分比和容量，例如 `45% of 1.0M`）
2. 先是 branch 及其标记（✓ 干净或 ● 有修改、领先/落后，有 stash 时显示 stash 图标和数量），然后是 btw（mermaid-tty 在本会话中回答 `/btw` 期间显示 `answering Ns`），然后是 Diff（本会话绿色的 `+新增` 和红色的 `-删除`，只显示非零部分，两者都为 0 时隐藏），文件夹路径在行的最右端

每一项都是带强调色的 Nerd Font 图标、弱化的标签和值；项之间用细竖线分隔，没有数据的项会隐藏。已知 `COLUMNS` 时，路径右对齐，并从左侧缩短（`…/`）以适应宽度；否则路径跟在其他项后面。`CLAUDE_STATUSLINE_PAD_TOP` 设置留白行数（默认 1）。

WakaTime 的数值缓存五分钟；无论成功与否，五分钟内最多尝试获取一次，因此两秒的刷新间隔不会在每次渲染时都启动一个失败的 `wakatime-cli`。两个脚本读取同一个本机生成 Apollo 颜色 include。文件缺失或禁用颜色时，它们仍会输出可读的无色内容。Claude 自定义状态栏没有 live-subagent 数量或树，因为 Claude Code 已有原生 subagent UI。Copilot 保留自定义 rows。

btw 项读取 mermaid-tty 的标记 `~/.cache/mermaid-tty/btw-<session_id>`，按状态栏输入中顶层的 `session_id`（小写 UUID）区分会话；含其他字符的 id 没有标记，因此不区分大小写的磁盘也不会让两个会话共用一个文件。只读取这一个标记，因此无论过去的会话留下多少空标记，渲染开销都不变。当输入只出现一次 `session_id` 且没有转义时，直接从文本读取 id；否则先由 `jq` 解析出顶层 id，因此键的顺序不会决定读取哪个标记。一旦该标记表明正在回答 `/btw`，`jq` 还会确认这个 id 是顶层的那一个。标记内容恰好为 `1`（结尾换行除外）且在 300 秒内修改过时显示，并显示从那时起的秒数，否则隐藏。因此，会话崩溃后留下的标记最多五分钟后就不再显示。由于受管理的 `env` 设置了 `MERMAID_TTY_BTW_STATUS=file`，mermaid-tty 会写这个标记，而不是在提示符下方显示自己的状态行。`/btw` 不会产生回复，也就不会让状态栏重新运行，因此 `refreshInterval` 为 2 秒。Copilot 状态栏为保持共同布局也有同样的项，但 mermaid-tty 只在 Claude Code 中运行，所以在那里始终隐藏。

## Plugins

受管设置启用：

- `frontend-design@claude-plugins-official`
- `rust-analyzer-lsp@claude-plugins-official`
- `clangd-lsp@claude-plugins-official`
- `swift-lsp@claude-plugins-official`
- `claude-code-wakatime@wakatime`
- `feature-crew@feature-crew`
- `mermaid-tty@mermaid-tty`
- `mux-agents@mux-agents`

WakaTime marketplace 指向官方 `wakatime/claude-code-wakatime` Git 仓库。Feature-Crew marketplace 指向 GitHub 仓库 `D0n9X1n/feature-crew`；`install.sh` 也会在 PATH 上的每个 CLI 中安装或更新这个 plugin。`~/.claude` 中旧的 Feature-Crew 脚本安装会遮挡 plugin。Claude Code 列出该 plugin 已启用后，`install.sh` 会删除 `~/.claude/agents/` 中旧的 `fc-*` agent、`~/.claude/skills/` 中旧的 `fc-*` skill，以及 `~/.claude/feature-crew.sha256`。它只删除这些确切名称，并跳过链接形式的 `agents` 或 `skills` 文件夹。很早版本留下的非 `fc-` 文件不会被删除；对这些文件，请在 Feature-Crew 克隆中运行 `./install.sh`。

mermaid-tty marketplace 指向 GitHub 仓库 `D0n9X1n/mermaid-tty`。这个 plugin 会把 Claude 回复中已闭合的 `mermaid` 代码块重绘为彩色的制表符图表；凡是无法精确绘制的内容，都显示源码。`install.sh` 会在 Claude Code 中安装或更新它。除非已设置主题，它会保存默认主题（跟随 Claude Code 主题），因此 Claude Code 不会提示该选项未设置；`/mermaid-tty source` 可把图表显示为源码。

mux-agents marketplace 指向 GitHub 仓库 `D0n9X1n/mux-agents`。这个 plugin 会在 tmux 或 RMUX pane 中启动 Claude Code 和 Copilot CLI 辅助 agent，在侧边栏显示每个 agent 正在做什么，并通过邮箱文件传递消息。要使用它，请在 tmux 3.2+ 或 RMUX 0.10+ 中启动 Claude。`install.sh` 会像 Feature-Crew 一样，在 PATH 上的每个 CLI 中安装或更新它。

每次运行 `install.sh`（因此也包括每次 `uu`）都会刷新所有 Claude Code marketplace，并更新每个已启用的 user plugin，包括官方 LSP 和 WakaTime plugin。Project 和 local plugin 交给各自的仓库管理。Plugin 更新在 Claude Code 重启后生效。

## 常见问题

### RMUX 内的颜色不同

Claude Code 2.1.278 在存在 `TMUX` 时会把输出限制为 256 色，即使已设置 `COLORTERM=truecolor` 和 `FORCE_COLOR=3`。RMUX 为兼容性导出 `TMUX`，但支持真彩色。受管的 `env.CLAUDE_CODE_TMUX_TRUECOLOR: "1"` 跳过这个客户端限制，不改动 Apollo 配色。原生 SonicTerm 没有 `TMUX` 时，也没有这个限制需要绕过。

应用设置后请启动新的 Claude Code 进程；已有进程已完成颜色初始化。可以用 `claude --continue` 恢复对话。不要重启 RMUX 服务器：它已经支持真彩色，重启会停止窗格内的应用。重载或重新连接 RMUX 不会重新初始化运行中 Claude 进程的颜色。保留 `TERM=tmux-256color`、`TERM_PROGRAM=rmux` 和 `rmux claude` 私有 teammate shim，不需要修改它们。

### Claude 每次都显示 onboarding

本机 `~/.claude.json` 缺少 `hasCompletedOnboarding`。在这台 Mac 上完成一次 onboarding。

### `dummy` key 被拒绝

第一次提示选择了拒绝。在本机 `~/.claude.json` 中，把 `dummy` 从 `customApiKeyResponses.rejected` 移到 `approved`，或重新完成允许流程。

### 小任务出现 `model_not_supported`

保持 Haiku 和 small-fast aliases 都是 `gpt-6.2-astra[1m]`，与 GPT 选择器行相同。检查 `gptModel` 仍是 `gpt-6.2-astra`，并确认 relay base URL 正确。

### Relay 重写 settings

`config/copilot-relay/config.yaml` 中的 `claudeSetup` 必须是 `false`。重新运行 `./install.sh`。

### Relay token 过期

```sh
npx copilot-relay auth
./install.sh
```

Deep relay 检查退出码为 2 时，一般需要重新登录，不是重启。

## 检查

```sh
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
curl -fsS http://127.0.0.1:4142/healthz
scripts/check.sh instructions
scripts/check.sh all
```

launchd 和健康检查请看[服务与自动化](Services-and-Automation-zh-CN.md)。
