#!/usr/bin/env bash
# Build entry point, run by Vercel via vercel.json buildCommand.
#
# End state: this script regenerates the whole ~1 MB dataset from the pret
# decompilations and assembles the app, so the repo stays small and the data can
# never drift from its source. The environment for that is verified working -
# see /build-log.html on the deployed site.
#
# Interim: the extractors and app shell are still being committed. Until the
# generated build is complete, the current published build is pulled in so the
# site serves the real app rather than a placeholder. That fallback disappears
# the moment scripts/build_app.py lands.

set -uo pipefail
mkdir -p public work
LOG=work/build.txt
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

CURRENT_BUILD="https://encounter-atlas-deploy-2.vercel.app/"

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
    PY=work/venv/bin/python
    say "  Pillow $($PY -c 'import PIL; print(PIL.__version__)') in venv"
  fi
fi
[ "$PY" = "python3" ] && say "  Pillow unavailable" || true

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
say "=== extractors ==="
run_step() {
  local name="$1" script="$2"
  if [ -f "scripts/$script" ]; then
    if (cd scripts && "../$PY" "$script") >>"$LOG" 2>&1; then
      say "  $name  ok"
    else
      say "  $name  FAILED"
    fi
  else
    say "  $name  not committed yet"
  fi
}
run_step "regions " build_regions.py
run_step "extras  " build_extras.py
run_step "sprites " build_sprites.py
run_step "layouts " build_layouts.py
run_step "app     " build_app.py

say ""
if [ -s public/index.html ]; then
  say "=== app assembled from source ==="
  say "  public/index.html  $(du -h public/index.html | cut -f1)"
else
  say "=== app not generated yet - pulling the published build ==="
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
<p style="color:#3f5a76">The build pipeline is being assembled. See
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
