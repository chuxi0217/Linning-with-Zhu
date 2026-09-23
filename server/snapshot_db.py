# snapshot_db.py —— 咱家全库快照：带时间戳整库复制，打印路径
# 用法：python snapshot_db.py
import os
import shutil
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")


def snapshot():
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dst = os.path.join(BASE_DIR, f"咱家的家_snapshot_{ts}.db")
    shutil.copyfile(DB_PATH, dst)
    print(dst)
    return dst


if __name__ == "__main__":
    snapshot()
