"""Bundle the mock runtime + every src/ file + a scenario into one Luau script."""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
scenario = sys.argv[1]
outname = sys.argv[2]
out = ['local API = (function()\n' + (HERE / 'api.luau').read_text() + '\nend)()']
for p in ['rt1.luau', 'rt2.luau', 'rt3.luau', 'rt4.luau']:
    out.append('do end\n' + (HERE / p).read_text())
files = []
for f in sorted((ROOT / 'src').rglob('*.luau')):
    rel = f.relative_to(ROOT).as_posix()
    src = f.read_text()
    assert ']=========]' not in src
    out.append(f'Sim.sources["{rel}"] = [=========[\n' + src + ']=========]')
    files.append(rel)
out.append('Sim.FILES = {' + ', '.join(f'"{x}"' for x in files) + '}')
out.append(pathlib.Path(scenario).read_text())
pathlib.Path(outname).write_text('\n'.join(out))
