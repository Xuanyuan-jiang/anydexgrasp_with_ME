# AnyDexGrasp Portable

把 **AnyDexGrasp**（多指抓取检测）+ 改动过的 **MinkowskiEngine** 打包成一个
可跨机器移植的仓库：`git clone` 之后只需运行 **一个脚本** `setup_env.sh`，
即可根据目标机的 CUDA / PyTorch 自动建环境并重新编译全部原生扩展。

> 设计目标：自动化 ~90%。MinkowskiEngine 在全新的 PyTorch / CUDA 组合上首次
> 编译，**仍可能需要手工补几处源码 API**（详见下文「已知风险」）。

---

## 目录结构

```
anydexgrasp_portable/
├── setup_env.sh                # ① 一键入口：建 conda 环境 → 装 torch → 编译 → 自检
├── environment.yml             # conda 基础环境（python + cudatoolkit + blas）
├── requirements-portable.txt   # 纯 Python 依赖（去掉 numpy 硬钉）
├── scripts/
│   ├── assemble_repo.sh        # 从源工作区拷贝 AnyDexGrasp / MinkowskiEngine 进来（首次打包用）
│   ├── build_extensions.sh     # 编译 MinkowskiEngine / knn / pointnet2 / ur_toolbox
│   ├── generate_meshes.sh      # 现场重生成手部 mesh/点云（替代不进 git 的 18.8G）
│   ├── fetch_weights.sh        # 下载模型权重（logs/，不进 git）
│   └── verify_install.py       # import + CUDA 可用性自检
├── AnyDexGrasp/                # 由 assemble_repo.sh 填充（已 .gitignore logs/build）
└── third_party/
    └── MinkowskiEngine/        # 改动过的 ME，由 assemble_repo.sh 填充
```

---

## 首次打包（在当前开发机上执行一次）

```bash
cd anydexgrasp_portable
bash scripts/assemble_repo.sh   # 把 AnyDexGrasp + MinkowskiEngine 拷进来（排除 logs/build/缓存）
git init && git add -A && git commit -m "init portable anydexgrasp"
git remote add origin <your-repo-url>
git push -u origin main
```

> 模型权重（`AnyDexGrasp/logs/`）体积大，**不纳入 git**，由 `fetch_weights.sh` 在
> 目标机上拉取，或手动放置。
>
> 手部 mesh/点云（`generate_mesh_and_pointcloud/*/meshes/source{,_pointclouds}`，
> 共 18.8G）也**不进 git**；它们是可再生成产物，生成输入（Link STL / Excel / URDF）
> 会随仓库保留，目标机用 `generate_meshes.sh` 现场生成。

---

## 在目标机上部署（RTX 50 系 / Blackwell sm_120 示例）

```bash
git clone <your-repo-url> && cd anydexgrasp_portable

# 一键：建 conda 环境 anydex → 装 PyTorch 2.7+cu128 → 编译全部扩展 → 自检
bash setup_env.sh

# 可选参数：
#   ENV_NAME=anydex            conda 环境名
#   PY_VER=3.10                python 版本
#   TORCH_SPEC="torch==2.7.0"  指定 torch 版本
#   TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128
#   TORCH_CUDA_ARCH_LIST=12.0  目标 GPU 架构（留空则自动探测）
例：
ENV_NAME=anydex TORCH_CUDA_ARCH_LIST=12.0 bash setup_env.sh
```

完成后：

```bash
conda activate anydex
python scripts/verify_install.py     # 应全部打印 OK
```

### 手部 mesh/点云现场生成（18.8G 不进 git）

`setup_env.sh` 默认会自动调用生成（仅 Inspire 手）。如需手动或生成其他手：

```bash
bash scripts/generate_meshes.sh                          # 仅 Inspire（目标手）
HANDS="inspire dh3 allegro" bash scripts/generate_meshes.sh   # 全部
```

输出到 `AnyDexGrasp/generate_mesh_and_pointcloud/<hand>_urdf/meshes/{source,source_pointclouds}`，
运行期由 `InspireHandR_grasp.py` 等读取。跳过可用 `SKIP_MESHGEN=1 bash setup_env.sh`。

---

## CUDA / 架构对照（务必匹配）

| GPU 架构 | 代表显卡 | `TORCH_CUDA_ARCH_LIST` | 最低 CUDA |
|---|---|---|---|
| Ampere | RTX 30 系 | `8.6` | 11.1 |
| Ada | RTX 40 系 | `8.9` | 11.8 |
| Hopper | H100/H200 | `9.0` | 12.0 |
| **Blackwell** | **RTX 50 系 (5070 Ti)** | **`12.0`** | **12.8** |

> Blackwell（sm_120）**必须** CUDA 12.8 + PyTorch 2.7+cu128，CUDA 12.4 不支持。

---

## 已知风险（重点看 MinkowskiEngine）

`knn` 和 `pointnet2` 用 PyTorch 官方 `cpp_extension`，自动跟随当前 torch ABI，
跨版本基本无障碍。

**MinkowskiEngine 是唯一的硬骨头**：官方 v0.5.4 不能在 PyTorch ≥ 2.0 上原生编译。
本仓库内置的是已打补丁版本。若目标机 torch 更新（如 2.7），可能出现新的 API 报错：

- `THC/THC.h` 头文件缺失 → 改用 `ATen/cuda/CUDAContext.h`
- `at::cuda::getCurrentCUDAStream` / `c10::cuda` API 变更
- `torch::Tensor.type()` 弃用 → `.scalar_type()`
- `AT_CHECK` → `TORCH_CHECK`

遇到时按编译报错逐处修改 `third_party/MinkowskiEngine/src/*.cu|*.cpp|*.hpp`，
然后重跑 `bash scripts/build_extensions.sh`。
