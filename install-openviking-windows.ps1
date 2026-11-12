#Requires -Version 5.1
<#
install-openviking-windows.ps1
OpenViking memory plugin — Windows 安装的 PowerShell 启动器（非官方）。

给没有 Git Bash 的机器用：本脚本找到 Git Bash（找不到时可用 winget 安装），
获取 install-openviking-windows.sh（本地副本优先，否则从 CDN 下载），然后把
全部参数原样转发给它运行。引擎仍是 bash 引导脚本，本脚本只负责启动。

用法 / Usage:
  交互向导（不带任何参数）:
    powershell -ExecutionPolicy Bypass -File install-openviking-windows.ps1
  非交互:
    powershell -ExecutionPolicy Bypass -File install-openviking-windows.ps1 --yes --harness zcode
  零文件一行式（直接执行远端脚本；注意 iex 无法携带参数，仅交互终端使用——
  向导会正常弹出；无终端环境下 bash 侧保护会拒绝默认安装）:
    iex (irm https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.ps1)

说明:
  - Windows 自带的 System32\bash.exe 是 WSL 的 bash：它安装到 Linux 侧的 $HOME，
    配置不到 Windows 的 agent，本脚本不会使用它。
  - winget 安装 Git 前会先询问（y/N），不会静默装软件。
  - SPDX-License-Identifier: AGPL-3.0-only；补丁与引导脚本派生自
    https://github.com/volcengine/OpenViking（AGPL-3.0）。
    Repo: https://github.com/L9m/openviking-windows
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
function Info($m) { Write-Host "==> $m" }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
# 审查修复：用 throw 而非 exit——`iex (irm ...)` 一行式运行在用户的交互
# PowerShell 会话里，exit 会直接关掉整个控制台；throw 两种模式都正确
# （-File 模式同样以非零退出码结束）。
function Die($m)  { throw $m }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ---- 1) 定位 Git Bash（绝不使用 WSL 的 System32\bash.exe） -------------------
if (Test-Path "$env:SystemRoot\System32\bash.exe") {
  Warn "检测到 WSL 的 bash（System32\bash.exe）——它安装到 Linux 侧，配置不到 Windows 的 agent，不使用。"
}

$candidates = @()
# a) 注册表：Git for Windows 官方安装器必写（机器级 HKLM / 用户级 HKCU），最可靠
foreach ($rk in @('HKLM:\SOFTWARE\GitForWindows', 'HKCU:\SOFTWARE\GitForWindows')) {
  if (Test-Path $rk) {
    $ip = (Get-ItemProperty $rk -ErrorAction SilentlyContinue).InstallPath
    if ($ip) { $candidates += (Join-Path $ip 'bin\bash.exe') }
  }
}
# b) PATH 扫描。兼容从 Git Bash 启动本脚本时继承的 POSIX 风格 PATH（如
#    /d/Program Files/Git/cmd），把它换算回 Windows 路径再找 git.exe。
foreach ($seg in ($env:PATH -split ';')) {
  if (-not $seg) { continue }
  $w = $null
  if ($seg -match '^/([a-zA-Z])/(.+)$') { $w = "$($Matches[1].ToUpper()):\$($Matches[2])" }
  elseif ($seg -match '^[a-zA-Z]:[\\/]') { $w = $seg }
  else { continue }
  $w = $w -replace '/', '\'
  if (Test-Path (Join-Path $w 'git.exe')) { $candidates += (Join-Path (Split-Path $w) 'bin\bash.exe') }
}
# c) 原生 Windows PATH 场景
$gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCmd) { $candidates += (Join-Path (Split-Path (Split-Path $gitCmd.Source)) 'bin\bash.exe') }
# d) 常见安装位置兜底
$candidates += @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $bash) {
  Warn "未找到 Git Bash。请安装 Git for Windows: https://git-scm.com"
  # 安全底线：输入被重定向（脚本/CI 等非交互环境）时绝不安装软件
  if ([Console]::IsInputRedirected) {
    Die "当前为非交互环境，不会自动安装软件。请在交互终端中重试，或手动安装 Git for Windows。"
  }
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Die "本机没有 winget。请安装 Git for Windows 后重试: https://git-scm.com"
  }
  # 已装却找不到 bash 多半是安装位置特殊：提示人工确认，不重装/升级
  $listed = (& winget list -e --id Git.Git --accept-source-agreements 2>$null | Select-String 'Git\.Git')
  if ($listed) {
    Die "winget 显示 Git.Git 已安装，但未在常见位置找到 bash.exe。请确认其安装目录下的 bin\bash.exe 后重试。"
  }
  $reply = Read-Host "是否现在用 winget 安装 Git for Windows？(y/N)"
  if ($reply -notmatch '^[Yy]') { Die "已取消。" }
  & winget install -e --id Git.Git --source winget --disable-interactivity --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { Die "winget 安装失败，请手动安装: https://git-scm.com" }
  $bash = "$env:ProgramFiles\Git\bin\bash.exe"
  if (-not (Test-Path $bash)) { Die "Git 已安装但未找到 bash.exe；请新开一个终端重试。" }
}
Info "Git Bash: $bash"

# ---- 2) 获取 bash 引导脚本：本地副本优先，否则下载 ----------------------------
$sh = $null
if ($PSScriptRoot) {
  $local = Join-Path $PSScriptRoot 'install-openviking-windows.sh'
  if (Test-Path $local) { $sh = $local; Info "使用本地引导脚本: $sh" }
}
if (-not $sh) {
  $urls = @(
    'https://fastly.jsdelivr.net/gh/L9m/openviking-windows@main/install-openviking-windows.sh',
    'https://raw.githubusercontent.com/L9m/openviking-windows/main/install-openviking-windows.sh'
  )
  $dest = Join-Path $env:TEMP 'install-openviking-windows.sh'
  foreach ($u in $urls) {
    Info "下载引导脚本: $u"
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $dest
      $sh = $dest
      break
    } catch { Warn "下载失败: $u" }
  }
  if (-not $sh) { Die "引导脚本下载失败（fastly.jsdelivr.net 与 raw.githubusercontent.com 均不可达）。可改用: git clone https://github.com/L9m/openviking-windows.git 后运行其中的 .sh" }
}

# ---- 3) 运行，参数原样转发，退出码透传 ----------------------------------------
# bash 引导脚本输出 UTF-8；PowerShell 5.1 默认按系统 ANSI(GBK) 解码会显示乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$shPosix = ($sh -replace '\\', '/')
Info "运行引导脚本（参数原样转发）..."
& $bash $shPosix @RemainingArgs
# 审查修复：-File 模式透传退出码；iex 模式成功时不 exit（exit 会关掉用户
# 的交互 PowerShell 会话），失败时 throw 报错。
if ($PSScriptRoot) { exit $LASTEXITCODE }
if ($LASTEXITCODE -ne 0) { throw "安装器退出码 $LASTEXITCODE" }
