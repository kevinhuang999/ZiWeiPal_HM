# -*- coding: utf-8 -*-
# QA 专项：带占位符资源的「调用实参个数 vs 资源占位符个数」一致性（防止 getStringSync 抛异常）
import json, os, re, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'element', 'string.json')
ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

with open(RES, 'r', encoding='utf-8') as f:
    base = {it['name']: it['value'] for it in json.load(f)['string']}

ph = re.compile(r'%(?:\d+\$)?[sd]')

def top_args(s):
    depth = 0
    args = []
    cur = ''
    for ch in s:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0:
            args.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        args.append(cur.strip())
    return args

problems = []
checked = 0
for dirpath, _, files in os.walk(ETS):
    for fn in files:
        if not fn.endswith('.ets'):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT)
        with open(p, 'r', encoding='utf-8') as f:
            txt = f.read()
        # 去掉注释，简化
        txt = re.sub(r'//[^\n]*', '', txt)
        # 形如 getStringSync($r('app.string.X').id, a, b)
        for m in re.finditer(r"getStringSync\(\s*\$r\('app\.string\.(\w+)'\)\.id\s*,", txt):
            key = m.group(1)
            start = m.end()
            depth = 1
            i = start
            while i < len(txt) and depth > 0:
                if txt[i] in '([{':
                    depth += 1
                elif txt[i] in ')]}':
                    depth -= 1
                i += 1
            inner = txt[start:i - 1]
            n_args = len(top_args(inner)) + 1  # +1 为第一个参数（资源 id）
            n_ph = len(ph.findall(base.get(key, '')))
            checked += 1
            if n_args != n_ph:
                problems.append((rel, key, n_ph, n_args, base.get(key, '')))

print('已检查 getStringSync 带参调用: %d 处' % checked)
if problems:
    print('!! 实参个数与占位符个数不匹配:')
    for r_, k, a, b, v in problems:
        print('   %s  key=%s  资源占位符=%d  传入实参=%d  资源="%s"' % (r_, k, a, b, v))
else:
    print('实参个数与占位符个数全部匹配: 无异常')

# 另外列出所有含占位符的键，供人工抽查
withph = {k: v for k, v in base.items() if ph.search(v)}
print('含占位符的资源键共 %d 个' % len(withph))
