"""Apply a unified diff. Vercel's build image has no patch(1).

Deliberately strict: a hunk whose context does not match is a hard error, so a
mangled patch stops the build instead of quietly producing a half-changed file.
Hunks are located at their stated line first and searched for nearby only if
that fails, which keeps a patch working after an earlier one shifts the file.
"""
import re, sys

HUNK = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')


def parse(text):
    """-> [(path, [(start_line, old_lines, new_lines), ...]), ...]"""
    lines = text.split('\n')
    files, cur, i = [], None, 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('--- ') and i + 1 < len(lines) and lines[i + 1].startswith('+++ '):
            new = lines[i + 1][4:].split('\t')[0]
            old = line[4:].split('\t')[0]
            path = re.sub(r'^[ab]/', '', old if new == '/dev/null' else new)
            cur = (path, [])
            files.append(cur)
            i += 2
            continue
        m = HUNK.match(line)
        if m and cur is not None:
            start, oldn, newn = int(m.group(1)), int(m.group(2) or 1), int(m.group(4) or 1)
            old_body, new_body = [], []
            i += 1
            while i < len(lines) and (len(old_body) < oldn or len(new_body) < newn):
                t = lines[i]
                if t.startswith('\\'):                 # "\ No newline at end of file"
                    pass
                elif t.startswith('-'):
                    old_body.append(t[1:])
                elif t.startswith('+'):
                    new_body.append(t[1:])
                elif t.startswith(' ') or t == '':      # context; bare '' is an empty one
                    old_body.append(t[1:])
                    new_body.append(t[1:])
                else:
                    break
                i += 1
            cur[1].append((start, old_body, new_body))
            continue
        i += 1
    return files


def locate(src, idx, old):
    if src[idx:idx + len(old)] == old:
        return idx
    for d in range(1, 400):                             # earlier hunks shift lines
        for cand in (idx - d, idx + d):
            if 0 <= cand and src[cand:cand + len(old)] == old:
                return cand
    return None


def apply(path, hunks):
    src = open(path, encoding='utf8').read().split('\n')
    out, pos = [], 0
    for start, old, new in hunks:
        idx = locate(src, start - 1, old)
        if idx is None:
            raise SystemExit('%s: hunk at line %d does not match' % (path, start))
        if idx < pos:
            raise SystemExit('%s: hunk at line %d overlaps the previous one' % (path, start))
        out.extend(src[pos:idx])
        out.extend(new)
        pos = idx + len(old)
    out.extend(src[pos:])
    open(path, 'w', encoding='utf8').write('\n'.join(out))


def main(paths):
    for p in paths:
        for path, hunks in parse(open(p, encoding='utf8').read()):
            if not hunks:
                continue
            apply(path, hunks)
            print('%s: %d hunk%s -> %s' % (p.split('/')[-1], len(hunks),
                                           '' if len(hunks) == 1 else 's', path))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
