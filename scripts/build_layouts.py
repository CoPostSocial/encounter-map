"""Route interiors.

Each map's blockdata is a grid of metatile ids. Every metatile carries a
behaviour byte in its tileset's metatile_attributes.bin - the same byte the game
itself checks to decide whether a tile triggers a wild encounter. Classifying by
that byte means the grass drawn on the route map is exactly the grass that
spawns Pokemon, not an approximation.

Output: work/layouts.json - {region: {MAP_ID: {w, h, c}}} where c is a run-length
encoded string of terrain categories.
"""
import json, os, re, struct
from paths import REPOS, work


def behaviors(repo):
    """Emerald declares MB_* as an enum, FireRed as #defines."""
    src = open(os.path.join(repo, 'include/constants/metatile_behaviors.h')).read()
    defs = re.findall(r'#define\s+(MB_\w+)\s+(0x[0-9A-Fa-f]+|\d+)', src)
    if len(defs) > 20:
        return {n: int(v, 0) for n, v in defs}
    body = src.split('enum', 1)[1]
    body = body[body.index('{') + 1: body.index('}')]
    out, nxt = {}, 0
    for raw in body.split(','):
        t = raw.split('//')[0].strip()
        if not t:
            continue
        if '=' in t:
            name, val = [x.strip() for x in t.split('=')]
            nxt = int(val, 0)
        else:
            name = t
        out[name] = nxt
        nxt += 1
    return out


def categorise(mb):
    """Behaviour name -> what it looks like on the route map."""
    n = mb
    if 'TALL_GRASS' in n or 'LONG_GRASS' in n or n == 'MB_ASHGRASS':
        return 'g'
    if 'WATER' in n or 'WATERFALL' in n or 'PUDDLE' in n or 'SURF' in n:
        return 'w'
    if 'SAND' in n or 'DESERT' in n or 'FOOTPRINT' in n:
        return 's'
    if 'ICE' in n or 'SNOW' in n:
        return 'i'
    if ('STAIRS' in n or 'LADDER' in n or 'DOOR' in n or 'WARP' in n
            or 'ESCALATOR' in n or ('CAVE' in n and 'ENTRANCE' in n)):
        return 'd'
    if 'JUMP' in n or 'LEDGE' in n:
        return 'l'
    return '.'


def tileset_dirs(repo):
    out = {}
    for kind in ('primary', 'secondary'):
        base = os.path.join(repo, 'data/tilesets', kind)
        if not os.path.isdir(base):
            continue
        for d in os.listdir(base):
            out[(kind, d.lower())] = os.path.join(base, d)
    return out


def label_to_dir(label, dirs, kind):
    key = re.sub(r'^gTileset_', '', label)
    key = re.sub(r'(?<!^)(?=[A-Z])', '_', key).lower()
    for k in (key, key.replace('_', '')):
        if (kind, k) in dirs:
            return dirs[(kind, k)]
    for (kk, name), path in dirs.items():
        if kk == kind and name.replace('_', '') == key.replace('_', ''):
            return path
    return None


def attrs_for(path, width):
    p = os.path.join(path, 'metatile_attributes.bin')
    if not os.path.exists(p):
        return []
    raw = open(p, 'rb').read()
    if width == 4:                      # FireRed stores 4 bytes per metatile
        return [v & 0xFF for v in struct.unpack('<%dI' % (len(raw) // 4), raw)]
    return [v & 0xFF for v in struct.unpack('<%dH' % (len(raw) // 2), raw)]


def rle(cells):
    out, prev, run = [], None, 0
    for c in cells:
        if c == prev:
            run += 1
        else:
            if prev is not None:
                out.append(prev + (str(run) if run > 1 else ''))
            prev, run = c, 1
    if prev is not None:
        out.append(prev + (str(run) if run > 1 else ''))
    return ''.join(out)


def build(repo, wanted_maps):
    mbnames = {v: k for k, v in behaviors(repo).items()}
    dirs = tileset_dirs(repo)
    layouts = {l['id']: l for l
               in json.load(open(os.path.join(repo, 'data/layouts/layouts.json')))['layouts']
               if l.get('id')}
    attr_cache = {}
    width = 4 if 'firered' in repo else 2

    out = {}
    for map_id, layout_id in wanted_maps.items():
        L = layouts.get(layout_id)
        if not L or not L.get('blockdata_filepath'):
            continue
        bp = os.path.join(repo, L['blockdata_filepath'])
        if not os.path.exists(bp):
            continue
        w, h = L['width'], L['height']
        raw = open(bp, 'rb').read()
        blocks = struct.unpack('<%dH' % (len(raw) // 2), raw)
        if len(blocks) < w * h:
            continue

        prim = label_to_dir(L['primary_tileset'], dirs, 'primary')
        sec = label_to_dir(L.get('secondary_tileset') or '', dirs, 'secondary')
        for d in (prim, sec):
            if d and d not in attr_cache:
                attr_cache[d] = attrs_for(d, width)
        pa = attr_cache.get(prim, [])
        sa = attr_cache.get(sec, [])

        cells = []
        for i in range(w * h):
            b = blocks[i]
            mid = b & 0x3FF
            coll = (b >> 10) & 3
            if mid < len(pa):
                beh = pa[mid]
            elif 0 <= mid - 512 < len(sa):
                beh = sa[mid - 512]
            else:
                beh = 0
            c = categorise(mbnames.get(beh, ''))
            if c == '.' and coll:
                c = '#'                 # solid: trees, walls, buildings
            cells.append(c)
        out[map_id] = {'w': w, 'h': h, 'c': rle(cells)}
    return out


def main():
    import glob
    regions = json.load(open(work('regions.json')))['regions']
    result = {}
    for key, repo in REPOS.items():
        maps = {}
        for path in glob.glob(os.path.join(repo, 'data/maps/*/map.json')):
            m = json.load(open(path))
            maps[m['id']] = m.get('layout')
        ids = {a['map'] for a in regions[key]['areas'].values()}
        wanted = {mid: maps[mid] for mid in ids if maps.get(mid)}
        result[key] = build(repo, wanted)
        tot = sum(len(v['c']) for v in result[key].values())
        print(f"  {key}: {len(result[key])} route layouts, {tot // 1024} KB of RLE")
    json.dump(result, open(work('layouts.json'), 'w'))


if __name__ == '__main__':
    main()
