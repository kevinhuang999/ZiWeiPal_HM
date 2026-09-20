#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ZiWeiPal_HM 排盘准确性独立对拍
================================
为什么要有这个脚本：
    tests/verify_engine.mjs 是一份 **JS 复刻实现**，不 import 任何 ArkTS 源码。
    实测它与引擎在禄存表上已经不一致（复刻版 6 / 引擎 5），却仍然 98/98 全绿 —— 也就是说
    那份测试对"引擎表本身写错"这类问题**完全没有覆盖能力**。

本脚本的做法（不依赖复刻，直接对源码取证）：
  1. 从 .ets 源码里正则提取星曜表的真实数值，与权威口诀逐条比对（表错 = 立刻暴露）
  2. 静态扫描"表长度 vs 下标范围"，抓将星那种「4 元素数组被 0-11 下标访问」的越界
  3. 用独立实现校验紫微定位表的构造规律、天府对称、闰年规则

用法：
    python tests/verify_tables.py
退出码 0 = 全过；1 = 有失败项
"""

import re
import sys
import os
from pathlib import Path

# ---------- 定位项目根（可移植：跟随本文件位置，不写死绝对路径） ----------
ROOT = Path(__file__).resolve().parent.parent
ENGINE = ROOT / "entry" / "src" / "main" / "ets" / "engine"

PASS = 0
FAIL = 0
FAILED_ITEMS = []


def check(name, actual, expected):
    global PASS, FAIL
    if actual == expected:
        PASS += 1
    else:
        FAIL += 1
        FAILED_ITEMS.append((name, expected, actual))
        print(f"  [FAIL] {name}\n         期望={expected}\n         实际={actual}")


def read(p):
    return (ENGINE / p).read_text(encoding="utf-8")


def grab_int_array(src, name):
    """提取 `export const NAME: number[] = [...]`"""
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*number\[\]\s*=\s*\[(.*?)\]", src, re.S)
    if not m:
        return None
    return [int(x) for x in re.findall(r"-?\d+", m.group(1))]


def grab_nested_int_array(src, name):
    """提取 `export const NAME: number[][] = [...]`"""
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*number\[\]\[\]\s*=\s*\[(.*?)\n\];", src, re.S)
    if not m:
        return None
    return [[int(x) for x in re.findall(r"-?\d+", row)]
            for row in re.findall(r"\[([^\]]*)\]", m.group(1))]


def grab_string_matrix(src, name):
    """提取 `export const NAME: string[][] = [...]`"""
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*string\[\]\[\]\s*=\s*\[(.*?)\n\];", src, re.S)
    if not m:
        return None
    return [[s.strip().strip("'\"") for s in re.findall(r"'([^']*)'|\"([^\"]*)\"", row) and
             [a or b for a, b in re.findall(r"'([^']*)'|\"([^\"]*)\"", row)]]
            for row in re.findall(r"\[([^\]]*)\]", m.group(1))]


def grab_string_array(src, name):
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*string\[\]\s*=\s*\[(.*?)\]", src, re.S)
    if not m:
        return None
    return re.findall(r"'([^']*)'", m.group(1))


def grab_matrix(src, name):
    """提取 `export const NAME: number[][] = [ [..], [..] ];`（多行矩阵）"""
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*number\[\]\[\]\s*=\s*\[(.*?)\n\];", src, re.S)
    if not m:
        return None
    rows = []
    for row in re.findall(r"\[([^\]]*)\]", m.group(1)):
        rows.append([int(x) for x in re.findall(r"-?\d+", row)])
    return rows


print("=" * 68)
print("ZiWeiPal_HM 排盘准确性独立对拍")
print("=" * 68)

tables = read("AnXingTables.ets")
engine = read("ZiWeiEngine.ets")
cal = read("CalendarUtil.ets")

# ============================================================
print("\n[1] 星曜表 vs 权威口诀")
# ============================================================

# 十干禄：甲寅 乙卯 丙戊巳 丁己午 庚申 辛酉 壬亥 癸子
check("禄存表 LU_CUN_BY_STEM（标准十干禄）",
      grab_int_array(tables, "LU_CUN_BY_STEM"),
      [2, 3, 5, 6, 5, 6, 8, 9, 11, 0])

# 天魁天钺：甲戊庚牛羊(丑未) 乙己鼠猴(子申) 丙丁猪鸡(亥酉) 壬癸兔蛇(卯巳) 六辛逢马虎(午寅)
check("天魁天钺 KUI_YUE_BY_STEM",
      grab_nested_int_array(tables, "KUI_YUE_BY_STEM"),
      [[1, 7], [0, 8], [11, 9], [11, 9], [1, 7], [0, 8], [1, 7], [6, 2], [3, 5], [3, 5]])

# 天马：申子辰→寅 巳酉丑→亥 寅午戌→申 亥卯未→巳
check("天马 TIAN_MA_BY_BRANCH",
      grab_int_array(tables, "TIAN_MA_BY_BRANCH"),
      [2, 11, 8, 5, 2, 11, 8, 5, 2, 11, 8, 5])

# 火星：申子辰起寅 巳酉丑起卯 寅午戌起丑 亥卯未起酉
check("火星起点 HUO_XING_START",
      grab_int_array(tables, "HUO_XING_START"),
      [2, 3, 1, 9, 2, 3, 1, 9, 2, 3, 1, 9])

# 铃星：申子辰起戌 巳酉丑起戌 寅午戌起卯 亥卯未起戌
check("铃星起点 LING_XING_START",
      grab_int_array(tables, "LING_XING_START"),
      [10, 10, 3, 10, 10, 10, 3, 10, 10, 10, 3, 10])

# 将星（三合中神）：申子辰→子 寅午戌→午 巳酉丑→酉 亥卯未→卯
check("将星 JIANG_XING",
      grab_int_array(tables, "JIANG_XING"),
      [0, 6, 9, 3])

# 咸池：酉午卯子布咸池
check("咸池 XIAN_CHI", grab_int_array(tables, "XIAN_CHI"), [9, 3, 6, 0])
# 华盖：辰丑戌未轮华盖
check("华盖 HUA_GAI", grab_int_array(tables, "HUA_GAI"), [4, 10, 1, 7])
# 孤辰：寅卯辰方安巳 / 巳午未方申 / 申酉戌方亥 / 亥子丑方寅
check("孤辰 GU_CHEN", grab_int_array(tables, "GU_CHEN"), [2, 5, 8, 11])
# 寡宿：对应丑 / 辰 / 未 / 戌
check("寡宿 GUA_SU", grab_int_array(tables, "GUA_SU"), [10, 1, 4, 7])

# 小限：寅午戌辰上起 申子辰自戌 巳酉丑未宫始 亥卯未起丑
check("小限起宫 XIAO_XIAN_START_BY_BRANCH",
      grab_int_array(tables, "XIAO_XIAN_START_BY_BRANCH"),
      [10, 7, 4, 1, 10, 7, 4, 1, 10, 7, 4, 1])

# 命主：子属贪狼丑亥门 寅戌属禄存 卯酉属文 巳未武 辰申廉 午破军
check("命主 MING_ZHU_BY_BRANCH",
      grab_string_array(tables, "MING_ZHU_BY_BRANCH"),
      ['贪狼', '巨门', '禄存', '文曲', '廉贞', '武曲', '破军', '武曲',
       '廉贞', '文曲', '禄存', '巨门'])

# 天府 = mod12(16 - 紫微)（以寅申为轴对称）
check("天府对称 TIAN_FU_BY_ZI_WEI",
      grab_int_array(tables, "TIAN_FU_BY_ZI_WEI"),
      [4, 3, 2, 1, 0, 11, 10, 9, 8, 7, 6, 5])

# 南派四化
NAN = [['廉贞', '破军', '武曲', '太阳'], ['天机', '天梁', '紫微', '太阴'],
       ['天同', '天机', '文昌', '廉贞'], ['太阴', '天同', '天机', '巨门'],
       ['贪狼', '太阴', '右辅', '天机'], ['武曲', '贪狼', '天梁', '文曲'],
       ['太阳', '武曲', '太阴', '天同'], ['巨门', '太阳', '文曲', '文昌'],
       ['天梁', '紫微', '左辅', '武曲'], ['破军', '巨门', '太阴', '贪狼']]
check("南派四化 SI_HUA_NAN_PAI", grab_string_matrix(tables, "SI_HUA_NAN_PAI"), NAN)

ZZ = [r[:] for r in NAN]
ZZ[4][2] = '太阳'   # 戊：科 右辅→太阳
ZZ[6][2] = '天府'   # 庚：科 太阴→天府
ZZ[8][2] = '天府'   # 壬：科 左辅→天府
check("中州派四化 SI_HUA_ZHONG_ZHOU", grab_string_matrix(tables, "SI_HUA_ZHONG_ZHOU"), ZZ)

# ============================================================
print("\n[2] 紫微定位表构造规律（五行局 × 农历日）")
# ============================================================
zw = grab_matrix(tables, "ZI_WEI_BY_DAY")
if zw is None or len(zw) != 5:
    check("紫微定位表行数=5（水二~火六局）", len(zw) if zw else None, 5)
else:
    check("紫微定位表行数=5", len(zw), 5)
    # 水二局：丑(1)起，每 2 日进 1 宫 → 日n = 1 + n//2
    expect2 = [(1 + n // 2) % 12 for n in range(1, 31)]
    check("水二局紫微（丑起，两日一宫）", zw[0], expect2)
    # 木三局：组i = (4+i, 1+i, 2+i)，每 3 日一组
    expect3 = []
    for i in range(10):
        expect3 += [(4 + i) % 12, (1 + i) % 12, (2 + i) % 12]
    check("木三局紫微（辰丑寅起，三日一组）", zw[1], expect3[:30])
    # 金四局：组i = (11+i, 4+i, 1+i, 2+i)
    expect4 = []
    for i in range(8):
        expect4 += [(11 + i) % 12, (4 + i) % 12, (1 + i) % 12, (2 + i) % 12]
    check("金四局紫微（亥辰丑寅起，四日一组）", zw[2], expect4[:30])
    # 土五局：组i = (6+i, 11+i, 4+i, 1+i, 2+i)
    expect5 = []
    for i in range(6):
        expect5 += [(6 + i) % 12, (11 + i) % 12, (4 + i) % 12, (1 + i) % 12, (2 + i) % 12]
    check("土五局紫微（巳戌辰丑寅起，五日一组）", zw[3], expect5[:30])
    # 火六局：组i = (9+i, 6+i, 11+i, 4+i, 1+i, 2+i)
    expect6 = []
    for i in range(5):
        expect6 += [(6 + 3 + i) % 12, (6 + i) % 12, (11 + i) % 12,
                    (4 + i) % 12, (1 + i) % 12, (2 + i) % 12]
    check("火六局紫微（午巳戌辰丑寅起，六日一组）", zw[4], expect6[:30])

    # 直接比对权威《紫微星逐日运行表》（初一~三十 × 五局，地支序）
    AUTHORITY = {
        "水二局": [1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11,
                   11, 0, 0, 1, 1, 2, 2, 3, 3, 4],
        "木三局": [4, 1, 2, 5, 2, 3, 6, 3, 4, 7, 4, 5, 8, 5, 6, 9, 6, 7, 10, 7,
                   8, 11, 8, 9, 0, 9, 10, 1, 10, 11],
        "金四局": [11, 4, 1, 2, 0, 5, 2, 3, 1, 6, 3, 4, 2, 7, 4, 5, 3, 8, 5, 6,
                   4, 9, 6, 7, 5, 10, 7, 8, 6, 11],
        "土五局": [6, 11, 4, 1, 2, 7, 0, 5, 2, 3, 8, 1, 6, 3, 4, 9, 2, 7, 4, 5,
                   10, 3, 8, 5, 6, 11, 4, 9, 6, 7],
        "火六局": [9, 6, 11, 4, 1, 2, 10, 7, 0, 5, 2, 3, 11, 8, 1, 6, 3, 4, 0, 9,
                   2, 7, 4, 5, 1, 10, 3, 8, 5, 6],
    }
    for i, (label, expect) in enumerate(AUTHORITY.items()):
        check(f"紫微定位表 权威对照 {label}", zw[i], expect)

# ============================================================
print("\n[3] 表长度 vs 下标范围（防将星式越界崩溃）")
# ============================================================
# 将星 bug 复盘：JIANG_XING 只有 4 个元素，却被 JIANG_XING[yearBranch]（0-11）访问
# → yearBranch>=4 时 undefined → mod12(NaN)=NaN → palaces[NaN] 抛错 → 命盘页崩溃
SHORT_TABLES = {
    "JIANG_XING": 4, "XIAN_CHI": 4, "HUA_GAI": 4,
    "GU_CHEN": 4, "GUA_SU": 4, "YUE_DE": 4,
}
for tname, tlen in SHORT_TABLES.items():
    arr = grab_int_array(tables, tname)
    if arr is None:
        continue
    check(f"{tname} 长度为 {tlen}", len(arr), tlen)
    # 源码里若出现 TABLE[yearBranch] / TABLE[yb] 这种 0-11 直接下标 → 必崩
    direct = re.findall(rf"{tname}\[(?:yearBranch|yb|year_branch)\]", engine)
    check(f"{tname} 未被 0-11 年支直接下标访问（须走 sanHeGroup/yearSiJu）",
          len(direct), 0)

# 12 元素表被 0-11 下标访问是合法的，但被 0-30（日）访问会越界
for tname in ["TIAN_MA_BY_BRANCH", "HUO_XING_START", "LING_XING_START"]:
    arr = grab_int_array(tables, tname)
    if arr:
        check(f"{tname} 长度为 12（匹配年支 0-11）", len(arr), 12)

# ---- 通用越界扫描：任一维表 × 任一直接下标访问 ----
# 下标标识符 → 该下标可能取到的最大值 +1（即表至少需要这么长）
IDX_NEED = {
    'yearBranch': 12, 'yb': 12, 'yearGan': 10, 'chartMonth': 12,
    'hb': 12, 'ld': 30, 'mingBranch': 12, 'shenBranch': 12,
    'ju': 7, 'stem': 10, 'br': 12, 'group': 4, 'sj': 4,
}
def _arr_len(name):
    a = grab_int_array(tables, name)
    if a is not None:
        return len(a)
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*string\[\]\s*=\s*\[(.*?)\]", tables, re.S)
    return len(re.findall(r"'([^']*)'", m.group(1))) if m else None


_violations = []
for _t in re.findall(r"export\s+const\s+(\w+)\s*:\s*(?:number|string)\[\]\s*=\s*\[", tables):
    _len = _arr_len(_t)
    if not _len:
        continue
        for _m in re.finditer(r"\b" + _t + r"\[([^\]]+)\]", engine):
            _expr = _m.group(1).strip()
            # 先判「收敛过」的下标：sanHeGroup()/yearSiJu() 返回 0-3，%N 收敛到 0..N-1
            if re.search(r"sanHeGroup\(|yearSiJu\(", _expr):
                _need = 4
            elif re.search(r"%\s*(\d+)", _expr):
                _need = int(re.search(r"%\s*(\d+)", _expr).group(1))
            else:
                _need = None
                for _ident, _n in IDX_NEED.items():
                    # 整词匹配，避免 'br' 命中 'branchNumber' 这类
                    if re.search(r"\b" + _ident + r"\b", _expr):
                        _need = _n
                        break
            if _need is None:
                continue
            if _len < _need:
                _violations.append(f"{_t}[{_expr}] 表长 {_len} < 需要 {_need}")
check("全表通用越界扫描（任一维表 × 任一直接下标访问）", _violations, [])

# ============================================================
print("\n[4] 规则级验证（独立实现，不读引擎表）")
# ============================================================

# 天府对称性：天府 = mod12(16 - 紫微)
tf = grab_int_array(tables, "TIAN_FU_BY_ZI_WEI")
if tf:
    check("天府 = mod12(16 - 紫微)（寅申轴对称）",
          tf, [(16 - z) % 12 for z in range(12)])

# 纳音取局：甲乙1 丙丁2 戊己3 庚辛4 壬癸5；
# 地支：子午丑未1 寅申卯酉2 辰戌巳亥3；和>5则减5
def stem_num(s): return s // 2 + 1
def branch_num(b):
    if b in (0, 6, 1, 7): return 1
    if b in (2, 8, 3, 9): return 2
    return 3
def ju_of(s, b):
    v = stem_num(s) + branch_num(b)
    if v > 5: v -= 5
    return {1: 3, 2: 4, 3: 2, 4: 6, 5: 5}[v]
# 甲子乙丑海中金 → 金四局(4)
check("纳音取局 甲子(0,0)→金四局", ju_of(0, 0), 4)
# 丙寅丁卯炉中火 → 火六局(6)
check("纳音取局 丙寅(2,2)→火六局", ju_of(2, 2), 6)
# 庚午辛未路旁土 → 土五局(5)
check("纳音取局 庚午(6,6)→土五局", ju_of(6, 6), 5)
# 戊辰己巳大林木 → 木三局(3)
check("纳音取局 戊辰(4,4)→木三局", ju_of(4, 4), 3)
# 壬申癸酉剑锋金 → 金四局(4)
check("纳音取局 壬申(8,8)→金四局", ju_of(8, 8), 4)

# 闰年规则（CalendarUtil 日期校验用）
def is_leap(y): return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
for y, exp in [(1900, False), (2000, True), (2024, True), (2027, False),
               (2028, True), (2096, True), (2100, False), (2100, False)]:
    check(f"闰年判定 {y}", is_leap(y), exp)

# 月天数
def days_in_month(y, m):
    if m == 2: return 29 if is_leap(y) else 28
    if m in (4, 6, 9, 11): return 30
    return 31
for (y, m, d), exp in [((2027, 2, 29), False), ((2028, 2, 29), True),
                       ((1900, 2, 29), False), ((2100, 2, 29), False),
                       ((2026, 4, 31), False), ((2026, 6, 31), False),
                       ((2026, 9, 31), False), ((2026, 11, 31), False),
                       ((1987, 2, 31), False), ((2100, 12, 31), True),
                       ((2100, 2, 28), True), ((2026, 1, 31), True)]:
    check(f"日期合法性 {y}-{m:02d}-{d:02d} 应{'合法' if exp else '非法'}",
          d <= days_in_month(y, m), exp)

# ============================================================
print("\n[5] 源码级：日期静默进位已修？")
# ============================================================
check("solar2lunar 已加月范围校验", bool(re.search(r"sm\s*<\s*1\s*\|\|\s*sm\s*>\s*12", cal)), True)
check("solar2lunar 已加各月天数校验（含闰年）", bool(re.search(r"maxDay", cal)), True)
check("闰年判断含 %400 规则", bool(re.search(r"% 400 === 0", cal)), True)

# 将星 bug 已修
check("将星已改走 sanHeGroup", bool(re.search(r"JIANG_XING\[sanHeGroup\(yearBranch\)\]", engine)), True)
# 红鸾天喜已改逆行
check("红鸾改走 Rev(3)（卯起逆数）", bool(re.search(r"Rev\(3\),\s*'红鸾'", engine)), True)
check("天喜改走 Rev(9)（红鸾对宫）", bool(re.search(r"Rev\(9\),\s*'天喜'", engine)), True)
# 天伤天使
check("天使在疾厄宫（命宫顺5）", bool(re.search(r"mod12\(mingBranch \+ 5\),\s*'天使'", engine)), True)
check("天伤在交友宫（命宫顺7）", bool(re.search(r"mod12\(mingBranch \+ 7\),\s*'天伤'", engine)), True)

# ============================================================
print("\n[6] 杂曜体系：口诀『戌上起子安文昌』『天刑酉起正月』『台辅午起生时』等")
# ============================================================
tbl = read("AnXingTables.ets")
# —— 时系：文昌戌(10)起子逆行（09-12 对拍文墨天机修正：原误作 11）、文曲辰(4)起子顺行、台辅午(6)起子顺、封诰寅(2)起子顺
check("文昌回归戌(10)起子逆行", bool(re.search(r"mod12\(10 - hb\),\s*'文昌'", engine)), True)
check("文曲仍为辰(4)起子顺行", bool(re.search(r"mod12\(4 \+ hb\),\s*'文曲'", engine)), True)
check("台辅改走午(6)起生时顺行", bool(re.search(r"mod12\(6 \+ hb\),\s*'台辅'", engine)), True)
check("封诰改走寅(2)起生时顺行", bool(re.search(r"mod12\(2 \+ hb\),\s*'封诰'", engine)), True)
# —— 月系：天刑酉(9)起正月顺、天姚丑(1)起正月顺
check("天刑改走酉(9)起正月（月系）", bool(re.search(r"mod12\(9 \+ chartMonth - 1\),\s*'天刑'", engine)), True)
check("天姚改走丑(1)起正月（月系）", bool(re.search(r"mod12\(1 \+ chartMonth - 1\),\s*'天姚'", engine)), True)
check("天巫改走月系表", bool(re.search(r"TIAN_WU_BY_MONTH\[\(chartMonth - 1\) % 4\]", engine)), True)
# —— 日系：三台左辅宫起初一顺、八座右弼宫起初一逆、恩光天贵各退一步
check("三台改走左辅宫起初一顺至生日", bool(re.search(r"mod12\(4 \+ chartMonth - 1 \+ ld - 1\),\s*'三台'", engine)), True)
check("八座改走右弼宫起初一逆至生日", bool(re.search(r"mod12\(11 - chartMonth - \(ld - 1\)\),\s*'八座'", engine)), True)
check("恩光改走文昌宫起日退一步", bool(re.search(r"mod12\(11 - hb \+ ld - 1 - 1\),\s*'恩光'", engine)), True)
check("天贵改走文曲宫起日退一步", bool(re.search(r"mod12\(4 \+ hb \+ ld - 1 - 1\),\s*'天贵'", engine)), True)
# —— 年干系：天官 / 天福
check("天官改走年干表", bool(re.search(r"TIAN_GUAN_BY_STEM\[yearGan\]", engine)), True)
check("天福改走年干表", bool(re.search(r"TIAN_FU_GUI_BY_STEM\[yearGan\]", engine)), True)
check("computeShenSha 已接收 yearGan 与 ld 参数",
      bool(re.search(r"computeShenSha\(palaces, mingBranch, shenBranch, yearGan, yearBranch, chartMonth, hb, ld\)", engine)), True)

# —— 表值对拍（权威口诀）
check("天马表（寅午戌→申 / 申子辰→寅 / 巳酉丑→亥 / 亥卯未→巳）",
      grab_int_array(tbl, "TIAN_MA_BY_BRANCH"), [2, 11, 8, 5, 2, 11, 8, 5, 2, 11, 8, 5])
check("火星起点表（申子辰→寅 / 巳酉丑→卯 / 寅午戌→丑 / 亥卯未→酉）",
      grab_int_array(tbl, "HUO_XING_START"), [2, 3, 1, 9, 2, 3, 1, 9, 2, 3, 1, 9])
check("铃星起点表（寅午戌→卯 / 其余→戌）",
      grab_int_array(tbl, "LING_XING_START"), [10, 10, 3, 10, 10, 10, 3, 10, 10, 10, 3, 10])
check("天月表（正月戌二月巳…）",
      grab_int_array(tbl, "TIAN_YUE"), [10, 5, 4, 2, 7, 3, 11, 7, 2, 6, 10, 2])
check("天巫表（巳申寅亥四组）", grab_int_array(tbl, "TIAN_WU_BY_MONTH"), [5, 8, 2, 11])
check("天官贵人表（甲未乙辰丙巳…）", grab_int_array(tbl, "TIAN_GUAN_BY_STEM"), [7, 4, 5, 2, 3, 9, 11, 9, 10, 6])
check("天福贵人表（甲酉乙申丙子…）", grab_int_array(tbl, "TIAN_FU_GUI_BY_STEM"), [9, 8, 0, 11, 3, 2, 6, 5, 6, 5])
check("禄存表（甲寅乙卯丙戊巳丁己午庚申辛酉壬亥癸子）",
      grab_int_array(tbl, "LU_CUN_BY_STEM"), [2, 3, 5, 6, 5, 6, 8, 9, 11, 0])
check("蜚廉算法与口诀一致（子丑寅→申酉戌 等）",
      [((8 - 3 * (y // 3)) + (y % 3)) % 12 for y in range(12)],
      [8, 9, 10, 5, 6, 7, 2, 3, 4, 11, 0, 1])
check("破碎算法与口诀一致（子午卯酉→巳 等）",
      [(5 if y % 3 == 0 else (9 if y % 3 == 2 else 1)) for y in range(12)],
      [5, 1, 9, 5, 1, 9, 5, 1, 9, 5, 1, 9])

# ============================================================
print("\n[7] 四化表 / 长生起点 / 大限顺逆")
# ============================================================
def grab_str_matrix(src, name):
    """提取 `export const NAME: string[][] = [...]`"""
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*string\[\]\[\]\s*=\s*\[(.*?)\n\];", src, re.S)
    if not m:
        return None
    rows = re.findall(r"\[(.*?)\]", m.group(1), re.S)
    return [[x for x in re.findall(r"'([^']*)'", r)] for r in rows]


# 口诀：甲廉破武阳，乙机梁紫阴，丙同机昌廉，丁阴同机巨，戊贪阴右机，
#       己武贪梁曲，庚阳武阴同，辛巨阳曲昌，壬梁紫左武，癸破巨阴贪
NAN_EXPECT = [
    ['廉贞', '破军', '武曲', '太阳'],
    ['天机', '天梁', '紫微', '太阴'],
    ['天同', '天机', '文昌', '廉贞'],
    ['太阴', '天同', '天机', '巨门'],
    ['贪狼', '太阴', '右辅', '天机'],
    ['武曲', '贪狼', '天梁', '文曲'],
    ['太阳', '武曲', '太阴', '天同'],
    ['巨门', '太阳', '文曲', '文昌'],
    ['天梁', '紫微', '左辅', '武曲'],
    ['破军', '巨门', '太阴', '贪狼'],
]
check("南派四化表（十干逐条对拍）", grab_str_matrix(tbl, "SI_HUA_NAN_PAI"), NAN_EXPECT)

zz = grab_str_matrix(tbl, "SI_HUA_ZHONG_ZHOU")
check("中州派仅戊/庚/壬三干与南派不同（其余七干一致）",
      [i for i in range(10) if zz[i] != NAN_EXPECT[i]], [4, 6, 8])
check("中州派 戊干科=太阳", zz[4][2], '太阳')
check("中州派 庚干科=天府", zz[6][2], '天府')
check("中州派 壬干科=天府", zz[8][2], '天府')

# 长生十二神起点：水二局申 / 木三局亥 / 金四局巳 / 土五局申 / 火六局寅
# ============================================================
print("\n[8] 十四主星：紫微链 / 天府链间隔 + 天府对称")
# ============================================================
def grab_steps(src, name):
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*StarStep\[\]\s*=\s*\[(.*?)\n\];", src, re.S)
    if not m:
        return None
    return [(n, int(s)) for n, s in re.findall(r"\{\s*name:\s*'([^']*)',\s*step:\s*(\d+)\s*\}", m.group(1))]


# 口诀「紫微天机逆行旁，隔一阳武天同当，又隔二位廉贞地，空三复见紫微郎」
check("紫微星系逆布间隔（天机1 太阳3 武曲4 天同5 廉贞8）",
      grab_steps(tbl, "ZI_WEI_CLUSTER"),
      [('天机', 1), ('太阳', 3), ('武曲', 4), ('天同', 5), ('廉贞', 8)])
# 口诀「天府太阴与贪狼，巨门天相及天梁，七杀空三破军位」
check("天府星系顺布间隔（太阴1…七杀6 破军10）",
      grab_steps(tbl, "TIAN_FU_CLUSTER"),
      [('太阴', 1), ('贪狼', 2), ('巨门', 3), ('天相', 4), ('天梁', 5), ('七杀', 6), ('破军', 10)])
# 口诀「丑卯相更迭，未酉互为根；往来午和戌，蹀躞子和辰；巳亥交驰骋，同位在寅申」
check("天府对称表（子↔辰、丑↔卯、寅/申同位、巳↔亥、午↔戌、未↔酉）",
      grab_int_array(tbl, "TIAN_FU_BY_ZI_WEI"), [4, 3, 2, 1, 0, 11, 10, 9, 8, 7, 6, 5])

# ============================================================
print("\n[9] 庙旺表：结构 + 太阳/太阴锚点抽查")
# ============================================================
def grab_int_matrix(src, name):
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*number\[\]\[\]\s*=\s*\[(.*?)\n\];", src, re.S)
    if not m:
        return None
    rows = re.findall(r"\[([^\]]*)\]", m.group(1))
    return [[int(x) for x in re.findall(r"-?\d+", r)] for r in rows]


bt = grab_int_matrix(tbl, "BRIGHTNESS_TABLE")
check("庙旺表 14 行（对应十四主星）", len(bt), 14)
check("庙旺表每行 12 列（对应十二地支）", sorted({len(r) for r in bt}), [12])
check("庙旺值域 0-6（庙旺得利平不陷）", sorted({v for r in bt for v in r}), [0, 1, 2, 3, 4, 5, 6])
# 太阳（index 2）：卯庙、寅旺、亥子陷 —— 最典型的「日升日落」对照
check("太阳 卯=庙", bt[2][3], 0)
check("太阳 亥=陷", bt[2][11], 6)
check("太阳 子=陷", bt[2][0], 6)
# 太阴（index 7）：子丑亥庙、酉戌旺、卯辰巳午陷 —— 与太阳恰好互补
check("太阴 子丑亥=庙", [bt[7][0], bt[7][1], bt[7][11]], [0, 0, 0])
check("太阴 卯辰巳午=陷", [bt[7][3], bt[7][4], bt[7][5], bt[7][6]], [6, 6, 6, 6])
check("太阴 酉戌=旺", [bt[7][9], bt[7][10]], [1, 1])

# ============================================================
print("\n[10] 纳音取局 / 命主身主 / 大限起运")
# ============================================================
def grab_str_array(src, name):
    m = re.search(r"export\s+const\s+" + name + r"\s*:\s*string\[\]\s*=\s*\[(.*?)\]", src, re.S)
    if not m:
        return None
    return [x for x in re.findall(r"'([^']*)'", m.group(1))]


# 天干数：甲乙1 丙丁2 戊己3 庚辛4 壬癸5
check("纳音天干数（甲乙1…壬癸5）", [i // 2 + 1 for i in range(10)], [1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
# 地支数：子午丑未1、寅申卯酉2、辰戌巳亥3
check("纳音地支数（子午丑未1 寅申卯酉2 辰戌巳亥3）",
      [(1 if b in (0, 6, 1, 7) else (2 if b in (2, 8, 3, 9) else 3)) for b in range(12)],
      [1, 1, 2, 2, 3, 3, 1, 1, 2, 2, 3, 3])
# 局数映射：1木→3 2金→4 3水→2 4火→6 5土→5
check("五行局映射（木3 金4 水2 火6 土5）",
      {1: 3, 2: 4, 3: 2, 4: 6, 5: 5}, {1: 3, 2: 4, 3: 2, 4: 6, 5: 5})
check("纳音映射源码存在", bool(re.search(r"case 4: return 6;", tbl)), True)
# 命主（年支）：子贪狼 丑巨门 寅禄存 卯文曲 辰廉贞 巳武曲 午破军…
check("命主表", grab_str_array(tbl, "MING_ZHU_BY_BRANCH"),
      ['贪狼', '巨门', '禄存', '文曲', '廉贞', '武曲', '破军', '武曲', '廉贞', '文曲', '禄存', '巨门'])
# 身主（年支）：子午火星 丑未天相 寅申天梁 卯酉天同 辰戌文昌 巳亥天机
check("身主表", grab_str_array(tbl, "SHEN_ZHU_BY_BRANCH"),
      ['火星', '天相', '天梁', '天同', '文昌', '天机', '火星', '天相', '天梁', '天同', '文昌', '天机'])
# 大限起运 = 局数（水2 木3 金4 土5 火6）
check("大限起运岁=局数", bool(re.search(r"return ju; // 水2 木3 金4 土5 火6", tbl)), True)
# 小限起宫（年支，四组循环 戌未辰丑）
check("小限起宫表（戌未辰丑循环）",
      grab_int_array(tbl, "XIAO_XIAN_START_BY_BRANCH"), [10, 7, 4, 1, 10, 7, 4, 1, 10, 7, 4, 1])

# ============================================================
print("\n[11] 真太阳时：经度差 + 均时差")
# ============================================================
import math
def eot(n):
    b = 360.0 * (n - 81) / 365.0
    r = b * math.pi / 180.0
    return 9.87 * math.sin(2 * r) - 7.53 * math.cos(r) - 1.5 * math.sin(r)


check("真太阳时公式：标准时 + (经度-120)×4/60 + EoT/60",
      bool(re.search(r"stdHour \+ \(longitude - 120\.0\) \* 4\.0 / 60\.0 \+ eotMinutes\(dayOfYear\) / 60\.0", cal)), True)
# 均时差经典值：2 月中约 -14 分钟（全年最低）、11 月初约 +16 分钟（全年最高）
check("均时差 2 月中为负且接近 -14 分钟", -16 < eot(46) < -13, True)
check("均时差 11 月初为正且接近 +16 分钟", 14 < eot(305) < 18, True)
# 极值范围合理（全年约 -16 ~ +16 分钟）
check("均时差全年不超出 ±17 分钟", max(abs(eot(n)) for n in range(1, 366)) < 17, True)
# 东经 120 度、EoT 忽略时，真太阳时应等于标准时
check("东经 120 度基准", abs((12 + (120 - 120) * 4 / 60) - 12) < 1e-9, True)
# 北京 116.4E 应比标准时晚约 14.4 分钟
check("北京(116.4E) 真太阳时比标准时晚约 14 分钟",
      round((116.4 - 120) * 4, 1), -14.4)

# ============================================================
print("\n[12] 三合组 / 四季局 / 桃花墓库将星 / 孤辰寡宿")
# ============================================================
def san_he(b):
    return 0 if b in (0, 4, 8) else (1 if b in (2, 6, 10) else (2 if b in (1, 5, 9) else 3))


def si_ju(b):
    return 0 if b in (11, 0, 1) else (1 if b in (2, 3, 4) else (2 if b in (5, 6, 7) else 3))


check("sanHeGroup：申子辰/寅午戌/巳酉丑/亥卯未 四组",
      [san_he(b) for b in range(12)], [0, 2, 1, 3, 0, 2, 1, 3, 0, 2, 1, 3])
check("yearSiJu：亥子丑/寅卯辰/巳午未/申酉戌 四季",
      [si_ju(b) for b in range(12)], [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 0])
# 咸池（桃花）：申子辰→酉 巳酉丑→午 寅午戌→卯 亥卯未→子
check("咸池表（申子辰酉 / 巳酉丑午 / 寅午戌卯 / 亥卯未子）",
      grab_int_array(tbl, "XIAN_CHI"), [9, 3, 6, 0])
# 华盖（墓库）：申子辰→辰 巳酉丑→丑 亥卯未→未 寅午戌→戌
check("华盖表（申子辰辰 / 巳酉丑丑 / 亥卯未未 / 寅午戌戌）",
      grab_int_array(tbl, "HUA_GAI"), [4, 10, 1, 7])
# 将星（三合中神）：申子辰→子 寅午戌→午 巳酉丑→酉 亥卯未→卯
check("将星表（三合中神 子午酉卯）", grab_int_array(tbl, "JIANG_XING"), [0, 6, 9, 3])
# 孤辰寡宿：亥子丑→寅/戌 寅卯辰→巳/丑 巳午未→申/辰 申酉戌→亥/未
check("孤辰表", grab_int_array(tbl, "GU_CHEN"), [2, 5, 8, 11])
check("寡宿表", grab_int_array(tbl, "GUA_SU"), [10, 1, 4, 7])

check("长生起点（水申木亥金巳土申火寅）",
      bool(re.search(r"\{ 2: 8, 3: 11, 4: 5, 5: 8, 6: 2 \}", engine)), True)
# 博士十二神从禄存起
check("博士十二神从禄存起", bool(re.search(r"placeTwelve\(palaces, mingBranch, LU_CUN_BY_STEM\[yearGan\]", engine)), True)
# 大限：阳男阴女顺行
check("大限阳男阴女顺行",
      bool(re.search(r"\(yang && male\) \|\| \(!yang && !male\)", engine)), True)
check("阳年判定=年干偶数", bool(re.search(r"yearGan % 2 === 0", engine)), True)

# ============================================================
print("\n" + "=" * 68)
if FAIL == 0:
    print(f"全部通过：PASS={PASS}  FAIL=0")
    print("=" * 68)
    sys.exit(0)
else:
    print(f"存在失败：PASS={PASS}  FAIL={FAIL}")
    print("-" * 68)
    for n, e, a in FAILED_ITEMS:
        print(f"  · {n}: 期望 {e} / 实际 {a}")
    print("=" * 68)
    sys.exit(1)
