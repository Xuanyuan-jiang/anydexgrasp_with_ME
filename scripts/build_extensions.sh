#!/usr/bin/env bash
# =============================================================================
# 编译全部原生扩展。可单独运行（修完 ME 源码后重编）：
#   conda activate anydex && bash scripts/build_extensions.sh
#
# 依赖环境变量（由 setup_env.sh 传入，也可手动 export）：
#   TORCH_CUDA_ARCH_LIST  目标 GPU 架构，如 12.0 (Blackwell)
#   MAX_JOBS              并行编译数（ME 建议 2）
#   CUDA_HOME             CUDA toolkit 根目录
# =============================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

ME_DIR="$HERE/third_party/MinkowskiEngine"
ADG_DIR="$HERE/AnyDexGrasp"

export MAX_JOBS="${MAX_JOBS:-2}"

log()  { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build][WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[build][ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

log "TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST:-<未设置>}  MAX_JOBS=$MAX_JOBS  CUDA_HOME=${CUDA_HOME:-<未设置>}"

# -----------------------------------------------------------------------------
# 1. MinkowskiEngine（最易失败，放最前面便于尽早暴露问题）
# -----------------------------------------------------------------------------
if [[ -d "$ME_DIR" ]]; then
  log "编译 MinkowskiEngine（改动版）..."
  pushd "$ME_DIR" >/dev/null
  rm -rf build
  # --force_cuda 确保即使 torch.cuda.is_available() 在编译机为 False 也编 CUDA。
  CUDA_HOME_ARG=()
  [[ -n "${CUDA_HOME:-}" ]] && CUDA_HOME_ARG=(--cuda_home="$CUDA_HOME")
  if ! pip install -v --no-build-isolation \
        --global-option="--force_cuda" \
        ${CUDA_HOME_ARG:+--global-option="${CUDA_HOME_ARG[@]}"} \
        --global-option="--blas=openblas" . ; then
    warn "pip 方式失败，回退 setup.py 直接编译..."
    python setup.py install --force_cuda --blas=openblas \
      ${CUDA_HOME:+--cuda_home="$CUDA_HOME"} \
      || die "MinkowskiEngine 编译失败。请按报错修改 src/ 后重跑本脚本（见 README 已知风险）。"
  fi
  popd >/dev/null
  log "MinkowskiEngine 编译完成。"
else
  warn "未找到 $ME_DIR，跳过 MinkowskiEngine（先运行 scripts/assemble_repo.sh）。"
fi

# -----------------------------------------------------------------------------
# 2. knn
# -----------------------------------------------------------------------------
if [[ -d "$ADG_DIR/knn" ]]; then
  log "编译 knn ..."
  pushd "$ADG_DIR/knn" >/dev/null
  rm -rf build dist *.egg-info
  pip install --no-build-isolation . || die "knn 编译失败。"
  popd >/dev/null
fi

# -----------------------------------------------------------------------------
# 3. pointnet2
# -----------------------------------------------------------------------------
if [[ -d "$ADG_DIR/pointnet2" ]]; then
  log "编译 pointnet2 ..."
  pushd "$ADG_DIR/pointnet2" >/dev/null
  rm -rf build dist *.egg-info
  pip install --no-build-isolation . || die "pointnet2 编译失败。"
  popd >/dev/null
fi

# -----------------------------------------------------------------------------
# 4. graspnetAPI（纯 Python，--no-deps 避开其 numpy==1.23.4 硬钉）
# -----------------------------------------------------------------------------
if [[ -d "$ADG_DIR/graspnetAPI" ]]; then
  log "安装 graspnetAPI (--no-deps) ..."
  pushd "$ADG_DIR/graspnetAPI" >/dev/null
  pip install --no-deps -e . || warn "graspnetAPI 安装失败（非阻断）。"
  popd >/dev/null
fi

# -----------------------------------------------------------------------------
# 5. ur_toolbox + python-urx（机器人控制；纯 Python）
# -----------------------------------------------------------------------------
if [[ -d "$ADG_DIR/ur_toolbox" ]]; then
  log "安装 ur_toolbox ..."
  pushd "$ADG_DIR/ur_toolbox" >/dev/null
  pip install --no-deps -e . || warn "ur_toolbox 安装失败（非阻断）。"
  if [[ -d "python-urx" ]]; then
    pip install --no-deps -e ./python-urx || warn "python-urx 安装失败（非阻断）。"
  fi
  popd >/dev/null
fi

log "全部扩展处理结束。运行 python scripts/verify_install.py 验证。"
