# -*- coding: utf-8 -*-
"""
_test_image400.py —— 临时测试脚本：复现 DeepSeek 400 Invalid base64 data，找出及格的构造方式。
军规：不动 linning_server.py / memory_lib.py / config.json 等任何现有文件，纯标准库。
缩放重编码用 Windows 自带 System.Drawing（PowerShell -EncodedCommand，无第三方包）。
跑法：set PYTHONIOENCODING=utf-8 && python _test_image400.py
"""
import base64
import json
import os
import re
import subprocess
import tempfile
import urllib.error
import urllib.request

import linning_server as s

TEXT = "小乖发来一张照片，看看。"


def newest_jpg():
    files = [os.path.join(s.PHOTOS_DIR, f)
             for f in os.listdir(s.PHOTOS_DIR) if f.lower().endswith(".jpg")]
    files.sort(key=os.path.getmtime)
    return files[-1]


def to_dataurl(raw, mime="image/jpeg"):
    return f"data:{mime};base64," + base64.b64encode(raw).decode("ascii")


def build_messages(url_value, with_loc=True):
    """照 handle_chat 实际发给 DeepSeek 的结构原样拼 messages"""
    msgs = [{"role": "system", "content": s.SESSION.system_prompt}]
    if with_loc:
        msgs.append({"role": "system", "content":
            "小乖此刻位置：（位置已隐）（今天 21:05 手机随行自动上报，小乖已授权）。"
            "规则：回答和位置有关的问题时，必须以上面这条坐标为准，并说明它是几点上报的；"
            "不许凭记忆猜位置。话题不涉及位置时，不用主动提坐标。"})
    msgs.append({"role": "user", "content": [
        {"type": "image_url", "image_url": {"url": url_value}},
        {"type": "text", "text": TEXT},
    ]})
    return msgs


def post(cfg, messages):
    """call_deepseek 的逐行克隆（同 endpoint、同 key、同 payload），只多带回 HTTP 状态码"""
    url = cfg["base_url"].rstrip("/") + "/chat/completions"
    payload = json.dumps({
        "model": cfg["model"],
        "messages": messages,
        "stream": False,
    }).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {cfg['api_key']}",
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return -1, repr(e)


def ps_reencode(src, max_edge, fmt):
    """Windows 自带 System.Drawing 缩放+另存，返回临时文件路径"""
    ext = "png" if fmt == "Png" else "jpg"
    dst = os.path.join(tempfile.gettempdir(), f"_zanjia_imgtest_{max_edge}.{ext}")
    ps = f"""
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('{src}')
$scale = [Math]::Min(1.0, {max_edge} / [double][Math]::Max($img.Width, $img.Height))
$w = [Math]::Max(1, [int][Math]::Round($img.Width * $scale))
$h = [Math]::Max(1, [int][Math]::Round($img.Height * $scale))
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($img, 0, 0, $w, $h)
$bmp.Save('{dst}', [System.Drawing.Imaging.ImageFormat]::{fmt})
$g.Dispose(); $bmp.Dispose(); $img.Dispose()
Write-Output ("RESIZED " + $w + "x" + $h)
"""
    cmd = base64.b64encode(ps.encode("utf-16-le")).decode("ascii")
    r = subprocess.run(["powershell", "-NoProfile", "-EncodedCommand", cmd],
                       capture_output=True, text=True, timeout=60)
    print(f"  [System.Drawing] {(r.stdout or r.stderr).strip()}")
    return dst


def trial(cfg, name, url_value, raw_size, with_loc=True):
    print(f"\n===== {name} =====")
    print(f"  图片字节数: {raw_size} | url 字段总长: {len(url_value)} | 开头60字符: {url_value[:60]}")
    code, body = post(cfg, build_messages(url_value, with_loc))
    print(f"  HTTP 状态码: {code}")
    print(f"  返回全文: {body[:1200]}")
    return code


def main():
    cfg = s.load_config()
    if not cfg.get("api_key"):
        print("config.json 里没 key，没法测。")
        return

    photo = newest_jpg()
    with open(photo, "rb") as f:
        raw = f.read()
    print(f"测试照片: {photo}")
    print(f"图片文件大小: {len(raw)} B | JPEG 魔数 FF D8: {raw[:2] == bytes([0xFF, 0xD8])}")

    # ② 基线：handle_chat 原样构造 + 同一个 call_deepseek（同 endpoint、同 key）
    dataurl = to_dataurl(raw)
    print(f"dataURL 总长度: {len(dataurl)} 字符 | 开头60字符: {dataurl[:60]}")
    print("\n===== 基线：原样复现（call_deepseek 本尊） =====")
    reply = s.call_deepseek(cfg, build_messages(dataurl))
    m = re.search(r"HTTP (\d+)", reply)
    print(f"  HTTP 状态码: {m.group(1) if m else '200（成功）'}")
    print(f"  返回全文: {reply[:1200]}")
    if not m:
        print("\n基线居然过了——bug 不在构造方式，收工。")
        return

    # ③ 换构造方式，逐个试，拿到 200 就停
    results = [("基线 dataURL 原图 64369B", "400")]

    code = trial(cfg, "T1 裸 base64（去掉 data: 前缀）",
                 base64.b64encode(raw).decode("ascii"), len(raw))
    results.append(("T1 裸 base64 无前缀", str(code)))
    if code == 200:
        summarize(results, "T1")
        return

    small = ps_reencode(photo, 512, "Jpeg")
    with open(small, "rb") as f:
        raw512 = f.read()
    code = trial(cfg, "T2 系统工具缩到512px重存JPEG → 标准 dataURL",
                 to_dataurl(raw512), len(raw512))
    results.append(("T2 512px 重编码 JPEG + dataURL", str(code)))
    if code == 200:
        summarize(results, "T2")
        return

    code = trial(cfg, "T3 512px dataURL + 只要一条 system（去掉定位 system）",
                 to_dataurl(raw512), len(raw512), with_loc=False)
    results.append(("T3 512px + 单 system", str(code)))
    if code == 200:
        summarize(results, "T3")
        return

    png = ps_reencode(photo, 512, "Png")
    with open(png, "rb") as f:
        rawpng = f.read()
    code = trial(cfg, "T4 512px 重存 PNG + data:image/png 前缀",
                 to_dataurl(rawpng, "image/png"), len(rawpng))
    results.append(("T4 512px PNG + dataURL", str(code)))
    if code == 200:
        summarize(results, "T4")
        return

    summarize(results, None)


def summarize(results, winner):
    print("\n" + "=" * 56)
    print("成绩单：")
    for name, code in results:
        mark = "✅ 及格" if code == "200" else "❌"
        print(f"  {mark} {name} -> HTTP {code}")
    if winner:
        print(f"\n及格版本：{winner}。与不及格版的差异见上面各项开头60字符与字节数。")
    else:
        print("\n全部不及格：这个 endpoint/模型大概率不收 dataURL 图片，与大小/前缀/编码无关。")
    print("=" * 56)


if __name__ == "__main__":
    main()
