#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""旧宅卷·索引脚本（9-27 家主令「向量检索能不能检索旧家记录」）

把《老家的存档》分块产物（tools/chunk_oldhome.py 的 jsonl）灌进旧宅卷：
  ① oldhome_chunks 源表＋fts_oldhome 全文索引（memory_lib.oldhome_put_chunk 顺手挂）
  ② vectors 向量（直连嵌入端点批量嵌——不走 embed_queue，一次灌完；失败可重跑补齐）
跑一次即可；重跑安全（同 file+chunk_no 原地更新、向量覆盖）。运行期没人写这张表。

用法：
  python tools/oldhome_index.py --jsonl <chunks.jsonl> [--root <仓库根>] [--no-embed] [--yes]
  --root  不传 = 本脚本上一级（库/配置跟着它走——沙盘试跑传沙盘目录）
  --yes   写生产库的确认钮：目标根是生产路径时，没给 --yes 只干跑报数
纪律：纯标准库；只写 --root 指向的库；除嵌入端点外不联网；其余文件一律不碰。
建议 server 空闲时跑；跑前先给库拍快照（家里有 auto_snapshot 惯例）。
"""
import argparse
import json
import os
import sys
import time
import urllib.request

# 生产根（双系统，宁拒勿碰家风）：命中且没 --yes → 只干跑
# 生产哨兵（9-29 ⑳ 评审第二批）：原先按**写死的绝对路径**认生产——镜像脱敏会把路径换成占位符，
# 守卫就永不命中（形同虚设，评审实抓）。改认**哨兵文件**：`<root>/.zanjia_prod` 在 = 这份是生产。
# 路径无关（Windows『d:/咱家记忆库』/ Linux『/media/.../咱家记忆库』/ 镜像 / 搬过家都认同一份）；
# 沙盘与演练目录不放这文件即可。哨兵本身 gitignore（每份拷贝各自带，不随仓走）。
PROD_MARK = ".zanjia_prod"


def _is_prod(root):
    try:
        return os.path.exists(os.path.join(os.path.abspath(root), PROD_MARK))
    except OSError:
        return False


def _load_chunks(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


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
    ap.add_argument("--jsonl", required=True)
    ap.add_argument("--no-embed", action="store_true")
    ap.add_argument("--yes", action="store_true", help="写生产库的确认钮")
    ap.add_argument("--batch", type=int, default=16)
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    prod = _is_prod(root)
    chunks = _load_chunks(args.jsonl)
    per_file = {}
    for c in chunks:
        per_file[c["file"]] = per_file.get(c["file"], 0) + 1
    print(f"  分块：{len(chunks)} 块（{args.jsonl}）")
    for f_, n_ in sorted(per_file.items()):
        print(f"    {f_}: {n_} 块")
    if prod and not args.yes:
        print(f"  目标根是生产路径（{root}）——加 --yes 才写；本次只干跑报数。")
        return 0

    sys.path.insert(0, root)
    import memory_lib as m   # noqa: E402 —— 跟着 --root 走
    print(f"  目标库：{m.DB_PATH}")
    m.init_db()

    # ① 源表 + FTS（幂等）
    pairs = []   # (chunk_id, text)
    for c in chunks:
        cid = m.oldhome_put_chunk(c["file"], c["chunk_no"], c.get("turn_from"),
                                  c.get("turn_to"), c["text"])
        pairs.append((cid, str(c["text"])[:2000]))
    print(f"  源表+FTS：{len(pairs)} 块入卷")

    # ② 向量（批量直嵌；失败批次跳过，重跑补齐）
    cfg = {}
    try:
        with open(os.path.join(root, "config.json"), encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}
    base = str(cfg.get("embedding_base_url") or "").rstrip("/")
    key = str(cfg.get("embedding_api_key") or "")
    model = str(cfg.get("embedding_model") or "")
    if args.no_embed or not (base and key and model):
        print("  嵌入：跳过（--no-embed 或三件套没配齐；可稍后重跑不带 --no-embed）")
    else:
        t0 = time.time()
        done = bad = 0
        for i in range(0, len(pairs), args.batch):
            part = pairs[i:i + args.batch]
            try:
                vecs = _embed([t for _cid, t in part], base, key, model)
            except Exception as e:
                bad += len(part)
                print(f"  第 {i // args.batch + 1} 批嵌入失败：{e}（跳过，重跑补齐）")
                continue
            for (cid, _t), v in zip(part, vecs):
                m.vector_put("oldhome", cid, model, v)
            done += len(part)
            if (i // args.batch + 1) % 10 == 0:
                print(f"  嵌入进度 {done}/{len(pairs)}（{time.time() - t0:.0f}s）")
        print(f"  向量：{done} 条完成（{bad} 条待重跑；模型 {model}）用时 {time.time() - t0:.0f}s")

    st = m.oldhome_stats()
    print(f"  旧宅卷盘点：共 {st['total']} 块")
    for f_, n_ in st["per_file"]:
        print(f"    {f_}: {n_} 块")
    return 0


if __name__ == "__main__":
    sys.exit(main())
