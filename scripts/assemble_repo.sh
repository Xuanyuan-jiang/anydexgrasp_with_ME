#!/usr/bin/env bash
# =============================================================================
# 首次打包：从当前开发工作区把 AnyDexGrasp + 改动版 MinkowskiEngine 拷进本仓库。
# 排除编译产物、缓存、超大权重（logs/），保持仓库精简、可 git 化。
#
# 用法（在 anydexgrasp_portable/ 内运行）：
#   bash scripts/assemble_repo.sh                 # 默认源 = 上两级工作区
#   SRC_ROOT=/path/to/NTU_Yuanjiang bash scripts/assemble_repo.sh
# =============================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

# 源工作区根目录（包含 AnyDexGrasp/ 和 MinkowskiEngine/）
SRC_ROOT="${SRC_ROOT:-$(cd "$HERE/.." && pwd)}"
SRC_ADG="$SRC_ROOT/AnyDexGrasp"
SRC_ME="$SRC_ROOT/MinkowskiEngine"

log()  { printf '\033[1;36m[assemble]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[assemble][ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

command -v rsync >/dev/null 2>&1 || die "需要 rsync，请先安装 (apt install rsync)。"
[[ -d "$SRC_ADG" ]] || die "未找到源目录 $SRC_ADG"
[[ -d "$SRC_ME"  ]] || die "未找到源目录 $SRC_ME"

mkdir -p "$HERE/third_party"

# 通用排除：编译产物、缓存、git、虚拟环境
COMMON_EXCLUDES=(
  --exclude '.git/'
  --exclude '__pycache__/'
  --exclude '*.pyc'
  --exclude 'build/'
  --exclude 'dist/'
  --exclude '*.egg-info/'
  --exclude '.eggs/'
  --exclude '*.so'
  --exclude '*.o'
)

log "拷贝 AnyDexGrasp -> $HERE/AnyDexGrasp （排除 logs/ 权重、数据集、生成的 mesh/点云）"
# generate_mesh_and_pointcloud/*/meshes/source 与 source_pointclouds 是生成产物
# （18.8G），不进 git；目标机用 scripts/generate_meshes.sh 现场重生成。
# 输入（urdf-five3/meshes/Link*.STL、Excel、urdf）不在这两个目录，会被保留。
rsync -a --delete "${COMMON_EXCLUDES[@]}" \
  --exclude 'logs/' \
  --exclude 'dataset/' \
  --exclude 'data/' \
  --exclude 'generate_mesh_and_pointcloud/*/meshes/source' \
  --exclude 'generate_mesh_and_pointcloud/*/meshes/source_pointclouds' \
  "$SRC_ADG/" "$HERE/AnyDexGrasp/"

log "拷贝 MinkowskiEngine(改动版) -> $HERE/third_party/MinkowskiEngine"
rsync -a --delete "${COMMON_EXCLUDES[@]}" \
  "$SRC_ME/" "$HERE/third_party/MinkowskiEngine/"

log "完成。建议接着："
echo "  git init && git add -A && git commit -m 'init portable anydexgrasp'"
echo "  权重单独走 scripts/fetch_weights.sh（不进 git）"
