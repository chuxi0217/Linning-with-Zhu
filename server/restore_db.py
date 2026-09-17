# restore_db.py —— 咱家全库恢复：恢复前自动再拍一张当前快照防手滑
# 用法：python restore_db.py <快照文件路径>
import os
import shutil
import sys

import snapshot_db

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")


def restore(snap_path):
    if not os.path.exists(snap_path):
        print(f"❌ 快照不存在：{snap_path}")
        return False
    print("恢复前，先给当前库拍一张防手滑：")
    snapshot_db.snapshot()
    shutil.copyfile(snap_path, DB_PATH)
    print(f"✅ 已恢复：{snap_path} → {DB_PATH}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法：python restore_db.py <快照文件路径>")
        sys.exit(1)
    restore(sys.argv[1])
