#!/usr/bin/env bash
# =============================================================================
# 在“源机器”上把已训练好的权重打包成 anydex_weights.tar.gz，便于拷到目标机。
#
# 权重运行时按 logs/ 相对路径加载（见 robot_inspire*.py）：
#   logs/model/checkpoint.tar.18                 表示模型
#   logs/model/inspire_model/obj140/...          Inspire 多指决策模型
# 因此本脚本从 logs/ 内部打包，顶层即 model/，解压到目标机 AnyDexGrasp/logs/ 即就位。
#
# 用法（在源机器上）：
#   # 默认从本仓库 AnyDexGrasp/logs 打包：
#   bash scripts/pack_weights.sh
#   # 或显式指定源 logs 目录与输出文件：
#   SRC_LOGS=/home/pine/NTU_Yuanjiang/AnyDexGrasp/logs \
#   OUT=/tmp/anydex_weights.tar.gz bash scripts/pack_weights.sh
# =============================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_LOGS="${SRC_LOGS:-$HERE/AnyDexGrasp/logs}"
OUT="${OUT:-$HERE/anydex_weights.tar.gz}"

log()  { printf '\033[1;36m[pack]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pack][WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[pack][ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$SRC_LOGS" ]] || die "源 logs 目录不存在: $SRC_LOGS（用 SRC_LOGS=... 指定）。"
[[ -e "$SRC_LOGS/model/checkpoint.tar.18" ]] || \
  warn "未发现 model/checkpoint.tar.18，确认 $SRC_LOGS 是否为正确的权重目录。"

log "打包 $SRC_LOGS  ->  $OUT"
# -C 进入 logs/ 内部，'.' 打包其全部内容（顶层为 model/）。
tar -czf "$OUT" -C "$SRC_LOGS" .

SIZE="$(du -h "$OUT" | awk '{print $1}')"
log "完成：$OUT （$SIZE）"
cat <<EOF

  下一步（拷到目标机并解压）：
    # 1) 传输（任选其一）：
    scp "$OUT" user@target:/path/to/anydexgrasp_with_ME/
    #   或放到可下载地址后在目标机用 WEIGHTS_URL 自动拉取。

    # 2) 在目标机解压（任选其一）：
    WEIGHTS_TAR=/path/to/anydex_weights.tar.gz bash scripts/fetch_weights.sh
    #   或手动：
    tar -xzf anydex_weights.tar.gz -C AnyDexGrasp/logs/

EOF
