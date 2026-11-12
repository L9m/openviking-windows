# openviking-windows

[OpenViking](https://github.com/volcengine/OpenViking) 记忆插件的 **非官方 Windows 安装器**。
官方 `install.sh` 只支持 macOS / Linux（在 Windows 上直接报 `Only macOS and Linux are supported.`），
本脚本在安装时自动下载最新官方安装器并动态套用 Windows 适配补丁，让它在 Git Bash 下正确工作。

**Unofficial Windows installer for the OpenViking memory plugin.** Downloads the
official installer on each run and adapts it for Windows (Git Bash) at install
time. Not affiliated with the upstream project.

## 一行安装 / One-liner

**交互式（推荐，真人使用）**——不带参数，回车确认后进入向导，勾选 agent、输入服务器和 API key：

```bash
curl -fsSL https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.sh | bash -s --
```

标准通道（`raw.githubusercontent.com` 可达时等效）：

```bash
curl -fsSL https://raw.githubusercontent.com/L9m/openviking-windows/main/install-openviking-windows.sh | bash -s --
```

**非交互（脚本 / CI / 发给别人直接粘贴）**——显式指定目标，无需任何输入，结果可预测；也是无终端环境下唯一能运行的形式：

```bash
curl -fsSL https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.sh \
  | bash -s -- --yes --harness zcode
```

> jsDelivr 有 CDN 缓存，新推送的提交可能延迟几分钟到几小时才可见；引导脚本本身会在
> 运行时下载**最新**官方安装器，所以引导脚本略有滞后影响很小。必要时可在
> [jsdelivr.com/tools/purge](https://www.jsdelivr.com/tools/purge) 手动刷新缓存。

克隆方式（完全不依赖 raw / CDN）：

```bash
git clone https://github.com/L9m/openviking-windows.git
bash openviking-windows/install-openviking-windows.sh        # 交互向导
bash openviking-windows/install-openviking-windows.sh --yes --harness zcode   # 非交互
```

## 前置要求 / Requirements

- Windows 上的 **Git Bash**（MSYS2 / MINGW / Cygwin 终端均可）—— [git-scm.com](https://git-scm.com)
- **Node.js 18+**（Volta 管理的 node 也可，脚本会自动绕过其 shim 缺陷）
- `curl`、`unzip`（Git Bash 自带）；`npm` 仅在 `--harness cli` 时需要

## 没有 Git Bash？用 PowerShell 启动器

仓库里的 [install-openviking-windows.ps1](./install-openviking-windows.ps1) 是给没有
Git Bash 的机器准备的 PowerShell 薄启动器：定位 Git Bash（注册表 + PATH + 常见位置），
找不到时**先询问（y/N）再**用 winget 安装 Git for Windows（非交互环境绝不安装、
已安装不重装），然后获取 bash 引导脚本运行，参数原样转发。引擎仍是 bash 引导脚本。

```powershell
# 零文件一行式（注意 iex 无法携带参数，仅交互终端使用；非交互环境会被拒绝而非默认全装）：
iex (New-Object Net.WebClient).DownloadString('https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.ps1')

# 或下载后运行（可带参数）：
curl.exe -fsSL -o "$env:TEMP\ov.ps1" https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.ps1
powershell -ExecutionPolicy Bypass -File "$env:TEMP\ov.ps1"                # 交互向导
powershell -ExecutionPolicy Bypass -File "$env:TEMP\ov.ps1" --yes --harness zcode
```

说明：Windows 自带的 `System32\bash.exe` 是 WSL 的 bash，安装到 Linux 侧、配置不到
Windows 的 agent，启动器会明确跳过它。**交互向导对终端有要求**：官方向导依赖 ANSI
重绘和 `/dev/tty` 单键读取，在 Git Bash 窗口（mintty）和 Windows Terminal 下正常；在
传统 conhost（PowerShell/cmd 直开的窗口）里可能卡顿、回车无响应——启动器检测到交互
场景会自动用 Git 自带的 mintty 新开窗口运行向导；直接用 bash 时请优先在 Git Bash 窗口
里跑。

## 用法 / Usage

**交互模式（推荐）**：不带任何参数直接运行——先按一次**回车确认**（5 秒无响应自动中止，
防止 CI/脚本误装），然后进入官方安装器的交互向导——
选语言 → 复选框勾选要装的 agent（已探测到的预选，zcode / codex / cursor / trae /
kimicode / ... 全部可勾）→ **服务器配置也在此输入**（菜单选 本地 127.0.0.1:1933 /
火山云 / 自定义 URL，然后输入 API key——隐藏输入不回显，回车保留已存值、`-` 清空）→
安装计划确认。`curl | bash` 一行安装同样支持（向导从 `/dev/tty` 读输入，不受管道影响）。**注意**：未显式给出
`--harness` / `--yes` 且无交互终端时（CI、被其他脚本调用），脚本会直接拒绝运行而不是按默认装全部——
请显式指定目标。

```bash
bash install-openviking-windows.sh
```

非交互模式（脚本 / CI 用，加 `--yes` 跳过全部提问）：

```bash
# 安装到自动探测到的 agent（或用 --harness 指定，逗号分隔）
bash install-openviking-windows.sh --yes --harness zcode
bash install-openviking-windows.sh --yes --harness zcode,codex --url <server-url> --api-key <key>

# 卸载 / 官方参数总览
bash install-openviking-windows.sh --uninstall --yes --harness zcode
bash install-openviking-windows.sh --help

# 保留下载与补丁的临时目录供检查
bash install-openviking-windows.sh --keep ...
```

`--harness` 可选值与全部参数见官方安装器（`--help`）：claude, codex, cursor, trae, trae-cn,
trae-cli, zcode, kimicode, codebuddy, opencode, pi, dsh, cli。

### WorkBuddy（腾讯 GUI 版，实验性）

官方 harness 列表没有 WorkBuddy，本脚本以 MCP-only 方式单独支持（`--workbuddy`）：
组装 mcp-proxy 运行时到 `~/.openviking/agent-integrations/workbuddy`，向
`~/.workbuddy/connectors/default/mcp.json` 合并一个 stdio 型 `openviking` server 条目
（幂等、写前备份，原有连接器不动）。重启 WorkBuddy 后其 agent 即可调用 OpenViking 的
MCP 工具检索/保存记忆。

```bash
bash install-openviking-windows.sh --workbuddy           # 安装
bash install-openviking-windows.sh --workbuddy-remove    # 移除
```

> 已在 Windows 实测：JSON-RPC initialize 握手正常、24 个工具可用。局限：WorkBuddy
> 没有 hooks 机制，记忆不会自动注入对话，需要其 agent 按需调用 MCP 工具。

## 它修了什么 / The 8 patches

| # | 补丁 | 原因 |
|---|------|------|
| 00 | 文件头标记 | 说明性 |
| 01 | OS 门禁放行 `MINGW*/MSYS*/CYGWIN*` | 上游只认 `Darwin\|Linux` |
| 02 | hook 条目改写为 `type: process` 参数向量（timeout 秒 → timeoutMs 毫秒） | 上游写的是 POSIX shell 命令串，Windows 宿主用非 POSIX shell 执行 command 型 hook，必然失败；process 型无 shell、参数向量直传，是宿主文档认定的可移植形式 |
| 03 | ZCode config.json 合并后同样转换 | 同 02 |
| 04 | TRAE / TRAE CN 的 mcp.json 指向 `%APPDATA%\Trae[ CN]\User` | 对应 macOS 的 `~/Library/Application Support` |
| 05 | 安装后校验兼容反斜杠路径 | `path.join` 在 Windows 产生 `\`，JSON 转义成 `\\`，正斜杠 grep 匹配不上 |
| 06 | npm 全局目录用 Windows 布局（无 `bin/`，shim 在 prefix 根） | npm 布局差异 |
| 07 | `ov` CLI 路径同上 | 同 06 |

另有两项引导脚本自身的处理（不改上游文件）：

- **Volta node shim 绕过**：Volta 的 node shim 会丢失多行 `node -e` 参数，导致官方安装器
  `json_get` 静默失效、凭据读不出、`ovcli.conf` 的 url 被重置为 `127.0.0.1`。脚本启动时探测
  该缺陷，命中则把 `volta which node` 解析出的真实 node.exe 前置到 PATH。
- **路径转换**：无需补丁——MSYS 在 bash 调用 node.exe 时自动把 `/c/Users/...` 转成
  `C:/Users/...`（已实测），Node 的 `path.join` 在 Windows 上产出原生路径。

## 工作原理 / How it works

```
校验环境（Git Bash + Node 18+ + curl + unzip）
  → Volta shim 自检
  → 确认闸门：未显式 --harness/--yes/--help 时，无终端直接拒绝；有终端也需回车确认
    （上游安装器在无终端时按默认安装全部探测到的 agent，这是护栏）
  → 下载官方 install.sh（docs.openviking.net / docs.openviking.ai，双源顺序回退，校验文件头）
  → 8 个补丁：每个锚点在上游文件中必须恰好出现一次，任何失配立即中止
  → bash -n 语法校验
  → OPENVIKING_INSTALLER_REEXEC=0 运行，参数原样转发，退出码透传
```

补丁以 `NN.search` / `NN.replace` 文件对（quoted heredoc 落盘，零转义）交给临时 patcher
应用；**上游改动导致锚点失配时会响亮失败并拒绝运行未打补丁的安装器**，不会静默装错。

## 维护 / Maintenance（上游更新后）

上游 `install.sh` 改动相关代码块时，对应补丁会失配并中止。更新方法：

1. 运行一次看报错中的补丁编号（如 `01`）；
2. 下载最新官方安装器，找到对应代码块的新原文，替换脚本中的 `NN.search` heredoc；
3. 按需更新 `NN.replace`（保持 Windows 适配逻辑），跑 `bash install-openviking-windows.sh --help`
   看到 `applied 8/8 patches` 即通过；
4. 提交并在 README 或 commit message 里记录基准的上游 `INSTALLER_VERSION`。

已验证基准：`INSTALLER_VERSION=20261111-12b188a787`（上游 20261104→20261111 的改动
不影响锚点）。

## 安全说明 / Trust model

与官方 `curl | bash` 安装方式相同的信任模型：文件头校验可伪造、无签名/校验和；本脚本
只在临时目录写补丁产物，其余写入均由官方安装器完成。`OPENVIKING_DOWNLOAD_BASE` 可指向
自建镜像。

## 已验证环境

- Windows 10/11 + Git Bash + Volta node 24 / 官方 Node 18+
- ZCode 集成全链路：安装 → `hooks.events`（process 型）+ `mcp.servers` → 官方 doctor
  0 failures → hook 实际触发（SessionStart / UserPromptSubmit）
- 补丁失配路径（模拟上游改动）：报失配编号并拒绝运行，exit 1

## License

[AGPL-3.0](./LICENSE)（补丁内容派生自上游 AGPL 代码，跟随同许可）。
