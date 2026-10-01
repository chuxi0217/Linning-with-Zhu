# -*- coding: utf-8 -*-
"""srv_push.py —— Push Kit 门铃（服务器拆分 P4 · 2026-09-25）

从 linning_server.py 原样搬出：PS256 手写签名（_b64url/_der_tlv/_pkcs8_to_rsa_nd/_mgf1_sha256/
_ps256_sign）＋ JWT（get_push_jwt）＋ V3 推送（send_push/notify_letter）
。10-01：打卡念叨（gen_checkin_nags）已整只撤；`_he_present`（在场感知）也已删（9-30 删枷锁后零调用）。
纯标准库（军规：不装第三方包）＋memory_lib；入口重导出同名（心跳 / 收信 / 园子 / 工具照旧引用）。

运行期反查纪律（见 srv_state docstring）：notify_letter 读入口的 ASLEEP（沙盘 23 处重绑）、
get_push_jwt 读 PUSH_SA_FILE——一律走 srv_state 取用口/_srv() 现取。
"""

import base64
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime

import memory_lib as m
import srv_state

# ── Push Kit 门铃（9-2 #13）：outbox 来新信 → 锁屏弹通知（标题「咱家」正文「姐姐找你」） ──
# 鉴权（V3 只认服务账号 JWT，client_credentials 换的 token 稳定吃 80200001）：
# 服务账号密钥文件由小乖从 API Console 下载存本目录 push_service_account.json（值不打印不落日志）。
# PS256 = RSASSA-PSS(SHA256) 纯标准库手写——军规不装第三方包（PyJWT/cryptography 都不用）。
PUSH_PROJECT_ID = "<推送项目ID>"
PUSH_SA_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "push_service_account.json")
PUSH_SEND_URL = f"https://push-api.cloud.huawei.com/v3/{PUSH_PROJECT_ID}/messages:send"
PUSH_JWT_CACHE = {"jwt": None, "exp": 0}   # JWT 缓存，过期前 5 分钟重签


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _der_tlv(buf, pos):
    """读一个 DER TLV：返回 (tag, value_bytes, next_pos)。"""
    tag = buf[pos]
    pos += 1
    length = buf[pos]
    pos += 1
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(buf[pos:pos + n], "big")
        pos += n
    return tag, buf[pos:pos + length], pos + length


def _pkcs8_to_rsa_nd(pem_text):
    """PKCS#8 PEM → RSA (n, d) 整数。标准库手写 ASN.1 解析。"""
    b64 = "".join(line for line in pem_text.strip().splitlines()
                  if not line.startswith("-----"))
    der = base64.b64decode(b64)
    # PrivateKeyInfo ::= SEQUENCE { version, algorithm, OCTET STRING privateKey }
    tag, body, _ = _der_tlv(der, 0)
    if tag != 0x30:
        raise ValueError("密钥文件不是 PKCS#8 DER")
    _t, _v, p = _der_tlv(body, 0)            # version
    _t, _v, p = _der_tlv(body, p)            # algorithm
    tag, key_der, _ = _der_tlv(body, p)      # privateKey
    if tag != 0x04:
        raise ValueError("PKCS#8 里没找到私钥")
    # RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, dp, dq, qinv }
    tag, body, _ = _der_tlv(key_der, 0)
    _t, _v, p = _der_tlv(body, 0)            # version（进新一层，偏移归零）
    _t, n_b, p = _der_tlv(body, p)           # n
    _t, e_b, p = _der_tlv(body, p)           # e
    _t, d_b, p = _der_tlv(body, p)           # d
    return int.from_bytes(n_b, "big"), int.from_bytes(d_b, "big")


def _mgf1_sha256(seed, length):
    """MGF1-SHA256 掩码生成函数。"""
    out = b""
    counter = 0
    while len(out) < length:
        out += hashlib.sha256(seed + counter.to_bytes(4, "big")).digest()
        counter += 1
    return out[:length]


def _ps256_sign(message, n, d):
    """RSASSA-PSS(SHA256, 32 字节随机盐) 签名（RFC 8017 EMSA-PSS-ENCODE + RSASP1）。"""
    k = (n.bit_length() + 7) // 8
    em_bits = n.bit_length() - 1
    em_len = (em_bits + 7) // 8            # 2048 位模数 → 256
    m_hash = hashlib.sha256(message).digest()
    salt = os.urandom(32)
    h = hashlib.sha256(b"\x00" * 8 + m_hash + salt).digest()
    ps = b"\x00" * (em_len - 32 - 32 - 2)
    db = ps + b"\x01" + salt
    db_mask = _mgf1_sha256(h, em_len - 32 - 1)
    masked_db = bytearray(a ^ b for a, b in zip(db, db_mask))
    masked_db[0] &= (0xFF >> (8 * em_len - em_bits))   # 左边多余位清零
    em = bytes(masked_db) + h + b"\xbc"
    s = pow(int.from_bytes(em, "big"), d, n)
    return s.to_bytes(k, "big")


def get_push_jwt():
    """读服务账号密钥文件 → 纯标准库签 PS256 JWT。缓存复用。失败返回 None。"""
    now = int(time.time())
    if PUSH_JWT_CACHE["jwt"] and now < PUSH_JWT_CACHE["exp"]:
        return PUSH_JWT_CACHE["jwt"]
    try:
        with open(srv_state._srv().PUSH_SA_FILE, encoding="utf-8") as f:   # 运行期反查：沙盘会重绑 s.PUSH_SA_FILE
            sa = json.load(f)
        n, d = _pkcs8_to_rsa_nd(sa["private_key"])
        header = {"kid": sa["key_id"], "typ": "JWT", "alg": "PS256"}
        payload = {"iss": sa["sub_account"],
                   "aud": "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
                   "iat": now, "exp": now + 3600}
        signing_input = (_b64url(json.dumps(header, separators=(",", ":")).encode()) + "."
                         + _b64url(json.dumps(payload, separators=(",", ":")).encode())).encode()
        jwt = signing_input.decode() + "." + _b64url(_ps256_sign(signing_input, n, d))
        PUSH_JWT_CACHE["jwt"] = jwt
        PUSH_JWT_CACHE["exp"] = now + 3300
        return jwt
    except OSError:
        print("  [push] 服务账号密钥文件不在（push_service_account.json），门铃跳过")
        return None
    except Exception as e:
        print(f"  [push] JWT 签名失败：{e}")
        return None


def send_push(title="咱家", body="姐姐找你"):
    """V3 场景化推送（push-type 0 = Alert 通知消息；testMessage=false＝正式口径）。
    失败只打日志不抛炸（推送是门铃，不能砸主流程）。返回成功与否。"""
    device_token = m.get_push_token()
    if not device_token:
        print("  [push] 还没登记设备 token（app 还没开过门？），门铃跳过")
        return False
    auth = get_push_jwt()
    if not auth:
        return False
    payload = json.dumps({
        "payload": {
            "notification": {
                "category": "IM",                       # 即时聊天类，咱家场景
                "title": title,
                "body": body,
                "clickAction": {"actionType": 0},       # 点击=打开应用首页
            }
        },
        "target": {"token": [device_token]},
        # 10-02 摘调测口径：官方文档「正式上架需 testMessage=false」；测试消息每项目每天限 1000 条，
        # 家里用量远不到，但这是生产路径，不留调测开关。
        "pushOptions": {"testMessage": False},
    }).encode("utf-8")
    req = urllib.request.Request(PUSH_SEND_URL, data=payload, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {auth}",
        "push-type": "0",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode("utf-8"))
        ok = str(result.get("code")) in ("0", "80000000")   # V3 成功码 80000000
        print(f"  [push] 门铃{'按响' if ok else '没响'}：{result.get('code')} {result.get('msg', '')}")
        return ok
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")[:200]
        print(f"  [push] 推送 HTTP {e.code}：{err_body}")
        return False
    except Exception as e:
        print(f"  [push] 推送失败：{e}")
        return False


def notify_letter():
    """outbox 来新信时的门铃：睡着了不吵他（asleep 不推）；
    自测沙盘（ZANJIA_TEST=1）也绝不按真门铃——2026-09-08 晚自测预演出的缺口，堵死。"""
    if os.environ.get("ZANJIA_TEST"):
        print("  [push] 自测模式，门铃不按（真手机收不到）")
        return
    if srv_state.asleep():   # 运行期反查（所有权留入口）：沙盘会重绑 s.ASLEEP
        print("  [push] 小乖睡着了，门铃不按")
        return
    send_push("咱家", "姐姐找你")


# （10-01 大扫除批⑤：`_he_present` 删——9-30 删枷锁后**已无生产调用**（只在测试替身里出现）；
#   要问「他在场吗」请用 `desire_lib._he_present`，那是同款独立实现。）


