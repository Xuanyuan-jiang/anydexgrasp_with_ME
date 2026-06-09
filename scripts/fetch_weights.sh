#!/usr/bin/env bash
# =============================================================================
# 下载 AnyDexGrasp 模型权重到 AnyDexGrasp/logs/（不纳入 git）。
#
# 官方权重在 GoogleDrive：
#   https://drive.google.com/drive/folders/1XfJmEkg29vq7swCndnS_B0Y4djwWhZRo
# 由于 GoogleDrive 目录无法稳定脚本化下载，这里提供两种方式：
#   1) 设置 WEIGHTS_URL 指向你自建的镜像（tar.gz）后自动下载解压；
#   2) 未设置时仅打印手动放置说明。
#
# 用法：
#   WEIGHTS_URL="https://your-mirror/anydex_logs.tar.gz" bash scripts/fetch_weights.sh
# =============================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS_DIR="$HERE/AnyDexGrasp/logs"
mkdir -p "$LOGS_DIR"

log()  { printf '\033[1;36m[weights]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[weights][WARN]\033[0m %s\n' "$*"; }

if [[ -n "${WEIGHTS_URL:-}" ]]; then
  log "从 $WEIGHTS_URL 下载权重..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  if command -v curl >/dev/null 2>&1; then
    curl -L "$WEIGHTS_URL" -o "$TMP/weights.tar.gz"
  else
    wget -O "$TMP/weights.tar.gz" "$WEIGHTS_URL"
  fi
  log "解压到 $LOGS_DIR ..."
  tar -xzf "$TMP/weights.tar.gz" -C "$LOGS_DIR"
  log "权重就绪。"
else
  warn "未设置 WEIGHTS_URL，跳过自动下载。"
  cat <<EOF

  请手动准备权重：
    1. 打开 https://drive.google.com/drive/folders/1XfJmEkg29vq7swCndnS_B0Y4djwWhZRo
    2. 下载内容放到: $LOGS_DIR/
    3. 表示模型数据解压到:
         $LOGS_DIR/data/representation_model/graspnet_v1_newformat/
    （或把这些打包成 tar.gz 放自建镜像，设 WEIGHTS_URL 后重跑本脚本）

EOF
fi
