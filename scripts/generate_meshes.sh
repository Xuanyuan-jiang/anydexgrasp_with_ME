#!/usr/bin/env bash
# =============================================================================
# 现场重新生成手部 mesh / 体素点云（替代不进 git 的 18.8G 资产）。
# 从 AnyDexGrasp/ 根目录运行各 recover 脚本，输出到
#   generate_mesh_and_pointcloud/<hand>_urdf/meshes/{source,source_pointclouds}
#
# 输入（已随 git 仓库保留）：
#   <hand>_urdf/urdf-*/meshes/Link*.STL  基础 link 网格
#   <hand>_urdf/*.xls(x)                 角度映射表
#   <hand>_urdf/urdf-*/robots/*.urdf     URDF
#
# 用法（在 anydexgrasp_portable/ 内，已 conda activate）：
#   bash scripts/generate_meshes.sh            # 默认只生成 Inspire（目标手）
#   HANDS="inspire dh3 allegro" bash scripts/generate_meshes.sh   # 生成全部
# =============================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADG_DIR="$HERE/AnyDexGrasp"

log()  { printf '\033[1;36m[mesh]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[mesh][WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[mesh][ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$ADG_DIR/generate_mesh_and_pointcloud" ]] || \
  die "未找到 generate_mesh_and_pointcloud（先运行 scripts/assemble_repo.sh）。"

# recover 脚本内部使用相对路径 ./generate_mesh_and_pointcloud/...，必须在 ADG 根运行
cd "$ADG_DIR"

# ur_toolbox 需在 import 路径中（recover 脚本 import ur_toolbox.robot...）
export PYTHONPATH="$ADG_DIR:$ADG_DIR/ur_toolbox:${PYTHONPATH:-}"

declare -A SCRIPT_OF=(
  [inspire]="generate_mesh_and_pointcloud/recover_inspire_hand_to_stl.py"
  [dh3]="generate_mesh_and_pointcloud/recover_dh3_hand_to_stl.py"
  [allegro]="generate_mesh_and_pointcloud/recover_allegro_hand_to_stl.py"
)

HANDS="${HANDS:-inspire}"
for hand in $HANDS; do
  script="${SCRIPT_OF[$hand]:-}"
  [[ -n "$script" ]] || { warn "未知手型 '$hand'，跳过。"; continue; }
  [[ -f "$script" ]] || { warn "缺少脚本 $script，跳过。"; continue; }
  log "生成 $hand 手 mesh/点云：python3 $script （耗时较长，需 GUI-less pybullet）"
  python3 "$script" || die "生成 $hand 失败。检查 open3d/pybullet/xlrd2 是否安装。"
  log "$hand 完成。"
done

log "mesh/点云生成结束。运行期所需的 source/source_pointclouds 已就位。"
