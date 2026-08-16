#!/usr/bin/env bash
# Build entry point, run by Vercel via vercel.json buildCommand.
#
# The atlas regenerates itself from the pret decompilations on every deploy:
# clone pokeemerald and pokefirered, walk their wild-encounter, item, trainer
# and tileset data, and assemble a single self-contained index.html. Nothing
# derived is committed, so the data can never drift from its source.
#
# scripts/payload/*.b64 is a gzipped tar of the extractors and the app
# generator, split into parts small enough to travel through the GitHub API one
# call at a time. Their names sort into the order they must be concatenated
# in. The result is checksummed and unpacked here.
#
# That tarball is the frozen baseline. Every change since arrives as a unified
# diff in scripts/patches/, applied in filename order -- a few KB per change
# instead of re-sending the whole payload.
#
# Diagnostics for every run land at /build-log.html on the deployed site.

set -uo pipefail
ROOT=$(pwd)
mkdir -p public work
LOG=work/build.txt
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

# This site's own production URL. The previous deploy is where the inlined fonts
# are recovered from, and it is the safety net that keeps the app served if
# generation ever fails. Google Fonts covers the fonts if it is unreachable.
CURRENT_BUILD="https://encounter-map-blue.vercel.app/"
PAYLOAD_SHA256="db1e6ac35353e3fe20e39c9a1538c52547be8caac7738ea5d76734a83d7de7d1"
export CURRENT_BUILD

say "=== toolchain ==="
say "os:     $(uname -srm)"
say "python: $(python3 --version 2>&1)"
say "node:   $(node --version 2>&1)"

say ""
say "=== python env ==="
PY=python3
if python3 -m venv work/venv >>"$LOG" 2>&1; then
  work/venv/bin/pip install --quiet --disable-pip-version-check Pillow >>"$LOG" 2>&1
  if work/venv/bin/python -c "import PIL" >/dev/null 2>&1; then
    PY="$ROOT/work/venv/bin/python"
    say "  Pillow $("$PY" -c 'import PIL; print(PIL.__version__)') in venv"
  fi
fi
[ "$PY" = "python3" ] && say "  Pillow unavailable - sprite extraction will fail" || true

say ""
say "=== payload ==="
cat scripts/payload/part*.b64 2>/dev/null \
  | tr -d '[:space:]' | base64 -d > work/payload.tgz 2>>"$LOG"
GOT=$(sha256sum work/payload.tgz 2>/dev/null | cut -d' ' -f1)
if [ "$GOT" = "$PAYLOAD_SHA256" ]; then
  say "  sha256 ok      $(du -h work/payload.tgz | cut -f1)"
  if tar xzf work/payload.tgz -C scripts 2>>"$LOG"; then
    # Vercel's image has no patch(1), so apply_patch.py does the job.
    for p in scripts/patches/*.patch; do
      [ -f "$p" ] || continue
      if (cd scripts && "$PY" apply_patch.py "../$p") >>"$LOG" 2>&1; then
        say "  patched        $(basename "$p")"
      else
        # A half-applied patch would ship a subtly wrong app; refuse to build
        # one and let the previous deploy keep serving instead.
        say "  PATCH FAILED   $(basename "$p") - see the log tail"
        rm -f scripts/build_app.py
      fi
    done
    # The extractors were written against a local checkout of the decomps.
    # Point every absolute path they carry at this build's work/ directory.
    for f in scripts/build_regions.py scripts/build_extras.py \
             scripts/build_sprites.py scripts/build_app.py; do
      [ -f "$f" ] && sed -i "s#/home/claude/#$ROOT/work/#g" "$f"
    done
    say "  unpacked       $(ls scripts/*.py 2>/dev/null | wc -l) scripts"
  else
    say "  UNPACK FAILED"
  fi
else
  say "  sha256 MISMATCH - the payload parts do not reassemble"
  say "    expected  $PAYLOAD_SHA256"
  say "    got       ${GOT:-<nothing>}"
  for f in scripts/payload/part*.b64; do
    [ -f "$f" ] || continue
    say "    $(basename "$f")  $(tr -d '[:space:]' < "$f" | wc -c) chars  $(tr -d '[:space:]' < "$f" | sha1sum | cut -c1-12)"
  done
fi

say ""
say "=== decompilations ==="
T0=$(date +%s)
git clone --depth 1 --quiet https://github.com/pret/pokeemerald.git work/pokeemerald 2>>"$LOG" \
  && say "  pokeemerald  $(du -sh work/pokeemerald | cut -f1)  $(( $(date +%s) - T0 ))s" \
  || say "  pokeemerald  CLONE FAILED"
T1=$(date +%s)
git clone --depth 1 --quiet https://github.com/pret/pokefirered.git work/pokefirered 2>>"$LOG" \
  && say "  pokefirered  $(du -sh work/pokefirered | cut -f1)  $(( $(date +%s) - T1 ))s" \
  || say "  pokefirered  CLONE FAILED"

say ""
say "=== fonts ==="
if [ -f scripts/fonts.py ]; then
  say "  $( (cd scripts && "$PY" fonts.py "$ROOT/work/font2.json") 2>&1 | tail -n 1 )"
fi
if [ ! -s work/font2.json ]; then
  say "  unavailable - the page will use the system font stack"
  echo '{"400":"","600":"","800":""}' > work/font2.json
fi

say ""
say "=== extractors ==="
run_step() {
  local name="$1" script="$2" t0
  if [ ! -f "scripts/$script" ]; then
    say "  $name  missing"
    return
  fi
  t0=$(date +%s)
  if (cd scripts && "$PY" "$script") >>"$LOG" 2>&1; then
    say "  $name  ok      $(( $(date +%s) - t0 ))s"
  else
    say "  $name  FAILED - traceback is further down this log"
  fi
}
run_step "regions " build_regions.py
run_step "extras  " build_extras.py
run_step "sprites " build_sprites.py
run_step "layouts " build_layouts.py
run_step "app     " build_app.py

say ""
[ -s work/wild-encounter-atlas.html ] && cp work/wild-encounter-atlas.html public/index.html

if [ -s public/index.html ]; then
  say "=== app assembled from source ==="
  say "  public/index.html  $(du -h public/index.html | cut -f1)"
else
  say "=== generation produced no page - serving the last published build ==="
  if curl -fsSL --max-time 60 "$CURRENT_BUILD" -o public/index.html; then
    say "  fetched  $(du -h public/index.html | cut -f1)  from $CURRENT_BUILD"
  else
    say "  FETCH FAILED - serving a status page"
    cat > public/index.html <<'HTML'
<!doctype html>
<meta charset="utf-8"><title>Encounter Atlas</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:16px/1.6 system-ui;max-width:34rem;margin:5rem auto;padding:0 1.25rem;color:#0d2136;background:#eaf4ff">
<h1>Encounter Atlas</h1>
<p style="color:#3f5a76">This build did not complete. See
<a href="/build-log.html">the build log</a>.</p>
</body>
HTML
  fi
fi

say ""
say "=== finished $(date -u '+%H:%M:%SZ') ==="

# Diagnostics live at their own path so they never sit on top of the app.
{
  cat <<'HTML'
<!doctype html>
<meta charset="utf-8"><title>Encounter Atlas - build log</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<body style="font:15px/1.6 system-ui,sans-serif;max-width:46rem;margin:3rem auto;padding:0 1.25rem;color:#0d2136;background:#eaf4ff">
<h1 style="margin-bottom:.2rem">Build log</h1>
<p style="color:#3f5a76;margin-top:0">Vercel regenerates the atlas dataset from the
Pokemon decompilations on every push. This is that run.</p>
<pre style="background:#fff;border:2px solid #cddff2;border-radius:12px;padding:1rem 1.25rem;overflow:auto;font:13px/1.55 ui-monospace,monospace">
HTML
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$LOG"
  cat <<'HTML'
</pre>
<p style="color:#3f5a76"><a href="/">Back to the atlas</a></p>
</body>
HTML
} > public/build-log.html

exit 0
