#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成繁体（zh_Hant）资源 —— ZiWeiPal_HM
======================================
从 base/element/string.json 转出繁体版，保证：
  1. 键序与 base 完全一致（鸿蒙要求）
  2. %s 占位符原样保留
  3. 术语修正：紫微斗数的「斗」是北斗南斗，繁体写作「斗」而非「鬥」
     （zhconv 会误转成「鬥數」，必须改回来）

可移植：路径跟随本文件位置；依赖 zhconv（缺了就提示安装命令，不写死解释器路径）。
用法：python tests/gen_zh_hant.py
"""

import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "entry" / "src" / "main" / "resources"
SRC = RES / "base" / "element" / "string.json"
DST_DIR = RES / "zh_Hant" / "element"
DST = DST_DIR / "string.json"

try:
    import zhconv
except ImportError:
    print("缺少依赖 zhconv，请先安装：")
    print("  pip install zhconv -i https://pypi.tuna.tsinghua.edu.cn/simple")
    sys.exit(1)

# 术语修正表：zhconv 的通用转换在紫微斗数语境下是错的，这里改回来。
# 紫微斗数的「斗」指北斗/南斗，繁体与简体同形，不能变成「鬥」（争斗）。
FIXES = {
    "鬥數": "斗數",
    "鬥君": "斗君",
    "北鬥": "北斗",
    "南鬥": "南斗",
    # 台湾习惯的几处用词（字符转换不会改，手工补）
    "設置": "設定",
}

# 语言名按「自身文字」书写是通行做法（iOS/Android 都这样）：
# 「简体中文」与「繁體中文」这两个选项名在四种语言里保持同一写法，
# 否则用户在繁体界面里会看到被转成「簡體中文」的简体选项，反而认不出来。
SKIP_KEYS = {"lang_hans", "lang_hant"}


def to_hant(s: str) -> str:
    out = zhconv.convert(s, "zh-hant")
    for a, b in FIXES.items():
        out = out.replace(a, b)
    return out


def main() -> int:
    data = json.load(io.open(SRC, encoding="utf-8"))
    items = data["string"]

    changed = 0
    out_items = []
    for it in items:
        v = it["value"]
        nv = v if it["name"] in SKIP_KEYS else to_hant(v)
        if nv != v:
            changed += 1
        out_items.append({"name": it["name"], "value": nv})

    DST_DIR.mkdir(parents=True, exist_ok=True)
    with io.open(DST, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"string": out_items}, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # 校验：键序一致、占位符数量一致
    src_names = [x["name"] for x in items]
    dst_names = [x["name"] for x in out_items]
    assert src_names == dst_names, "键序不一致！"

    bad = []
    for a, b in zip(items, out_items):
        if a["value"].count("%s") != b["value"].count("%s"):
            bad.append(a["name"])

    print(f"生成 {DST.relative_to(ROOT)}")
    print(f"  键数 {len(out_items)}，其中 {changed} 个值发生变化")
    print(f"  键序与 base 一致：是")
    print(f"  %s 占位符数量不一致的键：{bad if bad else '无'}")

    # 打印含「斗」的键，便于人工复核
    print("  含「斗」的键（人工复核用）：")
    for it in out_items:
        if "斗" in it["value"] or "鬥" in it["value"]:
            print(f"    {it['name']} = {it['value']}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
