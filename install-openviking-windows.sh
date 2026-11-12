#!/usr/bin/env bash
#
# install-openviking-windows.sh
# OpenViking memory plugin — Windows installer (unofficial bootstrap).
# 通用版：自动下载最新官方安装器，动态套用 Windows 适配补丁，再原样运行。
#
# SPDX-License-Identifier: AGPL-3.0-only
# The embedded patch replacements derive from the upstream installer at
# https://github.com/volcengine/OpenViking (AGPL-3.0); this bootstrap follows
# the same license. Not affiliated with the upstream project.
# Repo: https://github.com/L9m/openviking-windows
#
# 用法 / Usage (Git Bash on Windows):
#   bash install-openviking-windows.sh [官方安装器的任意参数]
#
#   交互模式（推荐）：不带任何参数运行，进入官方安装器的交互向导——
#   选语言 → 复选框勾选 agent（zcode / codex / cursor / trae / ...，已探测到的预选）
#   → 服务器配置 → 安装计划确认。curl | bash 一行安装同样支持。
#     bash install-openviking-windows.sh
#
#   常用示例（非交互，脚本/CI 用）:
#     bash install-openviking-windows.sh --yes --harness zcode
#     bash install-openviking-windows.sh --yes --harness zcode,codex \
#          --url <server-url> --api-key <key>
#     bash install-openviking-windows.sh --uninstall --yes --harness zcode
#     bash install-openviking-windows.sh --help          # 官方参数总览
#
#   本脚本自有参数:
#     --keep, -k          保留临时目录（含打完补丁的安装器）供检查
#     --workbuddy         给腾讯 WorkBuddy（GUI，~/.workbuddy）安装 OpenViking
#                         MCP 集成：组装运行时 + 往 connectors/default/mcp.json
#                         合并 openviking server 条目（stdio）。WorkBuddy 无
#                         hooks 机制，记忆自动注入不可用，MCP 工具按需调用。
#     --workbuddy-remove  移除 WorkBuddy 的 OpenViking MCP 集成
#
# 环境要求: Git Bash (MSYS2/MINGW/Cygwin)、Node.js 18+、curl、unzip
#           （npm 可选，仅 --harness cli 需要）
#
# 它做了什么 / What it does:
#   1. 校验运行环境（必须 MSYS/MINGW/CYGWIN；macOS/Linux 请直接用官方脚本）
#   2. 探测 Volta node shim 的多行 `-e` 参数丢失问题；命中则把真实
#      node.exe 前置到 PATH（否则官方安装器的 json_get 等会静默失效）
#   3. 从 docs.openviking.net / docs.openviking.ai 下载最新官方安装器
#      （校验文件头是 OpenViking 官方安装器）
#   4. 套用 8 个 Windows 适配补丁（每个锚点必须恰好匹配一次，失配即中止
#      并提示上游已改动，绝不运行未打补丁的安装器）：
#        00 文件头标记                     （说明性）
#        01 OS 门禁放行 MINGW*/MSYS*/CYGWIN*
#        02 hook 条目转 `type: process`    （POSIX command 串在 Windows 宿主
#                                           的 shell 中无法执行；process 型
#                                           是参数向量、无 shell，各宿主文档
#                                           认定的可移植形式；timeout 秒转
#                                           timeoutMs 毫秒）
#        03 ZCode config.json 合并后同样转换
#        04 TRAE/TRAE CN 的 mcp.json 指向 %APPDATA%\Trae[ CN]\User
#        05 安装后校验：兼容反斜杠路径、process 型无 env 前缀
#        06/07 npm 在 Windows 的目录布局（无 bin/，shim 在 prefix 根）
#   5. bash -n 语法校验后以 OPENVIKING_INSTALLER_REEXEC=0 运行，退出码透传
#
set -Eeuo pipefail

KEEP=0
WORKBUDDY=0
WORKBUDDY_REMOVE=0
forward_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep|-k) KEEP=1; shift ;;
    --workbuddy) WORKBUDDY=1; shift ;;
    --workbuddy-remove) WORKBUDDY_REMOVE=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do forward_args+=("$1"); shift; done; break ;;
    *) forward_args+=("$1"); shift ;;
  esac
done
set -- ${forward_args[@]+"${forward_args[@]}"}

note() { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'xx  %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- environment
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  Darwin|Linux)
    die "这是 macOS/Linux — 直接用官方安装器即可: curl -fsSL https://openviking.ai/install | bash" ;;
  *)
    die "不支持的运行环境 ($(uname -s))。请在 Windows 的 Git Bash 中运行本脚本（https://git-scm.com）。" ;;
esac

command -v curl  >/dev/null 2>&1 || die "缺少 curl"
command -v unzip >/dev/null 2>&1 || die "缺少 unzip（Git Bash 自带；请检查安装）"
command -v node  >/dev/null 2>&1 || die "缺少 Node.js 18+（https://nodejs.org）"
node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
[ "$node_major" -ge 18 ] || die "需要 Node.js 18+，当前 $(node --version 2>/dev/null || echo '未知')"

# Volta's node shim drops multi-line `-e` arguments when it re-spawns the real
# node.exe; the official installer relies on multi-line `node -e` in several
# helpers (json_get among them) and they fail silently through the shim. Probe
# for exactly that, and if broken, put the real node.exe first on PATH. The
# installer (a child process) inherits the fixed PATH.
if ! node -e '
console.log("probe");
' >/dev/null 2>&1; then
  if command -v volta >/dev/null 2>&1; then
    real_node="$(volta which node 2>/dev/null || true)"
    case "$real_node" in
      *node.exe)
        PATH="$(dirname "$(cygpath -u "$real_node")"):$PATH"
        export PATH
        note "Volta node shim 检测到多行 -e 缺陷，已改用真实 node: $real_node"
        ;;
      *) die "node 多行 -e 参数不可用（Volta shim 已知问题），且 volta which node 未返回 node.exe" ;;
    esac
  else
    die "node 多行 -e 参数不可用且未发现 volta。官方安装器的凭据读取等步骤会静默失效
（已知后果：~/.openviking/ovcli.conf 的 url 被重置为 127.0.0.1）。请安装 Volta
（volta.sh）或官方 Node.js（nodejs.org）后重试。"
  fi
fi

# ------------------------------------------------------------- workbuddy MCP
# 腾讯 WorkBuddy（GUI，~/.workbuddy）没有 CLI、也没有 hooks 机制，但它的 MCP
# 配置 ~/.workbuddy/connectors/default/mcp.json 接受 stdio server（command+args，
# 连接器市场里已有 "command": "npx" 型先例）。安装 = 在
# ~/.openviking/agent-integrations/workbuddy 组装 mcp-proxy 运行时，并向该
# mcp.json 合并一个 openviking server 条目（幂等、写前备份）。
workbuddy_install() {
  local ov_home="${OPENVIKING_HOME:-$HOME/.openviking}"
  local integ="$ov_home/agent-integrations/workbuddy"
  local shared="$ov_home/agent-integrations/memory-plugin-shared/lib"
  local mcp_file="$HOME/.workbuddy/connectors/default/mcp.json"
  local need_bundle=0
  # 审查修复：WorkBuddy 不存在时不写孤儿配置（~/.workbuddy 由其本身创建）
  [ -d "$HOME/.workbuddy" ] || die "未检测到 WorkBuddy（~/.workbuddy 不存在）。请先安装 WorkBuddy 再运行 --workbuddy。"
  [ -f "$integ/servers/mcp-proxy.mjs" ] || need_bundle=1
  [ -f "$shared/MANIFEST" ] || need_bundle=1

  if [ "$need_bundle" -eq 1 ]; then
    local workdir zdir unpacked base url downloaded=0 f
    workdir="$(mktemp -d "${TMPDIR:-/tmp}/ov-workbuddy.XXXXXX")" || die "mktemp 失败"
    # 审查修复：中途 die 时清理临时目录（此前会泄漏 /tmp/ov-workbuddy.*）
    trap 'rm -rf "$workdir"' EXIT
    zdir="$workdir/mkt.zip"; unpacked="$workdir/mkt/memory-plugin-marketplace"
    for base in ${OPENVIKING_DOWNLOAD_BASE:-https://docs.openviking.net/dl https://docs.openviking.ai/dl}; do
      url="${base%/}/releases/latest/memory-plugin-marketplace.zip"
      note "下载插件包: $url"
      if curl -fsSL --connect-timeout 10 -m 180 -o "$zdir" "$url"; then downloaded=1; break; fi
    done
    [ "$downloaded" -eq 1 ] || die "插件包下载失败"
    unzip -q "$zdir" -d "$workdir/mkt" || die "插件包解压失败"
    [ -d "$unpacked/agent-hook-plugin" ] || die "插件包布局异常（缺少 agent-hook-plugin）"

    if [ ! -f "$integ/servers/mcp-proxy.mjs" ]; then
      rm -rf "$integ.tmp"
      mkdir -p "$integ.tmp"
      (cd "$unpacked/agent-hook-plugin" && tar --exclude node_modules --exclude .git -cf - .) | (cd "$integ.tmp" && tar -xf -)
      rm -rf "$integ"
      mkdir -p "$(dirname "$integ")"
      mv "$integ.tmp" "$integ"
      note "运行时已组装: $integ"
    fi
    # mcp-proxy 依赖的同级共享库（../../memory-plugin-shared/lib，MANIFEST 闭包）
    if [ ! -f "$shared/MANIFEST" ]; then
      mkdir -p "$shared.tmp"
      while read -r f; do
        [ -n "$f" ] && cp "$unpacked/memory-plugin-shared/lib/$f" "$shared.tmp/$f"
      done < "$unpacked/memory-plugin-shared/lib/MANIFEST"
      cp "$unpacked/memory-plugin-shared/lib/MANIFEST" "$shared.tmp/MANIFEST"
      rm -rf "$shared"
      mkdir -p "$(dirname "$shared")"
      mv "$shared.tmp" "$shared"
      note "共享运行时已组装: $(dirname "$shared")"
    fi
    rm -rf "$workdir"
    trap - EXIT   # 已显式清理；避免退出时对失效的局部变量再执行 rm
  fi

  node - "$mcp_file" "$(cygpath -m "$(command -v node)")" "$(cygpath -m "$integ/servers/mcp-proxy.mjs")" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [file, cmd, script] = process.argv.slice(2);
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { if (e.code !== "ENOENT") throw e; }
cfg.mcpServers = cfg.mcpServers && typeof cfg.mcpServers === "object" && !Array.isArray(cfg.mcpServers) ? cfg.mcpServers : {};
const next = {
  command: cmd,
  args: [script],
  env: { OPENVIKING_INTEGRATION_ID: "openviking-memory", OPENVIKING_HOOK_SOURCE: "workbuddy" },
};
if (JSON.stringify(cfg.mcpServers.openviking || null) === JSON.stringify(next)) {
  console.log("已是最新，无需修改");
  process.exit(0);
}
if (fs.existsSync(file)) fs.writeFileSync(file + ".bak", fs.readFileSync(file));
fs.mkdirSync(path.dirname(file), { recursive: true });
cfg.mcpServers.openviking = next;
fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
console.log("已写入 openviking server 条目: " + file);
NODE
  note "重启 WorkBuddy 后生效（连接器/工具列表会出现 openviking）"
  note "说明: WorkBuddy 无 hooks 机制，OpenViking 记忆不会自动注入对话；其 agent 可按需调用 openviking MCP 工具检索/保存记忆"
}

workbuddy_remove() {
  local ov_home="${OPENVIKING_HOME:-$HOME/.openviking}"
  local mcp_file="$HOME/.workbuddy/connectors/default/mcp.json"
  local integ="$ov_home/agent-integrations/workbuddy"
  if [ -f "$mcp_file" ]; then
    node - "$mcp_file" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
let cfg;
try { cfg = JSON.parse(fs.readFileSync(file, "utf8")); } catch { process.exit(0); }
if (!cfg.mcpServers || !cfg.mcpServers.openviking) { console.log("未发现 openviking 条目"); process.exit(0); }
if (!JSON.stringify(cfg.mcpServers.openviking).includes("mcp-proxy.mjs")) {
  console.log("openviking 条目不是本脚本写入的，跳过");
  process.exit(0);
}
delete cfg.mcpServers.openviking;
fs.writeFileSync(file + ".bak", fs.readFileSync(file));
fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
console.log("已移除 openviking 条目: " + file);
NODE
  fi
  rm -rf "$integ"
  note "已移除 WorkBuddy 集成目录: $integ"
}

if [ "$WORKBUDDY_REMOVE" -eq 1 ]; then workbuddy_remove; exit 0; fi
if [ "$WORKBUDDY" -eq 1 ]; then workbuddy_install; exit 0; fi

# 审查修复（下载前）：未显式指定目标（--harness/--yes/--help）时，官方安装器
# 会按默认值安装全部探测到的 agent（zcode/codex/kimicode/cli...）。无终端环境
# （CI、curl|bash 进脚本、以及分配了 console 但无真人的子进程）必须拦下；
# 有 /dev/tty 时也要求一次带回车确认——console 可打开不代表真有人在敲键盘。
explicit=0
for a in "$@"; do
  case "$a" in --harness|--yes|-y|--help|-h) explicit=1; break ;; esac
done
if [ "$explicit" -ne 1 ]; then
  if exec 3</dev/tty 2>/dev/null; then
    printf '即将进入交互安装向导，按回车继续（5 秒无响应将自动中止）...'
    if ! IFS= read -r -t 5 _ <&3; then
      exec 3<&-
      die "无响应：检测到非真实交互环境，已中止（未下载、未安装任何内容）。
显式指定请用:  $0 --harness <list> [--yes]   或  $0 --help"
    fi
    exec 3<&-
  else
    die "无交互终端且未指定目标：为避免按默认安装全部探测到的 agent，已中止
（未下载、未安装任何内容）。在交互终端中直接运行本脚本可进入选择向导；
或显式指定，例如:
    $0 --yes --harness zcode            # 非交互安装到指定 agent
    $0 --harness zcode,codex --url <url> --api-key <key>
    $0 --help                            # 查看全部参数"
  fi
fi

# ------------------------------------------------------------------- download
workdir="$(mktemp -d "${TMPDIR:-/tmp}/ov-win-install.XXXXXX")" || die "mktemp 失败"
cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    note "保留临时目录: $workdir"
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

official="$workdir/install-official.sh"
fetched=0
for base in ${OPENVIKING_DOWNLOAD_BASE:-https://docs.openviking.net/dl https://docs.openviking.ai/dl}; do
  note "下载官方安装器: ${base%/}/memory-plugin-shared/install.sh"
  if curl -fsSL --connect-timeout 10 -m 120 -o "$official" "${base%/}/memory-plugin-shared/install.sh"; then
    if head -n 1 "$official" | grep -q '^#!' \
       && head -n 5 "$official" | grep -q 'OpenViking Memory Plugin shared installer'; then
      fetched=1
      export OPENVIKING_DOWNLOAD_BASE="${base%/}"
      break
    fi
    warn "$base 返回的内容不是 OpenViking 官方安装器"
  fi
done
[ "$fetched" -eq 1 ] || die "无法下载官方安装器（docs.openviking.net / docs.openviking.ai）"
version_line="$(grep -m1 '^INSTALLER_VERSION=' "$official" || echo 'INSTALLER_VERSION=(unknown)')"
note "官方安装器版本: ${version_line#INSTALLER_VERSION=}"

# --------------------------------------------------------------------- patches
# Each patch is a pair of files NN.search / NN.replace under $workdir/patches,
# written with quoted heredocs so every byte is literal. The patcher requires
# each search string to occur exactly once in the official installer.
patches="$workdir/patches"
mkdir -p "$patches"

cat > "$patches/00.search" <<'__OV_PATCH_EOF__'
#!/usr/bin/env bash
#
__OV_PATCH_EOF__
cat > "$patches/00.replace" <<'__OV_PATCH_EOF__'
#!/usr/bin/env bash
#
# >>> Windows adaptation, applied by install-openviking-windows.sh <<<
# 8 surgical patches: OS gate for MINGW/MSYS/CYGWIN, hook entries rewritten to
# `type: process` argument vectors (POSIX command strings do not run in Windows
# shells), TRAE mcp.json under %APPDATA%, backslash-tolerant validation, and
# npm's Windows layout. Everything else is the upstream installer unchanged.
#
__OV_PATCH_EOF__

cat > "$patches/01.search" <<'__OV_PATCH_EOF__'
case "$(uname -s)" in
  Darwin|Linux) ;;
  *) err "Unsupported OS: $(uname -s). Only macOS and Linux are supported."; exit 1 ;;
esac
__OV_PATCH_EOF__
cat > "$patches/01.replace" <<'__OV_PATCH_EOF__'
case "$(uname -s)" in
  Darwin|Linux) ;;
  # Windows adaptation: Git Bash / MSYS2 / Cygwin. The installer's own shell
  # work runs fine there; the platform differences are patched in above.
  MINGW*|MSYS*|CYGWIN*) OV_WINDOWS=1 ;;
  *) err "Unsupported OS: $(uname -s). Only macOS and Linux are supported."; exit 1 ;;
esac
__OV_PATCH_EOF__

cat > "$patches/02.search" <<'__OV_PATCH_EOF__'
agent_write_json_configs() { # agent_write_json_configs <kind> <hooks> <mcp> <root> <client-id> <node-bin>
  local lib
  lib="$(require_install_lib_dir)" || return 1
  "$NODE_BIN" "$lib/host-json-config.mjs" write "$1" "$2" "$3" "$4" "$5" "$6" "$SOURCE_MODE"
}
__OV_PATCH_EOF__
cat > "$patches/02.replace" <<'__OV_PATCH_EOF__'
# Windows adaptation: `type: command` hooks run through a shell, and the
# command string this installer renders is POSIX syntax (single-quoted env
# assignments), which no Windows shell runs. Rewrite this installer's entries
# in place into `type: process` argument vectors — the shell-free form the
# hosts document as the portable one. The hook scripts take their event and
# client id from argv (the env assignments are fallbacks and an ownership
# marker); the script paths keep the entries recognizable for uninstall.
win_process_hooks_file() { # win_process_hooks_file <json-file>
  [ "${OV_WINDOWS:-0}" -eq 1 ] || return 0
  [ -f "$1" ] || return 0
  "$NODE_BIN" - "$1" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
// Matches what renderHookCommand writes:
//   OPENVIKING_X='v' ... '<node>' '<script>' <args> [# openviking-memory]
const cmdRe = /^(?:[A-Z_][A-Z0-9_]*='[^']*'\s+)*'([^']+)'\s+'([^']+)'\s*([^#]*?)\s*(?:#\s*openviking-memory\s*)?$/;
const convert = (entry) => {
  const m = cmdRe.exec(entry.command || "");
  if (!m || !m[2].includes("agent-integrations")) return entry; // not ours
  const next = { ...entry, type: "process", command: m[1], args: [m[2], ...m[3].split(/\s+/).filter(Boolean)] };
  if (entry.timeout != null) { next.timeoutMs = entry.timeout * 1000; delete next.timeout; }
  return next;
};
const walk = (value) => {
  if (Array.isArray(value)) return value.map(walk);
  if (!value || typeof value !== "object") return value;
  const out = {};
  for (const [key, child] of Object.entries(value)) out[key] = walk(child);
  return out.type === "command" ? convert(out) : out;
};
const root = JSON.parse(fs.readFileSync(file, "utf8"));
const next = walk(root);
if (JSON.stringify(next) !== JSON.stringify(root)) {
  fs.writeFileSync(`${file}.win.tmp`, JSON.stringify(next, null, 2) + "\n");
  fs.renameSync(`${file}.win.tmp`, file);
}
NODE
}

agent_write_json_configs() { # agent_write_json_configs <kind> <hooks> <mcp> <root> <client-id> <node-bin>
  local lib
  lib="$(require_install_lib_dir)" || return 1
  "$NODE_BIN" "$lib/host-json-config.mjs" write "$1" "$2" "$3" "$4" "$5" "$6" "$SOURCE_MODE"
  win_process_hooks_file "$2"
}
__OV_PATCH_EOF__

cat > "$patches/03.search" <<'__OV_PATCH_EOF__'
zcode_merge_config() { # zcode_merge_config <config_path> <hooks_path> <mcp_path>
  local lib
  lib="$(require_install_lib_dir)" || return 1
  "$NODE_BIN" "$lib/host-json-config.mjs" merge-zcode "$1" "$2" "$3"
}
__OV_PATCH_EOF__
cat > "$patches/03.replace" <<'__OV_PATCH_EOF__'
zcode_merge_config() { # zcode_merge_config <config_path> <hooks_path> <mcp_path>
  local lib
  lib="$(require_install_lib_dir)" || return 1
  "$NODE_BIN" "$lib/host-json-config.mjs" merge-zcode "$1" "$2" "$3"
  win_process_hooks_file "$1"
}
__OV_PATCH_EOF__

cat > "$patches/04.search" <<'__OV_PATCH_EOF__'
trae_mcp_path() { # trae_mcp_path <client-id>
  local client_id="$1"
  if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$client_id" = "trae-cn" ]; then
      printf '%s' "$HOME/Library/Application Support/Trae CN/User/mcp.json"
    else
      printf '%s' "$HOME/Library/Application Support/Trae/User/mcp.json"
    fi
  elif [ "$client_id" = "trae-cn" ]; then
    printf '%s' "$HOME/.trae-cn/mcp.json"
  else
    printf '%s' "$HOME/.trae/mcp.json"
  fi
}
__OV_PATCH_EOF__
cat > "$patches/04.replace" <<'__OV_PATCH_EOF__'
trae_mcp_path() { # trae_mcp_path <client-id>
  local client_id="$1"
  if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$client_id" = "trae-cn" ]; then
      printf '%s' "$HOME/Library/Application Support/Trae CN/User/mcp.json"
    else
      printf '%s' "$HOME/Library/Application Support/Trae/User/mcp.json"
    fi
  elif [ "${OV_WINDOWS:-0}" -eq 1 ]; then
    # Windows adaptation: the GUI keeps its user data in %APPDATA% (Roaming).
    # Kept in Windows form on purpose: the file goes to the Node helpers and
    # into a config the native app reads.
    local roaming="${APPDATA:-$(cygpath -u "${USERPROFILE:-$HOME}")/AppData/Roaming}"
    if [ "$client_id" = "trae-cn" ]; then
      printf '%s' "$roaming/Trae CN/User/mcp.json"
    else
      printf '%s' "$roaming/Trae/User/mcp.json"
    fi
  elif [ "$client_id" = "trae-cn" ]; then
    printf '%s' "$HOME/.trae-cn/mcp.json"
  else
    printf '%s' "$HOME/.trae/mcp.json"
  fi
}
__OV_PATCH_EOF__

cat > "$patches/05.search" <<'__OV_PATCH_EOF__'
  grep -q 'scripts/hook.mjs' "$hooks" 2>/dev/null \
    && grep -q 'scripts/uri-guard.mjs' "$hooks" 2>/dev/null \
    && grep -q 'OPENVIKING_INTEGRATION_ID' "$hooks" 2>/dev/null \
    && grep -q 'mcp-proxy.mjs' "$mcp" 2>/dev/null || complete=0
__OV_PATCH_EOF__
cat > "$patches/05.replace" <<'__OV_PATCH_EOF__'
  # Windows adaptation: path.join writes backslashes and JSON escapes them to
  # `\\`, so the separator must match either slash or backslash; process-type
  # entries carry no OPENVIKING_INTEGRATION_ID env prefix.
  grep -qE 'scripts[/\\]+hook\.mjs' "$hooks" 2>/dev/null \
    && grep -qE 'scripts[/\\]+uri-guard\.mjs' "$hooks" 2>/dev/null \
    && { [ "${OV_WINDOWS:-0}" -eq 1 ] || grep -q 'OPENVIKING_INTEGRATION_ID' "$hooks" 2>/dev/null; } \
    && grep -q 'mcp-proxy.mjs' "$mcp" 2>/dev/null || complete=0
__OV_PATCH_EOF__

cat > "$patches/06.search" <<'__OV_PATCH_EOF__'
choose_cli_prefix() {
  contains_harness cli && command -v npm >/dev/null 2>&1 || return 0
  local prefix
  prefix="$(npm prefix -g 2>/dev/null || true)"
  if [ -n "$prefix" ] && dir_writable "$prefix/lib/node_modules" && dir_writable "$prefix/bin"; then
    CLI_PREFIX="$prefix"
  else
    CLI_PREFIX="$HOME/.local"
  fi
}
__OV_PATCH_EOF__
cat > "$patches/06.replace" <<'__OV_PATCH_EOF__'
choose_cli_prefix() {
  contains_harness cli && command -v npm >/dev/null 2>&1 || return 0
  local prefix
  prefix="$(npm prefix -g 2>/dev/null || true)"
  if [ "${OV_WINDOWS:-0}" -eq 1 ]; then
    # Windows adaptation: npm's layout is <prefix>\node_modules with the shims
    # in the prefix root; there is no lib/ or bin/.
    if [ -n "$prefix" ] && dir_writable "$prefix/node_modules" && dir_writable "$prefix"; then
      CLI_PREFIX="$prefix"
    else
      CLI_PREFIX="$HOME/.local"
    fi
  elif [ -n "$prefix" ] && dir_writable "$prefix/lib/node_modules" && dir_writable "$prefix/bin"; then
    CLI_PREFIX="$prefix"
  else
    CLI_PREFIX="$HOME/.local"
  fi
}
__OV_PATCH_EOF__

cat > "$patches/07.search" <<'__OV_PATCH_EOF__'
  local ov="$CLI_PREFIX/bin/ov" found version args
__OV_PATCH_EOF__
cat > "$patches/07.replace" <<'__OV_PATCH_EOF__'
  local ov found version args
  if [ "${OV_WINDOWS:-0}" -eq 1 ]; then
    # Windows adaptation: npm drops the shim beside the prefix, not in bin/.
    ov="$CLI_PREFIX/ov.cmd"
  else
    ov="$CLI_PREFIX/bin/ov"
  fi
__OV_PATCH_EOF__

cat > "$workdir/patcher.mjs" <<'__OV_PATCH_EOF__'
import fs from "node:fs";
import path from "node:path";
const [, , inFile, outFile, patchDir] = process.argv;
let text = fs.readFileSync(inFile, "utf8");
const names = fs.readdirSync(patchDir).filter((n) => n.endsWith(".search")).sort();
const failures = [];
let applied = 0;
for (const searchName of names) {
  const name = searchName.replace(/\.search$/, "");
  const search = fs.readFileSync(path.join(patchDir, searchName), "utf8");
  const replace = fs.readFileSync(path.join(patchDir, `${name}.replace`), "utf8");
  const first = text.indexOf(search);
  if (first === -1 || text.indexOf(search, first + 1) !== -1) {
    failures.push(name);
    continue;
  }
  text = text.slice(0, first) + replace + text.slice(first + search.length);
  applied += 1;
}
if (failures.length) {
  process.stderr.write(
    `Windows patches did not apply cleanly (upstream installer changed?): ${failures.join(", ")}\n` +
    "The unpatched installer was NOT run. Update install-openviking-windows.sh patches.\n",
  );
  process.exit(1);
}
fs.writeFileSync(outFile, text);
process.stdout.write(`applied ${applied}/${names.length} patches\n`);
__OV_PATCH_EOF__

# --------------------------------------------------------------------- run it
patched="$workdir/install-patched.sh"
note "套用 Windows 适配补丁..."
node "$workdir/patcher.mjs" "$official" "$patched" "$patches" || die "补丁应用失败，已中止（未运行任何安装动作）"
bash -n "$patched" || die "打补丁后的安装器语法校验失败，已中止"
note "运行安装器（参数原样转发）..."
status=0
OPENVIKING_INSTALLER_REEXEC=0 bash "$patched" "$@" || status=$?
exit "$status"
