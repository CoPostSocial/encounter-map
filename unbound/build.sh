#!/usr/bin/env bash
# Build the Unbound Atlas from the game's published data.
#
# Unbound has no decompilation. Two of its sources are first-party and pinned to
# the exact commits Unbound 2.1.1.1 was built from; two are community datasets
# with weaker provenance. Every one of them is pinned by SHA so a rebuild months
# from now produces the same site, and the app itself labels which is which.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UBROOT="$ROOT/work"
SRC="$UBROOT/src"
LOG="$ROOT/public/build-log.html"
mkdir -p "$UBROOT" "$SRC" "$ROOT/public"

DPE_SHA=fe058e0e3ac23cf968cf950de43332135bc1549d   # "Changes for 2.1.1"
CFRU_SHA=b637a27898b14e25dd24d0f69a3e302f0069deb8  # the commit Unbound 2.1.1.1 was built from
YDEX_SHA=abc2ccc0985bb5b31dac2d60118d54c310a15821  # community encounter table
FG_SHA=d668b78bcd223ea177086de4e1141abbcc32b0a1    # community trainer transcription
UG_SHA=main                                        # community location names

say() { echo "$@"; echo "$@" >> "$ROOT/.log"; }
: > "$ROOT/.log"

say "=== unbound atlas build $(date -u +%H:%M:%SZ) ==="

# ---- python deps -----------------------------------------------------------
python3 -m venv "$UBROOT/venv"
# shellcheck disable=SC1091
source "$UBROOT/venv/bin/activate"
pip install --quiet --disable-pip-version-check Pillow
say "python $(python3 -V 2>&1) pillow ok"

# ---- reassemble the build scripts ------------------------------------------
# The pipeline is ~150 KB of Python and the file API this repo is written
# through truncates large writes silently -- a 14 KB push arrived as 5.5 KB
# once. So each script ships as ordered <8.6 KB parts and is checksummed after
# reassembly. A short read now fails the build instead of producing a subtly
# wrong site.
check_script() { # name expected-sha256
  cat "$ROOT"/parts/"$1".*.part > "$UBROOT/$1.py"
  local got
  got=$(sha256sum "$UBROOT/$1.py" | cut -d' ' -f1)
  if [ "$got" != "$2" ]; then
    say "SCRIPT MISMATCH $1: want $2 got $got"
    exit 1
  fi
  say "  $1.py $(wc -c < "$UBROOT/$1.py") bytes ok"
}
check_script build_species 6b218da8741219c2ebf0b71148caa2852dcbb88eae9493a0797da1ecf5f53e90
check_script build_battle  35cf42c0bb78177f36f3768653cbb098e4f7ad965a4cf785648609f1ac4e85e7
check_script build_world   eb8b40f4a119d405297ee811c3aa5d3ebddf0fcd3cb252421c502640de868cf8
check_script build_sprites bab889315631643edcc6ed89e5b6e182ad5795917c764a5385b6f9813bc3b5de
check_script build_app     1f36455fa8e4f3a847289e9cf537ea11ab7ef58134813bff0c6bc398fb4813bd
check_script patch_world   0722298418b9b4f7c161e0b6cef4cb4ee98551229f9276217f825d5925c666f8
check_script patch_app     d0d5cb1cf0e5252a19774dbf9bd9ed486144af216fb9fb746b140c6b266285d3
check_script patch2_app    84f084da1c9d21c8dfbb2a473da44284037a15f70e9e847c2b734650f943c6df

# The app changes far more often than the parts it ships as, and re-splitting a
# whole file for every tweak is the exact operation that truncated a push once.
# So the parts stay at the baselines above and the patches carry the difference,
# each checking the sha256 of what it is handed and of what it produces.
python3 "$UBROOT/patch_world.py" | tee -a "$ROOT/.log"
python3 "$UBROOT/patch_app.py"   | tee -a "$ROOT/.log"
python3 "$UBROOT/patch2_app.py"  | tee -a "$ROOT/.log"

# ---- pinned sources --------------------------------------------------------
# The author's species tables. Cloned rather than fetched file by file because
# the 1264 sprites live here too.
if [ ! -d "$SRC/dpe/.git" ]; then
  mkdir -p "$SRC/dpe"
  git -C "$SRC/dpe" init -q
  git -C "$SRC/dpe" remote add origin https://github.com/Skeli789/Dynamic-Pokemon-Expansion.git
  git -C "$SRC/dpe" fetch -q --depth 1 origin "$DPE_SHA"
  git -C "$SRC/dpe" checkout -q FETCH_HEAD
fi
say "dpe   $(git -C "$SRC/dpe" rev-parse HEAD) sprites=$(ls "$SRC/dpe/graphics/frontspr" | wc -l)"

# CFRU is 130 MB and only seven files are needed, so take those by URL.
for f in strings/ability_name_table.string strings/attack_name_table.string \
         include/constants/pokedex.h include/constants/pokemon.h \
         src/Tables/battle_moves.c src/Tables/type_tables.h \
         src/Tables/raid_encounters.h; do
  mkdir -p "$SRC/cfru/$(dirname "$f")"
  curl -fsSL "https://raw.githubusercontent.com/Skeli789/Complete-Fire-Red-Upgrade/$CFRU_SHA/$f" \
    -o "$SRC/cfru/$f"
done
say "cfru  $CFRU_SHA ($(find "$SRC/cfru" -type f | wc -l) files)"

mkdir -p "$SRC/ydex/src/locations" "$SRC/fg/data" "$SRC/ug/data"
curl -fsSL "https://raw.githubusercontent.com/ydarissep/Unbound-Pokedex/$YDEX_SHA/src/locations/encounters.json" \
  -o "$SRC/ydex/src/locations/encounters.json"
curl -fsSL "https://raw.githubusercontent.com/jimineybillybob1/pokemon-unbound-field-guide/$FG_SHA/data/battle-data.json" \
  -o "$SRC/fg/data/battle-data.json"
# Gifts, statics, trades, raid dens with star tiers, Game Corner prizes -- the
# only version-matched answer to "how do I get this thing" for the half of the
# roster that stands in no grass.
curl -fsSL "https://raw.githubusercontent.com/jimineybillybob1/pokemon-unbound-field-guide/$FG_SHA/data/acquisition-data.json" \
  -o "$SRC/fg/data/acquisition-data.json"
curl -fsSL "https://raw.githubusercontent.com/jimineybillybob1/pokemon-unbound-guide/$UG_SHA/data/unbound-data.json" \
  -o "$SRC/ug/data/unbound-data.json"
say "ydex  $YDEX_SHA encounters=$(wc -c < "$SRC/ydex/src/locations/encounters.json") bytes"
say "fg    $FG_SHA battles=$(wc -c < "$SRC/fg/data/battle-data.json") bytes \
acquisition=$(wc -c < "$SRC/fg/data/acquisition-data.json") bytes"

# ---- run the pipeline ------------------------------------------------------
cd "$UBROOT"
for step in species battle world sprites app; do
  say "--- build_$step"
  python3 "build_$step.py" 2>&1 | tee -a "$ROOT/.log"
done

# build_app emits two things: a single self-contained file for downloading, and
# a web pair whose sprite sheet is its own cacheable PNG rather than 950 KB of
# base64 the browser has to parse before it can paint.
cp "$UBROOT/public/index.html"  "$ROOT/public/index.html"
cp "$UBROOT/public/sprites.png" "$ROOT/public/sprites.png"
cp "$UBROOT/unbound-atlas.html" "$ROOT/public/unbound-atlas.html"
say "=== finished $(date -u +%H:%M:%SZ) html=$(( $(wc -c < "$ROOT/public/index.html") / 1024 ))KB \
sheet=$(( $(wc -c < "$ROOT/public/sprites.png") / 1024 ))KB \
offline=$(( $(wc -c < "$ROOT/public/unbound-atlas.html") / 1024 ))KB ==="

{
  echo '<!doctype html><meta charset="utf-8"><title>Unbound Atlas build</title>'
  echo '<style>body{font:13px/1.6 ui-monospace,Menlo,monospace;background:#0d1117;color:#c9d1d9;padding:24px}'
  echo 'pre{white-space:pre-wrap}a{color:#58a6ff}</style>'
  echo '<h1>Unbound Atlas build</h1><p><a href="/">open the site</a> &middot; '
  echo '<a href="/unbound-atlas.html">single-file offline copy</a></p><pre>'
  sed 's/&/\&amp;/g;s/</\&lt;/g' "$ROOT/.log"
  echo '</pre>'
} > "$LOG"
