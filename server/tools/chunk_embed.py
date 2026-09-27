#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M2 块级重嵌（9-27）：把 chunks 表里还没有向量的块，直连嵌入端点批量嵌。
幂等：只嵌缺失（vectors kind='chunk' 里没有的）；可重跑补齐；跑一次即静。

用法：
  python tools/chunk_embed.py [--root <仓库根>] [--yes] [--batch 16]
  --root  不传 = 本脚本上一级（库/配置跟着它走——沙盘试跑传沙盘目录）
  --yes   写生产库的确认钮：目标根是生产路径时，没给 --yes 只干跑报数
纪律：只写 --root 指向的库的 vectors 表；除嵌入端点外不联网。
"""
import argparse
import json
import os
import sys
import time
import urllib.request

# 生产根（双系统，宁拒勿碰家风）：命中且没 --yes → 只干跑
_PROD_ROOTS = ("/media/<you>/<your-volume>/咱家记忆库", "~/咱家记忆库")


def _is_prod(root):
    r = os.path.abspath(root).replace("\\", "/").lower()
    for p in _PROD_ROOTS:
        if ":" in p.split("/")[0] and os.name == "nt":
            if os.path.abspath(p).replace("\\", "/").lower() == r:
                return True
        elif os.path.isabs(p) and os.path.abspath(p).replace("\\", "/").lower() == r:
            return True
    return False


def _embed(texts, base, key, model, timeout=120):
    """OpenAI 兼容 /embeddings 批量嵌（与服务器 _embed_texts 同款；文档侧直嵌、不加查询前缀）。"""
    body = {"model": model, "input": list(texts)}
    req = urllib.request.Request(
        base + "/embeddings", data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return [item["embedding"] for item in data["data"]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--yes", action="store_true", help="写生产库的确认钮")
    ap.add_argument("--batch", type=int, default=16)
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    if _is_prod(root) and not args.yes:
        print(f"  目标根是生产路径（{root}）——加 --yes 才写；本次只报数。")
        return 0

    sys.path.insert(0, root)
    import memory_lib as m   # noqa: E402 —— 跟着 --root 走

    cfg = {}
    try:
        with open(os.path.join(root, "config.json"), encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}
    base = str(cfg.get("embedding_base_url") or "").rstrip("/")
    key = str(cfg.get("embedding_api_key") or "")
    model = str(cfg.get("embedding_model") or "")
    if not (base and key and model):
        sys.exit("  嵌入三件套没配齐（embedding_base_url/api_key/model）")

    con = m._conn()
    c = con.cursor()
    rows = c.execute(
        "SELECT c.id, c.text FROM chunks c WHERE c.id NOT IN "
        "(SELECT ref_id FROM vectors WHERE kind='chunk' AND model=?) ORDER BY c.id",
        (model,)).fetchall()
    con.close()
    print(f"  库：{m.DB_PATH} | 待嵌 {len(rows)} 块（已有向量的不重嵌）")
    if not rows:
        st = m.chunk_stats()
        print(f"  无需重嵌；块盘点：{st['total']} 块 {st['per_type']}")
        return 0

    t0 = time.time()
    done = bad = 0
    for i in range(0, len(rows), args.batch):
        part = rows[i:i + args.batch]
        try:
            vecs = _embed([t[:2000] for _cid, t in part], base, key, model)
        except Exception as e:
            bad += len(part)
            print(f"  第 {i // args.batch + 1} 批嵌入失败：{e}（跳过，重跑补齐）")
            continue
        for (cid, _t), v in zip(part, vecs):
            m.vector_put("chunk", cid, model, v)
        done += len(part)
        if (i // args.batch + 1) % 10 == 0:
            print(f"  进度 {done}/{len(rows)}（{time.time() - t0:.0f}s）")
    print(f"  向量：{done} 条完成（{bad} 条待重跑；模型 {model}）用时 {time.time() - t0:.0f}s")
    st = m.chunk_stats()
    print(f"  块盘点：{st['total']} 块 {st['per_type']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
