#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""静态自检：多语言资源一致性 + 页面文案接线 + 隐私（本机绝对路径）扫描。

只做静态检查，不需要真机 / SDK。运行：
    python tests/verify_i18n.py

语言目录自动发现：base 打头，其余凡是有 element/string.json 的目录都算一种语言，
新增语言（如 zh_Hant）不需要改本脚本。

检查项：
  1. 各语言与 base 的键集合与顺序完全一致
  2. base 与 zh_CN 取值一致（base 是中文兜底）
  3. 每个键在所有语言里的 %s 占位符数量一致
  4. 代码里 $r('app.string.X') 引用的键都存在
  5. getStringSync($r(...).id, a, b, ...) 传入的实参个数 = 该键的 %s 个数；
     不以 getStringSync 首参形式出现的 $r(...) 是 Resource 直用，占位符必须为 0
  6. pages/ 与 components/ 里没有"漏接线"的硬编码中文界面文案
     （星名/干支/四化/农历月日/时辰等专业术语白名单放行；engine/ 是纯领域层，不扫）
  7. 工程内没有本机绝对路径残留（本脚本自身除外）
"""

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'entry', 'src', 'main', 'resources')
ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')
SELF = os.path.abspath(__file__)

# 紫微斗数专业术语字符：星名 / 干支 / 四化 / 性别 / 农历月日 / 时辰 / 宫位方位。
# 这些是查表键或专有名词，按设计保留中文，不做翻译。
DOMAIN_CHARS = set('甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥'
                   '禄权科忌男女'
                   '正一二三四五六七八九十冬腊初廿三十时'
                   '生年虚岁')  # 导出文案的 [生年X]/N虚岁(年份) 标记，走 hant() 显示层

# 硬编码中文扫描范围：只查 UI 层。engine/ 是排盘领域层，星名/宫名/城市名
# 本来就是中文数据，扫它只会产生噪音。
SCAN_DIRS = ['pages', 'components']

KEY_RE = re.compile(r"\$r\(\s*'app\.string\.([A-Za-z0-9_]+)'")
KEY_SPAN_RE = re.compile(r"\$r\(\s*'app\.string\.[A-Za-z0-9_]+'\s*\)")
CALL_RE = re.compile(r'getStringSync\s*\(')
LIT_RE = re.compile(r"(['\"`])((?:[^'\"`\\\n]|\\.)*?)\1")
SEG_RE = re.compile(r'\$\{[^}]*\}')
# ★ 必须容忍转义双反斜杠：JSON/JSON5 里的 Windows 路径写出来是 C:\\Users\\xxx，
#   只匹配单层 [\\/] 会漏报（build-profile.json5 就因此躲过了检查）。
BAD_PATH_RE = re.compile(r"([A-Za-z]:[\\/]{1,2}(?:Users|Documents|Desktop)[\\/]{1,2})")
# DevEco 自己生成的签名材料路径：那是 IDE 按本机写的，改不了、也不该由我们改。
# 只豁免这一个文件，其余位置（.md/.ets/.py/其他 .json）一律照抓。
PATH_SCAN_EXEMPT = {'build-profile.json5'}

problems = []
notes = []


def discover_langs():
    """base 打头，其余自动发现（按目录名排序），保证新增语言零改动。"""
    langs = [('base', os.path.join(RES, 'base', 'element', 'string.json'))]
    if os.path.isdir(RES):
        for name in sorted(os.listdir(RES)):
            if name == 'base':
                continue
            p = os.path.join(RES, name, 'element', 'string.json')
            if os.path.isfile(p):
                langs.append((name, p))
    return langs


LANGS = discover_langs()


def load(path):
    with io.open(path, encoding='utf-8') as f:
        return json.load(f)['string']


def count_fmt(value):
    return value.count('%s')


def parse_call_args(text, lp):
    """从 '(' 处解析实参列表：顶层逗号切分，正确跳过字符串与嵌套括号。"""
    args = []
    buf = []
    depth = 0
    quote = None
    i = lp
    n = len(text)
    while i < n:
        c = text[i]
        if quote:
            buf.append(c)
            if c == '\\':
                if i + 1 < n:
                    buf.append(text[i + 1])
                    i += 2
                    continue
            elif c == quote:
                quote = None
            i += 1
            continue
        if c in '"\'`':
            quote = c
            buf.append(c)
        elif c in '([{':
            depth += 1
            if depth == 1:
                buf = []
            else:
                buf.append(c)
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                args.append(''.join(buf).strip())
                break
            buf.append(c)
        elif c == ',' and depth == 1:
            args.append(''.join(buf).strip())
            buf = []
        else:
            buf.append(c)
        i += 1
    return args


def ets_files(dirs):
    for d in dirs:
        base = os.path.join(ETS, d)
        for dirpath, _dirs, files in os.walk(base):
            for fn in sorted(files):
                if fn.endswith('.ets'):
                    yield os.path.join(dirpath, fn)


def main():
    data = {}
    order = {}
    for name, path in LANGS:
        if not os.path.isfile(path):
            problems.append('缺少资源文件: %s' % path)
            continue
        arr = load(path)
        data[name] = {s['name']: s['value'] for s in arr}
        order[name] = [s['name'] for s in arr]

    lang_names = [n for n, _p in LANGS if n in data]
    if 'base' not in data or len(lang_names) < 2:
        report()
        return

    base = data['base']
    others = [n for n in lang_names if n != 'base']

    # 1. 键集合 / 顺序
    for name in others:
        if order[name] != order['base']:
            miss = [k for k in order['base'] if k not in order[name]]
            extra = [k for k in order[name] if k not in order['base']]
            problems.append('%-6s 键顺序/集合与 base 不一致 (缺: %s, 多: %s)'
                            % (name, miss or '无', extra or '无'))
    notes.append('语言目录: %s（键数 %d）'
                 % (', '.join(lang_names), len(order['base'])))

    # 2. base 与 zh_CN 取值一致（base 是中文兜底）
    if 'zh_CN' in data:
        zh = data['zh_CN']
        for k in order['base']:
            if k in zh and zh[k] != base[k]:
                problems.append('base 与 zh_CN 取值不同: %s' % k)

    # 3. %s 数量全语言一致
    for k in order['base']:
        n = count_fmt(base[k])
        for name in others:
            table = data[name]
            if k in table and count_fmt(table[k]) != n:
                problems.append('%s 占位符数量不一致: %s (base=%d, %s=%d)'
                                % (name, k, n, name, count_fmt(table[k])))

    # 4/5. 代码引用与实参个数
    used = set()
    all_ets = []
    for dirpath, _dirs, files in os.walk(ETS):
        for fn in files:
            if fn.endswith('.ets'):
                all_ets.append(os.path.join(dirpath, fn))
    all_ets.sort()

    for path in all_ets:
        with io.open(path, encoding='utf-8') as f:
            text = f.read()
        rel = os.path.relpath(path, ROOT)

        # 4. 键存在性
        for m in KEY_RE.finditer(text):
            key = m.group(1)
            used.add(key)
            if key not in base:
                problems.append('%s 引用了不存在的资源键: %s' % (rel, key))

        # 5. 实参个数：getStringSync($r('app.string.X').id, ...)
        consumed = []
        for cm in CALL_RE.finditer(text):
            lp = text.index('(', cm.start())
            args = parse_call_args(text, lp)
            if not args:
                continue                      # key 由变量传入，静态无法判定，跳过
            km = KEY_RE.search(args[0])
            if not km:
                continue
            key = km.group(1)
            # 注意：km 是在 args[0] 这段子串里的偏移，要回到原文重新定位
            # 才能拿到绝对位置（用于"是否被 getStringSync 消费"的判定）
            abs_km = KEY_RE.search(text, lp)
            consumed.append((abs_km.start(), abs_km.end()))
            if key not in base:
                continue
            given = len(args) - 1
            want = count_fmt(base[key])
            if given != want:
                line = text[:cm.start()].count('\n') + 1
                problems.append('%s:%d %s 实参 %d 个 != 占位符 %d 个'
                                % (rel, line, key, given, want))

        # 5b. Resource 直用（Text($r(...)) 之类）的键不能带占位符。
        #     若 $r 是当下拉入的"小写方法"实参（this.chipText($r(...), v) 这类
        #     把 Resource 交给 helper 去格式化的写法），静态看不出实参个数，跳过。
        for sm in KEY_SPAN_RE.finditer(text):
            if any(a <= sm.start() < b for a, b in consumed):
                continue
            caller = re.search(r'([A-Za-z_][A-Za-z0-9_.]*)\s*\(\s*$', text[:sm.start()])
            if caller and caller.group(1).split('.')[-1][:1].islower():
                continue
            key = KEY_RE.search(sm.group(0)).group(1)
            if key in base and count_fmt(base[key]) > 0:
                line = text[:sm.start()].count('\n') + 1
                problems.append('%s:%d %s 当 Resource 直用，但带 %d 个占位符'
                                % (rel, line, key, count_fmt(base[key])))

    # 6. 硬编码中文界面文案（只扫 UI 层）
    for path in ets_files(SCAN_DIRS):
        rel = os.path.relpath(path, ROOT)
        with io.open(path, encoding='utf-8') as f:
            lines = f.readlines()
        for lineno, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('*'):
                continue
            for m in LIT_RE.finditer(line):
                # 模板串里的 ${...} 是代码不是文案，先抠掉
                lit = SEG_RE.sub('', m.group(2))
                cjk = [c for c in lit if '\u4e00' <= c <= '\u9fff']
                if not cjk:
                    continue
                if all(c in DOMAIN_CHARS for c in cjk):
                    continue  # 专业术语，按设计保留中文
                problems.append('%s:%d 疑似漏接线的中文文案: %s'
                                % (rel, lineno, lit))

    # 7. 本机绝对路径（跳过本脚本自身：它的说明文字里就带这个例子）
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ('.git', 'build', '.hvigor',
                                                'oh_modules', '.preview', '.idea')]
        for fn in files:
            if not fn.endswith(('.ets', '.ts', '.json', '.json5', '.py', '.md')):
                continue
            path = os.path.abspath(os.path.join(dirpath, fn))
            if path == SELF or fn in PATH_SCAN_EXEMPT:
                continue
            try:
                with io.open(path, encoding='utf-8') as f:
                    for lineno, line in enumerate(f, 1):
                        if BAD_PATH_RE.search(line):
                            problems.append('%s:%d 残留本机绝对路径'
                                            % (os.path.relpath(path, ROOT), lineno))
            except (UnicodeDecodeError, OSError):
                pass
    if PATH_SCAN_EXEMPT:
        notes.append('本机路径豁免文件(DevEco 自行写入，无法消除): %s'
                     % ', '.join(sorted(PATH_SCAN_EXEMPT)))

    # 未被引用的键（提示，不算失败）
    unused = sorted(k for k in order['base']
                    if k not in used and not k.startswith(('EntryAbility', 'module_', 'app_')))
    if unused:
        notes.append('代码未引用的资源键(%d): %s' % (len(unused), ', '.join(unused)))

    report()


def report():
    for n in notes:
        print('[INFO] ' + n)
    if problems:
        print('')
        for p in problems:
            print('[FAIL] ' + p)
        print('\n结果: FAIL=%d' % len(problems))
        sys.exit(1)
    print('\n结果: 全部通过')


if __name__ == '__main__':
    main()
