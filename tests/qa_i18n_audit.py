# -*- coding: utf-8 -*-
# QA 专项：i18n 深度静态审计（不修改任何源文件）
# 1) zh/en 键集合是否一致  2) 占位符数量/类型是否一致
# 3) 代码中是否有硬编码中文（非注释）  4) %s 键的动态调用是否与资源匹配
import json, os, re, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'entry', 'src', 'main', 'resources')
ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

def load(p):
    with open(p, 'r', encoding='utf-8') as f:
        data = json.load(f)
    out = {}
    for it in data.get('string', []):
        out[it['name']] = it['value']
    return out

base = load(os.path.join(RES, 'base', 'element', 'string.json'))
zh = load(os.path.join(RES, 'zh_CN', 'element', 'string.json'))
en = load(os.path.join(RES, 'en_US', 'element', 'string.json'))

print('键数 base=%d zh_CN=%d en_US=%d' % (len(base), len(zh), len(en)))

miss_en = [k for k in base if k not in en]
miss_zh = [k for k in base if k not in zh]
print('en 缺失键: %s' % (miss_en if miss_en else '无'))
print('zh 缺失键: %s' % (miss_zh if miss_zh else '无'))

# 占位符一致性
ph = re.compile(r'%(\d+\$)?[sd]')
prob = []
for k in base:
    b, z, e = base[k], zh.get(k, ''), en.get(k, '')
    if len(ph.findall(b)) != len(ph.findall(z)) or len(ph.findall(b)) != len(ph.findall(e)):
        prob.append((k, b, z, e))
print('占位符数量不一致的键: %s' % (prob if prob else '无'))

# en 是否残留中文
cn_re = re.compile(r'[\u4e00-\u9fff]')
en_cn = [(k, v) for k, v in en.items() if cn_re.search(v)]
print('en_US 中残留中文的键(%d):' % len(en_cn))
for k, v in en_cn:
    print('   - %s = %s' % (k, v))

# 代码中硬编码中文（剔除注释行与字符串资源引用）
hard = []
for dirpath, _, files in os.walk(ETS):
    for fn in files:
        if not fn.endswith('.ets'):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT)
        with open(p, 'r', encoding='utf-8') as f:
            for i, line in enumerate(f, 1):
                s = line.strip()
                if s.startswith('//') or s.startswith('*') or s.startswith('/*'):
                    continue
                # 去掉行尾注释
                code = line
                idx = code.find('//')
                if idx >= 0:
                    code = code[:idx]
                for m in cn_re.finditer(code):
                    # 允许的情况：无
                    hard.append((rel, i, line.rstrip()))
                    break
print('代码中含中文字符的非注释行(%d 处):' % len(hard))
seen = set()
for rel, i, txt in hard:
    key = (rel, i)
    if key in seen:
        continue
    seen.add(key)
    print('   %s:%d  %s' % (rel, i, txt.strip()[:120]))

# 代码中引用的所有 $r('app.string.xxx')
used = set()
for dirpath, _, files in os.walk(ETS):
    for fn in files:
        if not fn.endswith('.ets'):
            continue
        p = os.path.join(dirpath, fn)
        with open(p, 'r', encoding='utf-8') as f:
            txt = f.read()
        for m in re.finditer(r"app\.string\.([A-Za-z0-9_]+)", txt):
            used.add(m.group(1))
undefined = sorted([k for k in used if k not in base])
print('代码引用但资源中未定义的键: %s' % (undefined if undefined else '无'))
