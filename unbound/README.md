# Unbound Atlas

A reference for **Pokémon Unbound 2.1.1.1** — Pokédex, wild encounters, raid dens,
boss fights and Gen VI type matchups — generated at build time from the game's
published data. Nothing here is hand-transcribed.

## Where the data comes from

Unbound has no decompilation, so this is a two-source pipeline and the app labels
which half you are looking at.

| Source | Pinned at | What it gives |
|---|---|---|
| `Skeli789/Dynamic-Pokemon-Expansion` branch `Unbound` | `fe058e0e` ("Changes for 2.1.1") | 1,274 species: stats, types, abilities, evolutions, learnsets, TM/tutor compatibility, and the game's own 64×64 sprites |
| `Skeli789/Complete-Fire-Red-Upgrade` | `b637a278` — the commit Unbound 2.1.1.1 was built from | 922 moves with per-move physical/special category, the 18-type Gen VI chart, 105 raid dens |
| `ydarissep/Unbound-Pokedex` | `abc2ccc0` | wild encounters — the only public table with levels and slot order. Undocumented, unversioned, 43 of 165 maps unnamed |
| `jimineybillybob1/pokemon-unbound-field-guide` | `d668b78b` | trainer and boss parties, transcribed from the community Trainers Doc |

The first two are first-party and version-matched. The last two are community work
of weaker provenance, and the app says so on every screen where it matters: 26
areas carry "name not documented", 17 more are marked as inferred sub-areas, and
bosses show which difficulty their roster came from.

There is **no map**. Unbound publishes no layout, coordinate or connection data —
that lives in the lower 16 MB of the ROM, which the distributed UPS patch XORs
against a copyrighted base ROM. Locations are a searchable list instead.

## Building

```
bash build.sh          # fetches the pinned sources, runs the pipeline, writes public/
```

Outputs three things into `public/`:

- `index.html` + `sprites.png` — the web build; the sheet is a separate cacheable
  file so the page paints before the artwork arrives
- `unbound-atlas.html` — one self-contained file with the sheet inlined, for
  offline use
- `build-log.html` — every source SHA and every extractor's own sanity output

## Why the scripts are in pieces

`parts/*.part` reassemble into the five Python extractors. They are split because
the file API this repo is written through truncates large writes silently — a
14 KB push once arrived as 5.5 KB. Each script is checksummed after reassembly
(`check_script` in `build.sh`), so a short read fails the build loudly instead of
producing a subtly wrong site.

## Performance notes

Two things dominated on a throttled phone and are worth not undoing:

- **Sprites draw from one rasterisation of the sheet.** Sizing the background per
  element made the browser re-rasterise a 4-megapixel PNG once per distinct sprite
  size; the 120px hero blew it up to 14.9 MP. Painting the Pokédex cost 6.5 s.
  Now `background-size` is constant and each 64px window is scaled with a
  transform.
- **Long lists render a screenful at a time**, and boss battle plans — which each
  scan 1,024 species — are computed when a panel is opened, not when the list is
  built. That was 10 s of blocked main thread for panels that start collapsed.

Not affiliated with Skeli789, the Unbound team, Nintendo, Game Freak or
The Pokémon Company.
