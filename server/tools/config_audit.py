#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""config_audit —— 开关表 ↔ 代码对账（10-01；9-30 体检硬问题①的解法）

**病根**：家里的开关太多，而"文档/台账写的上岗键"和"代码里真读的键"会**悄悄分家**——
`desire_engine` 那样"纸上写着是上岗键、代码里零引用"的死开关，能藏好几天
（9-30 体检：`desire_engine`/`outreach_unified`/`grudge_inject`/4 个换嗓遗物 key 全是零引用）。
拨了没反应，且从外面看不出来。

**只读**。扫三样：
  ① config.json 里有、**代码里零引用**的键 → ⚠️ 死开关候选（要么接线、要么删）
  ② 代码里读了、**config.json 与 DEFAULT_CONFIG 都没有**的键 → 靠 `cfg.get(k, default)` 兜底
     （不算错，但"盘面看不见"——9-10 的教训：默认值要落盘可见）
  ③ 两边都在 → ✓

    python3 tools/config_audit.py            # 全表
    python3 tools/config_audit.py --dead     # 只看死开关候选
    python3 tools/config_audit.py --md 分析报告/x.md
"""
import argparse
import io
import json
import os
import re
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.join(BASE, "config.json")
# 只扫生产代码（BASE 下的 py，tools/ 排除）。★ 10-01 扫除修：原先连 tools/ 一起扫，
# 而 tools/make_mechanism_ledger.py 有一张「每个开关→说明」的表——里面列了几乎所有键名，
# 于是**每个键都被判成「被引用」**，`--dead` 恒报（无），9-30 体检依赖它等于没查。
SCAN_DIRS = (BASE,)
SKIP_DIR = ("档案馆", "评测", "tests", "工单", "分析报告", "files", "photos", "tools", "__pycache__")


def _sources():
    """把入口＋srv_*＋各 *_lib.py＋tools/*.py 的源码合并成一份（按文件逐个记，便于定位）。"""
    out = {}
    for root in SCAN_DIRS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIR]
            for fn in filenames:
                if not fn.endswith(".py"):
                    continue
                p = os.path.join(dirpath, fn)
                try:
                    out[os.path.relpath(p, BASE)] = io.open(p, encoding="utf-8").read()
                except Exception:
                    pass
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dead", action="store_true", help="只看死开关候选")
    ap.add_argument("--md", default="", help="另落一份 md")
    a = ap.parse_args()

    cfg = json.load(io.open(CFG, encoding="utf-8"))
    src = _sources()
    print(f"config.json 共 {len(cfg)} 键；扫了 {len(src)} 个 py 文件\n")

    dead, visible, missing = [], [], []
    for k in sorted(cfg):
        # 引用判据：键名以**字符串字面量**出现、且**后面不紧跟 `:`**（排除 dict 定义行）。
        #   这样 `.get("键")` / `["键"]` / `_win_of(cfg, "键", …)`（键名当参数传）都算引用，
        #   而 `DEFAULT_CONFIG = {"键": …}` 的定义行、tools 说明表里的 `"键": "说明"` 都不算。
        #   ★ 10-01 扫除修：原先只要字面出现就算引用（连注释/定义/说明表都算）→ `--dead` 恒空。
        pat = re.compile(r"[\"']%s[\"'](?!\s*:)" % re.escape(k))
        hits = [f for f, t in src.items() if pat.search(t)]
        # 排除"只在本工具自己里出现"
        hits = [h for h in hits if not h.endswith("config_audit.py")]
        if not hits:
            dead.append((k, cfg[k]))
        else:
            visible.append((k, hits))

    # 代码里读了、盘面没有的：**只认"配置口"上的 .get()**（cfg/load_config()/_cfg… 开头），
    # 免得把 dict.get("action") 这类普通字段名也算进来（噪声）
    pat_get = re.compile(
        r"(?:load_config\(\)|cfg|_cfg|_cfg_ro|CFG|config)\.get\(\s*[\"']([A-Za-z_][A-Za-z0-9_]*)[\"']")
    read_keys = set()
    for f, t in src.items():
        if f.endswith("config_audit.py"):
            continue
        read_keys |= set(pat_get.findall(t))
    for k in sorted(read_keys - set(cfg)):
        if k in ("api_key", "port", "bind_host", "model"):   # 老键/别名，盘面上另有名字
            continue
        missing.append(k)

    lines = [f"# 开关表 ↔ 代码对账（{len(cfg)} 键 / {len(src)} 文件）", ""]
    lines.append(f"## ① 死开关候选：config 里有、**代码零引用**（{len(dead)}）")
    for k, v in dead:
        line = f"- ⚠️ `{k}` = `{json.dumps(v, ensure_ascii=False)[:60]}`"
        print(line)
        lines.append(line)
    if not dead:
        print("（无）")
        lines.append("（无）")
    if not a.dead:
        lines.append("")
        lines.append(f"## ② 代码读了、盘面/DEFAULT 都没有（{len(missing)}）——靠 `.get(k, default)` 兜底"
                     "（不算错，但「盘面看不见」）")
        for k in missing:
            print(f"- `{k}`")
            lines.append(f"- `{k}`")
        print()
    if a.md:
        io.open(a.md, "w", encoding="utf-8").write("\n".join(lines) + "\n")
        print(f"→ 已落 {a.md}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
