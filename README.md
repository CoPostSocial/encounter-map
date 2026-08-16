# Wild Encounter Atlas

Wild encounter reference for Pokemon Emerald (Hoenn) and Pokemon LeafGreen
(Kanto and the Sevii Islands).

Everything in the app is extracted from the games' own code - the
[pret/pokeemerald](https://github.com/pret/pokeemerald) and
[pret/pokefirered](https://github.com/pret/pokefirered) disassemblies. Kanto uses the
LeafGreen encounter tables specifically, not FireRed's.

## What it covers

- every wild encounter table in both games, with exact slot percentages
- items, including hidden ones, at their real tile coordinates
- trainers and their full parties
- full evolution lines: every branch, the method for each, whether a stage can
  be caught wild at all, and where to find the stone an evolution needs
- walkable route interiors rendered from each map's own tile data
- a missables guide per game

## How this repo builds

The dataset is around 1.4 MB and is not committed here. It is regenerated on
every deploy by `scripts/build.sh`, which shallow-clones both decompilations,
runs the extractors over the game data, and writes a single self-contained
`public/index.html`. The data can never drift from its source.

The extractors themselves reach this repo in an unusual shape, because they had
to travel through an API with a per-call size limit:

- `scripts/payload/*.b64` is a gzipped tar of the extractors and the app
  generator, split into parts. The build concatenates them in filename order,
  checks the result against a sha256, and unpacks it. This is a frozen
  baseline - it is not edited again.
- `scripts/patches/*.patch` holds every change since, as unified diffs applied
  in filename order by `scripts/apply_patch.py`. Vercel's build image has no
  `patch(1)`, hence the Python one; it is strict, and a hunk that does not
  match is a hard failure.

If the payload checksum fails, a patch does not apply, or an extractor throws,
the build refuses to assemble a page and the previous deploy keeps serving.
Every run writes its diagnostics to `/build-log.html` on the site.
