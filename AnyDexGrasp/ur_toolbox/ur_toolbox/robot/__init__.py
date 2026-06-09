try:
    # 完整硬件栈（UR 机械臂 + RealSense 相机 + urx 串口等）。
    from .ur import UR_Camera_Gripper
    __all__ = ['UR_Camera_Gripper', ]
except Exception as _e:  # noqa: BLE001
    # 部署/预处理场景下常缺少真实硬件依赖（pyrealsense2、urx、math3d 等）。
    # 此时仍允许导入本包下的纯几何子模块，例如：
    #   from ur_toolbox.robot.Inspire.InspireHandR_grasp import grasp_types
    import warnings as _warnings
    _warnings.warn(
        "ur_toolbox.robot: UR_Camera_Gripper 不可用（%s）；"
        "硬件相关功能被禁用，仅纯几何子模块可用。" % _e
    )
    UR_Camera_Gripper = None
    __all__ = []