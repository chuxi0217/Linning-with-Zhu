# -*- coding: utf-8 -*-
"""srv_state.py —— 服务器拆分 · 地基（2026-09-25「服务器拆分」批 · P1）

职责：给搬家出去的 srv_* 件一个**运行期反查入口模块**的针脚（_srv），以及共享态取用口。
为什么这么做：沙盘 52 套测试里有 274 处猴补丁（s.call_deepseek= / s.ASLEEP= / s.load_config= …）——
搬家件若在 import 期取入口引用，补丁就失效；运行期反查则补丁照旧有效。

纪律（照家里 lib 家风）：
- 本模块绝不许 import linning_server（循环）；只做针脚与取用口，不做重绑镜像。
- 入口两态都对：直跑（__main__）与 import（linning_server）——直跑时入口会把
  sys.modules.setdefault("linning_server", sys.modules["__main__"])，两态可统一反查。
- fail-open：查不到入口时抛 RuntimeError（搬家件都在链上，查不到=真错，早炸早修）。
"""

import sys


def _srv():
    """反查入口模块（linning_server 优先，其次 __main__）。"""
    m = sys.modules.get("linning_server")
    if m is not None:
        return m
    m = sys.modules.get("__main__")
    if m is not None and hasattr(m, "load_config"):
        return m
    raise RuntimeError("srv_state: 找不到入口模块（linning_server/__main__）")


# ── 共享态取用口（所有权一律留入口；测试猴补丁照旧打在 linning_server 上）──

def asleep():
    return bool(_srv().ASLEEP)


def last_loc():
    return _srv().LAST_LOC


def session():
    return _srv().SESSION


def places():
    return _srv().PLACES


def weather_cache():
    return _srv().WEATHER_CACHE

