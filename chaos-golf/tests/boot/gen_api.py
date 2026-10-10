import re, json
src = open(__import__('sys').argv[1]).read().split('\n')
classes = {}
enums = {}
enum_list = {}
i = 0
cur = None
in_enum_list = False
hdr = re.compile(r'^declare extern type (\w+)(?: extends (\w+))? with(.*)$')
while i < len(src):
    line = src[i]
    m = hdr.match(line)
    if m:
        name, sup, rest = m.group(1), m.group(2), m.group(3).strip()
        cur = {'Super': sup, 'Props': {}, 'Methods': {}, 'Events': {}, 'Callbacks': {}}
        classes[name] = cur
        if rest == 'end':
            cur = None
        i += 1
        continue
    if line.startswith('type ENUM_LIST = {'):
        in_enum_list = True
        i += 1
        continue
    if in_enum_list:
        s = line.strip()
        if s.startswith('}'):
            in_enum_list = False
        else:
            mm = re.match(r'(\w+): (\w+),?', s)
            if mm:
                enum_list[mm.group(1)] = mm.group(2)
        i += 1
        continue
    if cur is not None:
        s = line.strip()
        if s == 'end':
            cur = None
        elif s.startswith('@'):
            pass
        elif s.startswith('function '):
            mm = re.match(r'function (\w+)\(', s)
            if mm:
                cur['Methods'][mm.group(1)] = True
        else:
            mm = re.match(r'(\w+): (.*)$', s)
            if mm:
                n, t = mm.group(1), mm.group(2)
                if t.startswith('RBXScriptSignal'):
                    cur['Events'][n] = True
                elif '->' in t:
                    cur['Callbacks'][n] = t
                else:
                    cur['Props'][n] = t
    i += 1

def is_instance(n):
    seen = set()
    while n and n not in seen:
        if n == 'Instance':
            return True
        seen.add(n)
        c = classes.get(n)
        n = c['Super'] if c else None
    return False

out = ['return {', 'Classes = {']
def lstr(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
for n, c in classes.items():
    if n in ('Instance', 'Object') or is_instance(n):
        props = ', '.join(f'[{lstr(k)}] = {lstr(v)}' for k, v in c['Props'].items())
        meths = ', '.join(f'[{lstr(k)}] = true' for k in c['Methods'])
        evs = ', '.join(f'[{lstr(k)}] = true' for k in c['Events'])
        cbs = ', '.join(f'[{lstr(k)}] = true' for k in c['Callbacks'])
        sup = lstr(c['Super']) if c['Super'] else 'nil'
        out.append(f'[{lstr(n)}] = {{ Super = {sup}, Props = {{{props}}}, Methods = {{{meths}}}, Events = {{{evs}}}, Callbacks = {{{cbs}}} }},')
out.append('},')
out.append('Enums = {')
for ename, internal in enum_list.items():
    c = classes.get(internal)
    if not c:
        continue
    items = [k for k in c['Props']]
    out.append(f'[{lstr(ename)}] = {{ ' + ', '.join(lstr(x) for x in items) + ' },')
out.append('},')
out.append('}')
open('api.luau', 'w').write('\n'.join(out))
print(len([n for n in classes if is_instance(n)]), 'instance classes;', len(enum_list), 'enums')
