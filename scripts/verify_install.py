#!/usr/bin/env python
"""安装自检：验证 PyTorch / CUDA 与全部原生扩展能正常 import 并跑通最小算子。

退出码 0 = 全部通过；非 0 = 有失败项。
"""
import sys

GREEN = "\033[1;32m"
RED = "\033[1;31m"
YELLOW = "\033[1;33m"
RST = "\033[0m"

results = []


def check(name, fn):
    try:
        detail = fn()
        results.append((name, True, detail or ""))
        print(f"{GREEN}[ OK ]{RST} {name}  {detail or ''}")
    except Exception as e:  # noqa: BLE001
        results.append((name, False, repr(e)))
        print(f"{RED}[FAIL]{RST} {name}  ->  {e!r}")


def _torch():
    import torch
    info = (f"torch={torch.__version__} cuda={torch.version.cuda} "
            f"available={torch.cuda.is_available()}")
    if torch.cuda.is_available():
        info += f" gpu={torch.cuda.get_device_name(0)}"
        cc = torch.cuda.get_device_capability(0)
        info += f" cc={cc[0]}.{cc[1]}"
    return info


def _minkowski():
    import torch
    import MinkowskiEngine as ME
    coords = torch.IntTensor([[0, 0, 0], [0, 1, 0], [0, 0, 1]])
    feats = torch.FloatTensor([[1.0], [2.0], [3.0]])
    if torch.cuda.is_available():
        coords = coords.cuda()
        feats = feats.cuda()
    # batched_coordinates 默认在 CPU 上分配；显式指定 device 以与 feats 同后端，
    # 否则 ME 会报 "Features and coordinates must have the same backend."
    bcoords = ME.utils.batched_coordinates([coords], device=feats.device)
    _ = ME.SparseTensor(features=feats, coordinates=bcoords)
    return f"ME={getattr(ME, '__version__', '?')} (SparseTensor built)"


def _knn():
    import torch
    from knn_pytorch import knn_pytorch  # noqa: F401
    return "knn_pytorch imported"


def _pointnet2():
    import pointnet2._ext as _ext  # noqa: F401
    return "pointnet2._ext imported"


def _graspnet():
    import graspnetAPI  # noqa: F401
    return "graspnetAPI imported"


if __name__ == "__main__":
    check("PyTorch / CUDA", _torch)
    check("MinkowskiEngine", _minkowski)
    check("knn", _knn)
    check("pointnet2", _pointnet2)
    check("graspnetAPI", _graspnet)

    failed = [n for n, ok, _ in results if not ok]
    print()
    if failed:
        print(f"{RED}自检失败项: {', '.join(failed)}{RST}")
        print(f"{YELLOW}请查看上方报错。MinkowskiEngine 失败多为 torch API 变更，"
              f"修改 third_party/MinkowskiEngine/src 后重跑 build_extensions.sh。{RST}")
        sys.exit(1)
    print(f"{GREEN}全部自检通过。{RST}")
    sys.exit(0)
