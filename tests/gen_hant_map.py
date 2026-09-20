#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 engine/HantMap.ets —— 简→繁字符映射表（只含本项目真正会用到的字）。

为什么要脚本生成而不是手写：
  · 手工列 300 个字容易漏，漏一个字就是界面上一个半简半繁的错字。
  · 从源码里真实出现的字符集反推，天然覆盖，且表最小、可审计。

做法：
  1. 扫 engine/ pages/ components/ 下的 .ets，**先剥掉注释**再收集 CJK 字符
     （注释里的字只在注释里出现，收进来只会让表虚胖并引入多义字风险）
  2. 每个字过 zhconv 转繁；只保留「转换后不同」的字
  3. 应用 NO_CONVERT（本领域必须保持原字）
  4. ★幂等性自检：把表作用到已经繁体的 zh_Hant 资源上必须是不动点。
     这是本脚本最重要的一道闸 —— 语境多义字（后→後、才→纔、里→裡）会让
     「繁体模式下把本来正确的繁体字改坏」，只有这条检查能抓到。

运行：python tests/gen_hant_map.py
"""

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')
RES = os.path.join(ROOT, 'entry', 'src', 'main', 'resources')
OUT = os.path.join(ETS, 'engine', 'HantMap.ets')

try:
    from zhconv import convert as _zh
except ImportError:
    sys.exit('缺少 zhconv：pip install zhconv -i https://pypi.tuna.tsinghua.edu.cn/simple')

CJK_RE = re.compile(r'[\u4e00-\u9fff]')
COMMENT_RE = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)

# ── 本领域必须「不转换」的字 ───────────────────────────────────────────
# 简繁是字级映射，有些字语境相关、机器会按最常见义项选错：
#   斗：紫微「斗」数是北斗/南斗，不是「鬥」(争斗)
#   干：天「干」/「干」支，不是「乾」(乾燥)也不是「幹」(幹部)
#   咸：咸池是星名，不是「鹹」(鹹淡)
#   丑：地支「丑」时/丑年，不是「醜」(丑陋)。DI_ZHI/ZHI 数组会直接上界面
#   台：星名「三台」「台辅」+ 城市「台北」，繁体斗数写法就是「台輔」，转「臺」反而错
# 其余多义字由下方幂等性自检兜底，不再靠人肉列举。
NO_CONVERT = set('斗干咸丑台')

SCAN_DIRS = ['engine', 'pages', 'components']


def collect_chars():
    """只扫代码里出现的字（剥注释）—— **刻意不扫资源**。

    判断依据：hant() 只会作用在「代码拼出来的」或「代码常量拼进资源模板的」字符串
    （星名、宫名、十二神、城市名、时辰、农历月名…）。资源文案本身由 zh_Hant 目录
    翻译，根本不需要运行时再转一次。

    反过来把资源的字也收进表是有害的：`lang_hans` 的值「简体中文」是**刻意固定写法**
    （语言名各自用自己那套文字显示，繁体界面里也写作「简体中文」），一旦收了「简/体」，
    任何对它的 hant() 都会把它改成「簡體中文」。本脚本的幂等性自检正是撞到了这一条。

    这张表因此是「代码会出现哪些字」的精确快照：代码里新写了中文常量（或新拼了
    资源模板实参），重跑本脚本即自动纳入，不需要人工维护。"""
    chars = set()
    for d in SCAN_DIRS:
        base = os.path.join(ETS, d)
        for dirpath, _dirs, files in os.walk(base):
            for fn in sorted(files):
                if not fn.endswith(('.ets', '.ts')) or fn == 'HantMap.ets':
                    continue
                with io.open(os.path.join(dirpath, fn), encoding='utf-8') as f:
                    chars.update(CJK_RE.findall(COMMENT_RE.sub('', f.read())))
    return chars


def build_map(chars):
    table = {}
    for c in sorted(chars):
        if c in NO_CONVERT:
            continue
        t = _zh(c, 'zh-hant')
        if len(t) == 1 and t != c:
            table[c] = t
    return table


def check_hant_idempotent(table):
    """表作用到 zh_Hant 资源上必须是不动点。

    返回 [(键, [(原文, 表值, 转换后), ...]), ...]。任何一条都说明表里存在
    语境多义字，会把繁体模式下本来正确的字改坏。"""
    p = os.path.join(RES, 'zh_Hant', 'element', 'string.json')
    if not os.path.isfile(p):
        return None
    bad = []
    with io.open(p, encoding='utf-8') as f:
        for it in json.load(f)['string']:
            v = it['value']
            conv = ''.join(table.get(c, c) for c in v)
            if conv != v:
                diff = [(a, table[a], b) for a, b in zip(v, conv) if a != b]
                bad.append((it['name'], diff))
    return bad


def emit(table):
    lines = [
        '// 本文件由 tests/gen_hant_map.py 生成，请勿手改。',
        '// 重新生成：python tests/gen_hant_map.py',
        '//',
        '// 简→繁字符表，仅收录本项目源码里真实出现的字（表越小越容易人工复核）。',
        '// 语境相关的多义字（斗/干/咸）在生成脚本里被排除，保持原字；',
        '// 生成脚本还会断言「本表作用到繁体资源上是不动点」，防止把繁体字改坏。',
        '//',
        '// 用 Record 而非 Map：ArkTS 对 new Map([[...]]) 的元组推导很挑，',
        '// Record 字面量是本工程已验证可用的写法（见 engine/Constants.ets 的 ganWuXing）。',
        'export const HANT_MAP: Record<string, string> = {',
    ]
    lines.append(',\n'.join('  \'%s\': \'%s\'' % (k, v) for k, v in sorted(table.items())))
    lines.append('};')
    lines.append('')
    return '\n'.join(lines)


# 逐条复核用：引擎 / 页面**从代码里拼出来**的域术语。
# 刻意不收资源专有的词：「紫微斗数」全工程只在资源里（module_desc / slogan /
# md_title）以及 ZiWeiEngine 的文件头注释里出现，运行时由 zh_Hant 直接给出
# 「紫微斗數」，不需要也不应该走 hant()。
TERMS = [
    '命宫', '兄弟', '夫妻', '子女', '财帛', '疾厄', '迁移', '仆役', '官禄', '田宅', '福德', '父母',
    '紫微', '天机', '太阳', '武曲', '天同', '廉贞', '天府', '太阴', '贪狼', '巨门',
    '天相', '天梁', '七杀', '破军',
    '左辅', '右弼', '文昌', '文曲', '天空', '地劫', '天魁', '天钺', '禄存', '擎羊',
    '陀罗', '火星', '铃星', '天马',
    '禄', '权', '科', '忌',
    '庙', '旺', '得', '利', '平', '不', '陷',
    '长生', '沐浴', '冠带', '临官', '帝旺', '衰', '病', '死', '墓', '绝', '胎', '养',
    '博士', '力士', '青龙', '小耗', '将军', '奏书', '飞廉', '喜神', '病符', '大耗', '伏兵', '官府',
    '将星', '攀鞍', '岁驿', '息神', '华盖', '劫煞', '灾煞', '天煞', '指背', '咸池', '月煞', '亡神',
    '天刑', '天姚', '台辅', '封诰', '三台', '八座', '恩光', '天贵', '天官', '天福', '天巫',
    '红鸾', '天喜', '天伤', '天使', '孤辰', '寡宿', '天才', '天寿', '天月', '阴煞',
    '解神', '蜚廉', '破碎', '旬空', '截空', '天德', '天厨',
    '天干', '地支', '干支', '时辰', '阳', '阴', '水二局', '木三局', '金四局', '土五局', '火六局',
    '命主', '身主', '大限', '小限', '流年', '本命', '三方四正',
]


def main():
    chars = collect_chars()
    table = build_map(chars)
    with io.open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(emit(table))
    print('扫描到 CJK 字符 %d 个（已剥注释），其中需要转换 %d 个' % (len(chars), len(table)))
    print('已写入 %s' % os.path.relpath(OUT, ROOT))

    failed = False

    print('')
    print('── 域术语复核：与「除 NO_CONVERT 外逐字转繁」的规格逐条比对 ──')
    # 规格定义：术语里每个字，除 NO_CONVERT 外都必须按 zhconv 转繁。
    # 只要表里漏了任何一个字（例：只在资源里出现过的「數」），这条就会红。
    term_bad = []
    for t in TERMS:
        spec = ''.join(c if c in NO_CONVERT else _zh(c, 'zh-hant') for c in t)
        got = ''.join(table.get(c, c) for c in t)
        if spec != got:
            term_bad.append((t, spec, got))
    if term_bad:
        failed = True
        print('  [FAIL] %d 个术语与规格不符（表里缺字）：' % len(term_bad))
        for t, spec, got in term_bad:
            print('    %-8s 规格 %s  实得 %s' % (t, spec, got))
    else:
        print('  通过：%d 个域术语全部符合规格' % len(TERMS))

    print('')
    print('── 幂等性自检：本表作用于 zh_Hant 文案是否写坏繁体 ──')
    bad = check_hant_idempotent(table)
    if bad is None:
        print('  跳过（未找到 zh_Hant 资源，先跑 gen_zh_hant.py）')
    elif not bad:
        print('  通过：繁体文案经本表转换后完全不变')
    else:
        failed = True
        offenders = set()
        for name, diff in bad:
            for a, b, _c in diff:
                offenders.add('%s->%s' % (a, b))
            print('  [FAIL] %s: %s' % (name, diff))
        print('  修法：把 %s 加进 NO_CONVERT 后重新生成'
              % ', '.join(sorted(offenders)))

    print('')
    if failed:
        print('结果: FAIL（表会把繁体字改坏，必须处理后才能用）')
        sys.exit(1)
    print('结果: 全部通过')


if __name__ == '__main__':
    main()
