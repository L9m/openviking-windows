# openviking-windows

OpenViking 记忆插件的 **Windows 安装器**（非官方）。官方安装器只支持 macOS / Linux，本脚本运行时自动下载官方最新版并适配 Windows。

## 安装

**Git Bash（推荐）**——交互向导，勾选 agent、填服务器和 API key：

```bash
curl -fsSL https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.sh | bash -s --
```

非交互（脚本 / CI）：

```bash
curl -fsSL https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.sh | bash -s -- --yes --harness zcode
```

**没有 Git Bash？** 用 PowerShell：

```powershell
iex (New-Object Net.WebClient).DownloadString('https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.ps1')
```

## 常用命令

| 操作 | 命令 |
|---|---|
| 卸载 | `bash install-openviking-windows.sh --uninstall --yes --harness zcode` |
| WorkBuddy 集成（MCP） | `bash install-openviking-windows.sh --workbuddy` |
| 全部参数 | `bash install-openviking-windows.sh --help` |

## 说明

- 要求：Git Bash + Node.js 18+
- 支持的 agent：zcode（实测）、codex、cursor、trae、codebuddy、kimicode、opencode、pi、dsh
- 许可：AGPL-3.0，派生自 [volcengine/OpenViking](https://github.com/volcengine/OpenViking)，与其无关联
- 详细文档（补丁原理、维护指南、常见问题）：[docs/DETAILS.md](./docs/DETAILS.md)
