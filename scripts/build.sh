#!/usr/bin/env bash
# Build entry point, run by Vercel via vercel.json buildCommand.
#
# The app's dataset (~1 MB: encounter tables, items, trainers, sprite sheets and
# route layouts) is NOT committed to this repo. It is regenerated here from the
# pret decompilations, so the repo stays small and the data cannot drift from
# its source.
#
# This commit is a PROBE: it reports what the build image actually provides
# before the real pipeline is wired in. Read the deploy's build logs.

set -uo pipefail
mkdir -p public work

echo "=== environment ==="
echo "pwd:   $(pwd)"
echo "os:    $(uname -srm)"
for c in python3 pip3 git curl node unzip; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '  %-7s %s\n' "$c" "$($c --version 2>&1 | head -1)"
  else
    printf '  %-7s MISSING\n' "$c"
  fi
done

echo
echo "=== Pillow (needed for the sprite sheets) ==="
if command -v pip3 >/dev/null 2>&1; then
  pip3 install --quiet --disable-pip-version-check Pillow 2>&1 | tail -3
  python3 -c "import PIL; print('  Pillow', PIL.__version__)" 2>&1 || echo "  Pillow import FAILED"
else
  echo "  no pip3 - sprite generation would need a Node port"
fi

echo
echo "=== cloning the decompilations ==="
T0=$(date +%s)
if git clone --depth 1 --quiet https://github.com/pret/pokeemerald.git work/pokeemerald 2>&1; then
  echo "  pokeemerald OK   $(du -sh work/pokeemerald | cut -f1)   $(( $(date +%s) - T0 ))s"
else
  echo "  pokeemerald CLONE FAILED"
fi
T1=$(date +%s)
if git clone --depth 1 --quiet https://github.com/pret/pokefirered.git work/pokefirered 2>&1; then
  echo "  pokefirered OK   $(du -sh work/pokefirered | cut -f1)   $(( $(date +%s) - T1 ))s"
else
  echo "  pokefirered CLONE FAILED"
fi

echo
echo "=== a real extraction, to prove the data is readable ==="
python3 - <<'PY' 2>&1 || echo "  extraction FAILED"
import json, os
p = 'work/pokeemerald/src/data/wild_encounters.json'
if os.path.exists(p):
    g = json.load(open(p))['wild_encounter_groups'][0]
    print(f"  {len(g['encounters'])} Hoenn encounter tables parsed")
    r110 = [e for e in g['encounters'] if e['map'] == 'MAP_ROUTE110'][0]
    mons = r110['land_mons']['mons']
    print(f"  Route 110 grass slot 0: {mons[0]['species']} Lv{mons[0]['min_level']}")
else:
    print('  wild_encounters.json not found')
PY

echo
echo "=== disk ==="
df -h . 2>&1 | tail -2

cat > public/index.html <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Encounter Atlas &mdash; build probe</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:16px/1.6 system-ui,sans-serif;max-width:38rem;margin:4rem auto;padding:0 1.25rem;color:#0d2136">
<h1 style="margin-bottom:.25rem">Build probe</h1>
<p style="color:#3f5a76">This deploy exists only to verify the Vercel build environment &mdash;
whether Python, Pillow and git are available, and how long cloning the two Pok&eacute;mon
decompilations takes.</p>
<p style="color:#3f5a76">Check this deployment's <b>Build Logs</b> for the results.
The real atlas replaces this page once the pipeline is confirmed.</p>
</body>
HTML

echo
echo "=== build finished ==="
exit 0
