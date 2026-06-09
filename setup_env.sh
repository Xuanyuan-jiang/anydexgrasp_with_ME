#!/usr/bin/env bash
# =============================================================================
# AnyDexGrasp Portable — 一键环境搭建 + 原生扩展编译
#
# git clone 后在目标机执行：
#   bash setup_env.sh
#
# 可用环境变量覆盖默认值：
#   ENV_NAME              conda 环境名            (默认 anydex)
#   PY_VER                python 版本             (默认 3.10)
#   TORCH_SPEC            torch pip 规格          (默认 "torch torchvision")
#   TORCH_INDEX_URL       torch wheel 索引        (默认按下方探测的 CUDA 版本)
#   TORCH_CUDA_ARCH_LIST  目标 GPU 架构           (默认自动探测，失败回退 native)
#   MAX_JOBS              并行编译数              (默认 2，ME 编译爆内存的已知缓解)
#   SKIP_TORCH_INSTALL=1  跳过 torch 安装（已装好时）
#   SKIP_WEIGHTS=1        跳过权重下载
# =============================================================================
# 注意：不启用 -u (nounset)。conda 的 activate/deactivate 钩子脚本会引用未定义
# 变量（如 _CONDA_PYTHON_SYSCONFIGDATA_NAME_USED），在 set -u 下会中断脚本。
set -Eeo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

ENV_NAME="${ENV_NAME:-anydex}"
PY_VER="${PY_VER:-3.10}"
MAX_JOBS="${MAX_JOBS:-2}"
export MAX_JOBS

log()  { printf '\033[1;36m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup][WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[setup][ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 0. 前置检查
# -----------------------------------------------------------------------------
command -v conda >/dev/null 2>&1 || die "未找到 conda，请先安装 Miniconda/Anaconda。"

# 探测系统 nvcc / 驱动 CUDA 版本
SYS_CUDA=""
if command -v nvcc >/dev/null 2>&1; then
  SYS_CUDA="$(nvcc --version | grep -oP 'release \K[0-9]+\.[0-9]+' || true)"
fi
DRV_CUDA=""
if command -v nvidia-smi >/dev/null 2>&1; then
  DRV_CUDA="$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9]+\.[0-9]+' || true)"
fi
log "系统 nvcc CUDA = ${SYS_CUDA:-未检测到}, 驱动支持 CUDA = ${DRV_CUDA:-未检测到}"

# 探测 GPU 架构 (compute capability) -> TORCH_CUDA_ARCH_LIST
if [[ -z "${TORCH_CUDA_ARCH_LIST:-}" ]]; then
  if command -v nvidia-smi >/dev/null 2>&1; then
    CC="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ' || true)"
    if [[ -n "$CC" ]]; then
      export TORCH_CUDA_ARCH_LIST="$CC"
      log "自动探测 GPU compute capability = $CC -> TORCH_CUDA_ARCH_LIST=$CC"
    fi
  fi
fi
[[ -n "${TORCH_CUDA_ARCH_LIST:-}" ]] || warn "未能探测 GPU 架构，编译将用 nvcc 默认架构（可能不含目标卡）。"
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-}"

# 选择 torch wheel 索引（默认 cu128，适配 Blackwell/RTX50；旧卡可用 cu124/cu121）
if [[ -z "${TORCH_INDEX_URL:-}" ]]; then
  case "${SYS_CUDA:-${DRV_CUDA:-12.8}}" in
    12.8*|12.9*|13.*) TORCH_INDEX_URL="https://download.pytorch.org/whl/cu128" ;;
    12.4*|12.5*|12.6*) TORCH_INDEX_URL="https://download.pytorch.org/whl/cu124" ;;
    12.1*|12.2*|12.3*) TORCH_INDEX_URL="https://download.pytorch.org/whl/cu121" ;;
    11.8*)            TORCH_INDEX_URL="https://download.pytorch.org/whl/cu118" ;;
    *)                TORCH_INDEX_URL="https://download.pytorch.org/whl/cu128" ;;
  esac
fi
TORCH_SPEC="${TORCH_SPEC:-torch torchvision}"

# -----------------------------------------------------------------------------
# 1. 创建 / 复用 conda 环境
# -----------------------------------------------------------------------------
# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"

if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  log "conda 环境 '$ENV_NAME' 已存在，复用。"
else
  log "创建 conda 环境 '$ENV_NAME' (python=$PY_VER) ..."
  conda create -y -n "$ENV_NAME" "python=$PY_VER" cmake ninja openblas openblas-devel git -c conda-forge
fi
conda activate "$ENV_NAME"

# CUDA toolkit（提供 nvcc / cusparse / cudart，供 ME 编译）。
# 若系统已有匹配 nvcc 可设 SKIP_CUDA_TOOLKIT=1 跳过。
if [[ "${SKIP_CUDA_TOOLKIT:-0}" != "1" && -z "$SYS_CUDA" ]]; then
  log "环境内安装 cuda-toolkit（提供 nvcc/cusparse）..."
  CUDA_PKG_VER="${CUDA_PKG_VER:-12.8}"
  conda install -y -c nvidia "cuda-toolkit=${CUDA_PKG_VER}" || \
    warn "conda 安装 cuda-toolkit 失败，请确保系统已有匹配的 CUDA toolkit。"
fi
# 定位 CUDA_HOME
if [[ -z "${CUDA_HOME:-}" ]]; then
  if [[ -x "$CONDA_PREFIX/bin/nvcc" ]]; then
    export CUDA_HOME="$CONDA_PREFIX"
  elif command -v nvcc >/dev/null 2>&1; then
    export CUDA_HOME="$(dirname "$(dirname "$(command -v nvcc)")")"
  fi
fi
log "CUDA_HOME=${CUDA_HOME:-未设置}"

# -----------------------------------------------------------------------------
# 1.5 固定 host 编译器版本（CUDA 12.x 的 nvcc 不接受 gcc>=14；gcc 13 又踩 libstdc++ bug）
# -----------------------------------------------------------------------------
# conda 环境常默认带 gcc 14，导致 nvcc 报
#   "host c++ (14.x) is greater than the maximum required version by CUDA"
# 而 gcc 13.4 的 libstdc++ 又会让 nvcc 在 shared_ptr 处报
#   "more than one instance of overloaded function std::__to_address matches"
# 因此默认固定到 gcc/g++ 12（CUDA 12.x 上最稳）。可用 GXX_VER 覆盖（如 13.*）。
if [[ "${SKIP_COMPILER_PIN:-0}" != "1" ]]; then
  GXX_VER="${GXX_VER:-12.*}"
  log "固定 host 编译器到 gcc/g++ $GXX_VER（CUDA nvcc 要求 < 14，且避开 gcc13 的 __to_address bug）..."
  conda install -y -c conda-forge "gcc_linux-64=$GXX_VER" "gxx_linux-64=$GXX_VER" \
    || warn "安装 gcc/gxx $GXX_VER 失败，CUDA 编译可能报 host 编译器版本过高。"
fi
# 指向 conda 工具链编译器，并设 CUDAHOSTCXX 供 nvcc 使用
_CONDA_CC="$(command -v x86_64-conda-linux-gnu-gcc 2>/dev/null || command -v gcc || true)"
_CONDA_CXX="$(command -v x86_64-conda-linux-gnu-g++ 2>/dev/null || command -v g++ || true)"
[[ -n "$_CONDA_CC"  ]] && export CC="$_CONDA_CC"
[[ -n "$_CONDA_CXX" ]] && export CXX="$_CONDA_CXX" && export CUDAHOSTCXX="$_CONDA_CXX"
log "CC=$CC  CXX=$CXX  ($("${CXX:-g++}" -dumpversion 2>/dev/null || echo '?'))"

# -----------------------------------------------------------------------------
# 2. 安装 PyTorch
# -----------------------------------------------------------------------------
if [[ "${SKIP_TORCH_INSTALL:-0}" != "1" ]]; then
  log "安装 PyTorch: pip install $TORCH_SPEC  (index: $TORCH_INDEX_URL)"
  pip install --upgrade pip
  # shellcheck disable=SC2086
  pip install $TORCH_SPEC --index-url "$TORCH_INDEX_URL"
fi
python - <<'PY'
import torch
print(f"[setup] PyTorch {torch.__version__}  CUDA {torch.version.cuda}  "
      f"available={torch.cuda.is_available()}")
PY

# -----------------------------------------------------------------------------
# 3. 安装纯 Python 依赖
# -----------------------------------------------------------------------------
log "安装 Python 依赖 (requirements-portable.txt) ..."
pip install -r requirements-portable.txt

# -----------------------------------------------------------------------------
# 4. 编译原生扩展（ME / knn / pointnet2 / ur_toolbox / graspnetAPI）
# -----------------------------------------------------------------------------
bash scripts/build_extensions.sh

# -----------------------------------------------------------------------------
# 5. 现场重生成手部 mesh / 点云（替代不进 git 的 18.8G 资产）
# -----------------------------------------------------------------------------
if [[ "${SKIP_MESHGEN:-0}" != "1" ]]; then
  log "现场生成手部 mesh/点云（默认 Inspire、耗时较长）..."
  HANDS="${HANDS:-inspire}" bash scripts/generate_meshes.sh || \
    warn "mesh 生成失败/跳过，可稍后手动运行 scripts/generate_meshes.sh"
fi

# -----------------------------------------------------------------------------
# 6. 权重下载（可选）
# -----------------------------------------------------------------------------
if [[ "${SKIP_WEIGHTS:-0}" != "1" ]]; then
  bash scripts/fetch_weights.sh || warn "权重下载失败/跳过，可稍后手动运行 scripts/fetch_weights.sh"
fi

# -----------------------------------------------------------------------------
# 7. 自检
# -----------------------------------------------------------------------------
log "运行安装自检 ..."
python scripts/verify_install.py

log "完成。使用前请先: conda activate $ENV_NAME"
