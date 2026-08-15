#!/usr/bin/env bash
# Build entry point, run by Vercel via vercel.json buildCommand.
#
# The dataset (~1 MB: encounter tables, items, trainers, sprite sheets, route
# layouts) is not committed. It is regenerated here from the pret
# decompilations, so the repo stays small and the data cannot drift.
#
# Probe 2. Vercel's system Python is managed by uv and refuses `pip install`,
# so this tries several routes to Pillow and reports which one takes.
# The probe writes its own output into the served page, because deploy logs
# are not reachable through the API scope available to us.

set -uo pipefail
mkdir -p public work
LOG=work/probe.txt
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

PY=python3

say "=== environment ==="
say "os:     $(uname -srm)"
say "python: $(python3 --version 2>&1)"
say "node:   $(node --version 2>&1)"
say "uv:     $(command -v uv >/dev/null 2>&1 && uv --version 2>&1 || echo 'not present')"

say ""
say "=== getting Pillow ==="
have_pillow() { "$PY" -c "import PIL" >/dev/null 2>&1; }

# 1. a virtualenv sidesteps the uv-managed system install entirely
if ! have_pillow; then
  if python3 -m venv work/venv >>"$LOG" 2>&1; then
    work/venv/bin/pip install --quiet --disable-pip-version-check Pillow >>"$LOG" 2>&1
    if work/venv/bin/python -c "import PIL" >/dev/null 2>&1; then
      PY=work/venv/bin/python
      say "  venv          OK  Pillow $($PY -c 'import PIL; print(PIL.__version__)')"
    else
      say "  venv          pip install failed"
    fi
  else
    say "  venv          could not be created"
  fi
fi

# 2. uv is what manages this Python, so ask it directly
if ! "$PY" -c "import PIL" >/dev/null 2>&1 && command -v uv >/dev/null 2>&1; then
  uv pip install --system --quiet Pillow >>"$LOG" 2>&1
  if python3 -c "import PIL" >/dev/null 2>&1; then
    PY=python3
    say "  uv --system   OK  Pillow $(python3 -c 'import PIL; print(PIL.__version__)')"
  else
    say "  uv --system   failed"
  fi
fi

# 3. last resort: override the external-management guard
if ! "$PY" -c "import PIL" >/dev/null 2>&1; then
  pip3 install --quiet --break-system-packages Pillow >>"$LOG" 2>&1
  if python3 -c "import PIL" >/dev/null 2>&1; then
    PY=python3
    say "  break-system  OK  Pillow $(python3 -c 'import PIL; print(PIL.__version__)')"
  else
    say "  break-system  failed"
  fi
fi

if "$PY" -c "import PIL" >/dev/null 2>&1; then
  say "  -> using interpreter: $PY"
else
  say "  -> NO PILLOW. Sprite sheets will need a Node port (pngjs)."
fi

say ""
say "=== cloning the decompilations ==="
T0=$(date +%s)
git clone --depth 1 --quiet https://github.com/pret/pokeemerald.git work/pokeemerald 2>>"$LOG" \
  && say "  pokeemerald   OK  $(du -sh work/pokeemerald | cut -f1)  $(( $(date +%s) - T0 ))s" \
  || say "  pokeemerald   FAILED"
T1=$(date +%s)
git clone --depth 1 --quiet https://github.com/pret/pokefirered.git work/pokefirered 2>>"$LOG" \
  && say "  pokefirered   OK  $(du -sh work/pokefirered | cut -f1)  $(( $(date +%s) - T1 ))s" \
  || say "  pokefirered   FAILED"

say ""
say "=== sprite test: can we decode and recolour a real sprite? ==="
"$PY" - >>"$LOG" 2>&1 <<'PY' && say "  sprite pipeline OK" || say "  sprite pipeline FAILED"
from PIL import Image
import os

d = 'work/pokeemerald/graphics/pokemon/zigzagoon'
src = Image.open(os.path.join(d, 'front.png'))
ls = open(os.path.join(d, 'normal.pal')).read().split('\n')
n = int(ls[2])
pal = [tuple(int(v) for v in ls[3 + i].split()) for i in range(n)]
flat = [c for rgb in pal for c in rgb]
img = src.copy()
img.putpalette(flat + [0] * (768 - len(flat)))
rgba = img.convert('RGBA')
px, sp = rgba.load(), src.load()
for y in range(64):
    for x in range(64):
        if sp[x, y] == 0:
            px[x, y] = (0, 0, 0, 0)
os.makedirs('public', exist_ok=True)
rgba.save('public/zigzagoon.png')
print('  wrote public/zigzagoon.png', os.path.getsize('public/zigzagoon.png'), 'bytes')
PY

say ""
say "=== reading the game data ==="
"$PY" - >>"$LOG" 2>&1 <<'PY' || say "  extraction FAILED"
import json
g = json.load(open('work/pokeemerald/src/data/wild_encounters.json'))['wild_encounter_groups'][0]
print(f"  {len(g['encounters'])} Hoenn encounter tables")
k = json.load(open('work/pokefirered/src/data/wild_encounters.json'))['wild_encounter_groups'][0]
lg = [e for e in k['encounters'] if e['base_label'].endswith('_LeafGreen')]
print(f"  {len(lg)} LeafGreen encounter tables")
r = [e for e in g['encounters'] if e['map'] == 'MAP_ROUTE110'][0]
rates = [20,20,10,10,10,10,5,5,4,4,1,1]
agg = {}
for i, mon in enumerate(r['land_mons']['mons']):
    agg[mon['species']] = agg.get(mon['species'], 0) + rates[i]
top = sorted(agg.items(), key=lambda kv: -kv[1])[:3]
print("  Route 110: " + ", ".join(f"{a.replace('SPECIES_','').title()} {b}%" for a, b in top)
      + f"  (sums to {sum(agg.values())})")
PY

say ""
say "=== finished $(date -u '+%H:%M:%SZ') ==="

{
  cat <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Encounter Atlas - build probe 2</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:15px/1.6 system-ui,sans-serif;max-width:46rem;margin:3rem auto;padding:0 1.25rem;color:#0d2136;background:#eaf4ff">
<h1 style="margin-bottom:.2rem">Build probe 2</h1>
<p style="color:#3f5a76;margin-top:0">Checking that Vercel's build image can regenerate the
atlas dataset, including sprite sheets. Output below is this deploy's own build log.</p>
<pre style="background:#fff;border:2px solid #cddff2;border-radius:12px;padding:1rem 1.25rem;overflow:auto;font:13px/1.55 ui-monospace,monospace">
HTML
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$LOG"
  cat <<'HTML'
</pre>
<p style="color:#3f5a76">If the sprite test passed, a real decoded sprite is here:
<a href="/zigzagoon.png">zigzagoon.png</a></p>
</body>
HTML
} > public/index.html

exit 0
