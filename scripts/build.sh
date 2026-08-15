#!/usr/bin/env bash
# Build entry point, run by Vercel via vercel.json buildCommand.
#
# The app's dataset (~1 MB: encounter tables, items, trainers, sprite sheets and
# route layouts) is NOT committed to this repo. It is regenerated here from the
# pret decompilations, so the repo stays small and the data cannot drift from
# its source.
#
# This commit is still a PROBE. Because the deploy logs are not reachable through
# the API scope available to us, the probe writes its own output into the served
# page: fetch the site and you are reading the build log.

set -uo pipefail
mkdir -p public work
LOG=work/probe.txt
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

say "=== environment ==="
say "os:    $(uname -srm)"
for c in python3 pip3 git curl node; do
  if command -v "$c" >/dev/null 2>&1; then
    say "  $(printf '%-7s' "$c") $($c --version 2>&1 | head -1)"
  else
    say "  $(printf '%-7s' "$c") MISSING"
  fi
done

say ""
say "=== Pillow (needed for the sprite sheets) ==="
if command -v pip3 >/dev/null 2>&1; then
  pip3 install --quiet --disable-pip-version-check Pillow >>"$LOG" 2>&1
  if python3 -c "import PIL" 2>/dev/null; then
    say "  Pillow $(python3 -c 'import PIL; print(PIL.__version__)')"
  else
    say "  Pillow UNAVAILABLE - sprite generation would need a Node port"
  fi
else
  say "  no pip3"
fi

say ""
say "=== cloning the decompilations ==="
T0=$(date +%s)
if git clone --depth 1 --quiet https://github.com/pret/pokeemerald.git work/pokeemerald 2>>"$LOG"; then
  say "  pokeemerald   OK   $(du -sh work/pokeemerald | cut -f1)   $(( $(date +%s) - T0 ))s"
else
  say "  pokeemerald   CLONE FAILED"
fi
T1=$(date +%s)
if git clone --depth 1 --quiet https://github.com/pret/pokefirered.git work/pokefirered 2>>"$LOG"; then
  say "  pokefirered   OK   $(du -sh work/pokefirered | cut -f1)   $(( $(date +%s) - T1 ))s"
else
  say "  pokefirered   CLONE FAILED"
fi

say ""
say "=== reading the game data ==="
python3 - >>"$LOG" 2>&1 <<'PY' || say "  extraction FAILED"
import json, os
p = 'work/pokeemerald/src/data/wild_encounters.json'
if os.path.exists(p):
    g = json.load(open(p))['wild_encounter_groups'][0]
    print(f"  {len(g['encounters'])} Hoenn encounter tables parsed")
    r = [e for e in g['encounters'] if e['map'] == 'MAP_ROUTE110'][0]
    m = r['land_mons']['mons'][0]
    print(f"  Route 110 grass slot 0: {m['species']} Lv{m['min_level']}")
    rates = [20,20,10,10,10,10,5,5,4,4,1,1]
    agg = {}
    for i, mon in enumerate(r['land_mons']['mons']):
        agg[mon['species']] = agg.get(mon['species'], 0) + rates[i]
    top = sorted(agg.items(), key=lambda kv: -kv[1])[:3]
    print("  Route 110 top three: " + ", ".join(f"{k.replace('SPECIES_','').title()} {v}%" for k, v in top))
    print(f"  percentages sum to {sum(agg.values())}")
else:
    print('  wild_encounters.json NOT FOUND')
PY

say ""
say "=== disk ==="
df -h . 2>&1 | tail -1 | tee -a "$LOG" >/dev/null
say "$(df -h . 2>&1 | tail -1)"

say ""
say "=== build finished at $(date -u '+%Y-%m-%d %H:%M:%SZ') ==="

# Publish the log as the page, so it can be read without deploy-log access.
{
  cat <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Encounter Atlas - build probe</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:15px/1.6 system-ui,sans-serif;max-width:46rem;margin:3rem auto;padding:0 1.25rem;color:#0d2136;background:#eaf4ff">
<h1 style="margin-bottom:.2rem">Build probe</h1>
<p style="color:#3f5a76;margin-top:0">Verifying that Vercel's build image can regenerate the
atlas dataset from the Pokemon decompilations. Output below is this deploy's own build log.</p>
<pre style="background:#fff;border:2px solid #cddff2;border-radius:12px;padding:1rem 1.25rem;overflow:auto;font:13px/1.55 ui-monospace,monospace">
HTML
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$LOG"
  cat <<'HTML'
</pre>
</body>
HTML
} > public/index.html

exit 0
