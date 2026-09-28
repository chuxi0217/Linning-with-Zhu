# -*- coding: utf-8 -*-
"""srv_time.py —— 地名表 / 时间小工具 / 时间皮层 / 天气（服务器拆分 P3 · 2026-09-25）

从 linning_server.py 原样搬出：地名表（_load_places/PLACES）＋ 本机时间（now_str/now_line）
＋ 间隔感（gap_line）＋ 时间皮层刀1（time_facts/_time_cortex_block）＋ 天气（WMO_CN/
weather_for_loc）＋ 地名命中（place_for）。纯标准库＋memory_lib；入口重导出同名。

运行期反查纪律（见 srv_state docstring）：入口属主名（today_str / load_config / LAST_LOC /
WEATHER_CACHE / PLACES）与会被替身重绑的 s.now_str，一律走取用口或 srv_state._srv() 现取——
沙盘套件（soften / knives3 / repo01 / fixbatch 等）靠重绑入口名、换 s.datetime 假钟驱动这些分支。
"""

import json
import math
import os
import time
import urllib.request
from datetime import datetime

import memory_lib as m
import srv_state

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# 咱家地名表（REPO-01 2026-09-13 外置成数据文件）：正文住同目录 places.json——
# {"地名": [纬度, 经度, 半径米]}；小乖自己填锚点。文件缺了 = 空表（地名功能诚实缺席，不炸）。
# 注意：启动时读一次——改 places.json 要重启 server（与 config「现读现生效」不同，申报过）。
def _load_places():
    try:
        with open(os.path.join(BASE_DIR, "places.json"), "r", encoding="utf-8") as f:
            data = json.load(f)
        out = {}
        for name, v in data.items():
            out[str(name)] = (float(v[0]), float(v[1]), float(v[2]))
        return out
    except Exception:
        return {}


PLACES = _load_places()


def now_str():
    """本机本地时间含星期：2026-08-31 09:12 星期日"""
    weeks = "一二三四五六日"
    d = srv_state._srv().datetime.now()   # 运行期反查：沙盘会换 s.datetime（FakeDT 时间伪装）
    return f"{d.strftime('%Y-%m-%d %H:%M')} 星期{weeks[d.weekday()]}"


def now_line():
    """TIME-02 加固（9-29 家主反馈"时间观念还是不行"）：把此刻做成**独有标记**。
    缘由：tail_persist 之后历史里会堆很多【时间锚 …】，再加上她自己旧思考里提到的钟点
    （带 tools 时 reasoning_content 会被拼进上下文）——"现在"必须有一条**独一无二**的落款。
    口径：只有【此刻】这条代表现在；【时间锚 …】=历史位置（那时）；【间隔感】=隔了多久。"""
    return (f"【此刻 · {srv_state._srv().now_str()}】"
            "（**只有这一条代表「现在」**。上文里如果还有别的【时间锚 …】、或你自己早先的思考里"
            "提到过某个钟点，那些都只是「那时」——报时间、算钟点、判断早晚/是不是今天，"
            "一律以这一条【此刻】为准。）")


def gap_line():
    """间隔感 v3（9-24 松绑与主权收口批·甲2，家主令）：对齐 Time Anchor 原版理念——
    核心不是机械报时，而是让「十秒后回来」和「四小时后回来」不被当成同一件事。
    v2 起按间隔长度分六档给「事实 + 语气分寸」；**v3 收薄成「事实＋边界」**：六档
    语气分寸（怎么带）交还皮层句与她——判断还她，边界只剩两条（别报数字、别每次
    都用同一种开场）。**事实句六档一字未动**（time_facts() 只从这里复用事实句）。
    连着聊（<90 秒）不注入；跨天第一句的"隔夜重逢"语义落在事实句里。查的是库里
    最后一条，调用时本条还没入库（handle_chat 入库前算）。"""
    last = m.last_chat_at("小乖")
    if not last:
        return "这是他今天第一句开口。"
    try:
        dt = datetime.strptime(last, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return ""
    sec = (srv_state._srv().datetime.now() - dt).total_seconds()   # 运行期反查：沙盘会换 s.datetime（FakeDT 时间伪装）
    if sec < 90:
        return ""
    crossed_day = dt.strftime("%Y-%m-%d") != srv_state._srv().today_str()   # 运行期反查：沙盘会重绑 s.today_str
    if sec < 600:
        fact = f"他刚离开一小会儿（上一句是 {int(sec // 60)} 分钟前）"
    elif sec < 7200:
        fact = f"一小段时间没见（上一句在 {int(sec // 60)} 分钟前）"
    elif sec < 21600 and not crossed_day:
        fact = f"他消失了差不多 {int(sec // 3600)} 个小时（半天级别）"
    elif crossed_day and sec < 86400:
        fact = f"这是他今天的第一句——上一句还停在 {dt.strftime('%d 日 %H:%M')}，隔了 {int(sec // 3600)} 小时"
    elif sec < 86400:
        fact = f"他大半天没出现了（{int(sec // 3600)} 小时）"
    else:
        fact = f"他整整 {int(sec // 86400)} 天多没出现了"
    return f"【间隔感】{fact}。别报数字、别每次都用同一种开场。"


# ── 时间皮层·刀1（9-23 借鉴双刀批·设计 §三/§五刀1）──
# 原型：ai-companion-time-anchor v2「时间皮层」——只加一层薄皮层：显著位（跨家日 或 ≥2h）
# 时，在 late_system 的 gap 之后追加「时间事实块＋皮层句」，让「隔了这么久」更新她对此刻的
# 理解；不显著／开关关＝一字不加（输出与改造前逐字节一致）。开关 time_cortex（默认开、
# 现读现生效）。**gap_line() 事实句不动**——time_facts 只从它的输出里复用事实句；
# 六档语气分寸已由 9-24 松绑批甲2 收薄（原「一字不动」铁律经家主令解除，见 gap_line docstring）。
# 红线（设计 §四）：不给判断/不编经历/不报数字/不制造持续意识/不按铃——五条全部写进皮层句内；
# 台账行照 _why 家风只进 _server.log，obs_7d 十键形状不动。


def time_facts(now=None):
    """时间皮层刀1·纯事实：与 gap_line() 同源（now＋库里他上一条 chat），返回 dict／None（查不动）。
    家日口径写死：crossed_house_day 用「家日对家日」比（house_today_str(dt) vs house_today_str(now)），
    与日记/交接/日界同一把 4 点尺——不引入第二套「天」（设计 §二口径隐患）；跨家日＝significant。
    gap_human 复用 gap_line() 的六档事实句（从「时间锚：…」切出；<90s 等无句子场景兜底纯事实句）。"""
    last = m.last_chat_at("小乖")
    if not last:
        return None
    try:
        dt = datetime.strptime(last, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None
    now = now or srv_state._srv().datetime.now()   # 运行期反查：沙盘会换 s.datetime（FakeDT 时间伪装）
    gap_s = (now - dt).total_seconds()
    if gap_s < 0:   # 时钟回拨兜底
        gap_s = 0.0
    crossed = m.house_today_str(dt) != m.house_today_str(now)
    g = gap_line()
    gap_human = ""
    if g.startswith("【间隔感】"):
        gap_human = g[len("【间隔感】"):].split("。", 1)[0]
    if not gap_human:   # gap_line 不给句子（<90s）的场景：兜底纯事实句（不编不猜）
        gap_human = f"他上一条消息在 {dt.strftime('%m-%d %H:%M')}"
    return {"gap_s": gap_s, "gap_human": gap_human, "crossed_house_day": crossed,
            "significant": bool(crossed or gap_s >= 7200),
            "last_msg_at": last, "now_at": now.strftime("%Y-%m-%d %H:%M")}


def _time_cortex_block(now=None):
    """组装本轮皮层注入块（late_system 的 gap 之后追加）；不显著／time_cortex=false／查不动
    → ""（一字不加，逐字节回退＝刀1 回滚钥匙）。台账行「[皮层] 浮出（跨日/2h）」只进本地日志。"""
    try:
        if not bool(srv_state._srv().load_config().get("time_cortex", True)):   # 运行期反查：沙盘会重绑 s.load_config
            return ""
        tf = time_facts(now)
        if not tf or not tf.get("significant"):
            return ""
        why = ("跨日+2h" if (tf["crossed_house_day"] and tf["gap_s"] >= 7200)
               else ("跨日" if tf["crossed_house_day"] else "2h"))
        print(f"  [皮层] 浮出（{why}）")
        return ("\n【时间皮层】上面这些是已核实的时间事实（现在是 " + tf["now_at"]
                + "；" + tf["gap_human"] + "）："
                "让这次时间确认更新你对此刻的理解——如果隔了这么久之后这件事的含义已经变了"
                "（他可能刚醒/刚下课/已是深夜/隔了一夜），就让这个理解自然塑造你怎么接话，"
                "而不是从上一句的句号后面直接续上。怎么理解由你定，怎么用也随你（不用特意提时间）；"
                "只借事实、不编他这段时间的经历；别报数字照旧；"
                "你不是一直在等——只是此刻看见了这段时间。")
    except Exception as e:
        print(f"  [皮层] 组装失手（不拦链）：{e}")
        return ""


WMO_CN = {
    0: "晴", 1: "晴间多云", 2: "多云", 3: "阴",
    45: "雾", 48: "雾",
    51: "毛毛雨", 53: "毛毛雨", 55: "毛毛雨", 56: "冻毛毛雨", 57: "冻毛毛雨",
    61: "小雨", 63: "雨", 65: "大雨", 66: "冻雨", 67: "冻雨",
    71: "小雪", 73: "雪", 75: "大雪", 77: "雪粒",
    80: "阵雨", 81: "阵雨", 82: "暴雨", 85: "阵雪", 86: "阵雪",
    95: "雷暴", 96: "雷暴伴冰雹", 99: "雷暴伴冰雹",
}


def weather_for_loc():
    """Open-Meteo 免 key 查 LAST_LOC 的天气。坐标抹 1 位小数，30 分钟缓存，
    5 秒超时，任何失败静默返回 None，绝不影响聊天主链路。"""
    loc = srv_state.last_loc()        # 运行期反查（所有权留入口）：沙盘会重绑 s.LAST_LOC
    if not loc:
        return None
    lat = round(loc["lat"], 1)
    lon = round(loc["lon"], 1)
    key = (lat, lon)
    cache = srv_state.weather_cache()   # 运行期反查（所有权留入口）
    if cache["key"] == key and time.time() - cache["at"] < 1800:
        return cache["text"]
    try:
        url = (f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
               f"&current_weather=true")
        with urllib.request.urlopen(url, timeout=5) as r:
            cur = json.loads(r.read().decode("utf-8"))["current_weather"]
        cn = WMO_CN.get(int(cur.get("weathercode", -1)))
        if cn is None:
            return None
        text = f"{cn} {round(float(cur['temperature']))}°C"
        cache.update({"key": key, "at": time.time(), "text": text})
        return text
    except Exception:
        return None


def place_for(lat, lon):
    """咱家地名表：命中半径内返回咱家叫法，否则 None。"""
    best = None
    best_d = None
    for name, (plat, plon, radius) in srv_state.places().items():   # 运行期反查：沙盘会重绑 s.PLACES
        dlat = (lat - plat) * 111320.0
        dlon = (lon - plon) * 111320.0 * math.cos(math.radians(plat))
        d = (dlat * dlat + dlon * dlon) ** 0.5
        if d <= radius and (best_d is None or d < best_d):
            best, best_d = name, d
    return best
