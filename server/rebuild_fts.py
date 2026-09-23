# rebuild_fts.py —— 全文检索索引重建（工单 FTS5-01，可重入：跑多少遍结果都一样）
# 用法：
#   python3 rebuild_fts.py            # 对账档：三卷 count 不齐才重建，收藏卷与 favorites/ 不齐才补
#   python3 rebuild_fts.py --force    # 全量档：三卷清了重切重灌 + 收藏卷全量重刷
# 说明：
#   - 索引存在库文件里（FTS5 虚表），跑完不用重启 server，下次查询即生效。
#   - 平时不需要跑：开机 fts_autoheal 已对账自愈；这脚本是手动兜底 + 首次部署可选。
#   - jieba 词典在项目目录（vendor），换机器部署：pip install --target=. jieba 即可复原。
import memory_lib as m
import linning_server as s


def main():
    force = "--force" in __import__("sys").argv
    print(f"库：{m.DB_PATH}")
    if not m.FTS_ENABLED:
        print("❌ 本机 SQLite 没有 FTS5，全文检索未启用——先确认 python3 的 sqlite3 编译了 FTS5。")
        return
    if force:
        counts = m.rebuild_fts()
        print("全量重建完成：" + "、".join(f"{k}卷 {v} 条" for k, v in counts.items()))
    else:
        print(f"对账：{m.fts_autoheal()}")
    moved = s.fts_sync_favorites(force=force)
    print(f"收藏卷对账：同步 {moved} 笔（favorites/ 目录 {len(s.favorites_list())} 张）")
    print("收工。")


if __name__ == "__main__":
    main()
