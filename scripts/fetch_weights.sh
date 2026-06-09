#!/usr/bin/env bash
# =============================================================================
# 下载 AnyDexGrasp 模型权重到 AnyDexGrasp/logs/（不纳入 git）。
#
# 官方权重在 GoogleDrive：
#   https://drive.google.com/drive/folders/1XfJmEkg29vq7swCndnS_B0Y4djwWhZRo
# 由于 GoogleDrive 目录无法稳定脚本化下载，这里提供三种方式：
#   1) 设置 WEIGHTS_TAR 指向已拷到本机的 tar.gz（由 pack_weights.sh 生成）直接解压；
#   2) 设置 WEIGHTS_URL 指向你自建的镜像（tar.gz）后自动下载解压；
#   3) 都未设置时仅打印手动放置说明。
#
# 用法：
#   WEIGHTS_TAR=/path/to/anydex_weights.tar.gz bash scripts/fetch_weights.sh
#   WEIGHTS_URL="https://your-mirror/anydex_weights.tar.gz" bash scripts/fetch_weights.sh
# =============================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS_DIR="$HERE/AnyDexGrasp/logs"
mkdir -p "$LOGS_DIR"

log()  { printf '\033[1;36m[weights]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[weights][WARN]\033[0m %s\n' "$*"; }

# 解压后校验关键文件是否就位
verify_weights() {
  if [[ -e "$LOGS_DIR/model/checkpoint.tar.18" ]]; then
    log "校验通过：找到 model/checkpoint.tar.18"
  else
    warn "未找到 model/checkpoint.tar.18，请确认 tar 内层结构（顶层应为 model/）。"
  fi
}

if [[ -n "${WEIGHTS_TAR:-}" ]]; then
  [[ -f "$WEIGHTS_TAR" ]] || { warn "WEIGHTS_TAR 不存在: $WEIGHTS_TAR"; exit 1; }
  log "从本地 $WEIGHTS_TAR 解压到 $LOGS_DIR ..."
  tar -xzf "$WEIGHTS_TAR" -C "$LOGS_DIR"
  verify_weights
  log "权重就绪。"
elif [[ -n "${WEIGHTS_URL:-}" ]]; then
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
  verify_weights
  log "权重就绪。"
else
  warn "未设置 WEIGHTS_TAR / WEIGHTS_URL，跳过自动获取。"
  cat <<EOF

  请按以下任一方式准备权重（最终落到 $LOGS_DIR/model/...）：

  A) 从源机器打包后拷过来（推荐）：
     # 源机器上：
     bash scripts/pack_weights.sh                       # 生成 anydex_weights.tar.gz
     # 拷到本机后：
     WEIGHTS_TAR=/path/to/anydex_weights.tar.gz bash scripts/fetch_weights.sh

  B) 从官方 GoogleDrive 手动下载：
     1. 打开 https://drive.google.com/drive/folders/1XfJmEkg29vq7swCndnS_B0Y4djwWhZRo
     2. 解压后确保结构为：
          $LOGS_DIR/model/checkpoint.tar.18
          $LOGS_DIR/model/inspire_model/obj140/...

EOF
fi
