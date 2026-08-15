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
- walkable route interiors rendered from each map's own tile data
- a missables guide per game

## How this repo builds

The dataset is around 1 MB and is not committed here. It is regenerated during the
Vercel build: `scripts/build.sh` shallow-clones both decompilations, the extractors
read the game data, and the result is written into `public/`.

That keeps the repo small and means the data can never drift from its source.
