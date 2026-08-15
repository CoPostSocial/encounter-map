"""Rebuild font2.json: the three Plus Jakarta Sans weights the atlas inlines.

build_app.py embeds each weight as a base64 woff2 data: URL so the deployed page
is a single self-contained file that makes no font request at runtime. The blobs
are lifted from the currently published build first -- that reproduces exactly
what the app ships today -- and fetched from Google Fonts if that is
unreachable. If neither works the caller falls back to the system font stack.
"""
import base64, json, os, re, subprocess, sys

WEIGHTS = ('400', '600', '800')
UA = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')


def curl(url, *extra):
    if not url:
        return b''
    cmd = ['curl', '-fsSL', '--max-time', '60', *extra, url]
    return subprocess.run(cmd, capture_output=True).stdout


def from_published(url):
    html = curl(url).decode('utf8', 'replace')
    blobs = re.findall(r'font/woff2;base64,([A-Za-z0-9+/=]+)\)', html)
    if len(blobs) < 3:
        return None
    return dict(zip(WEIGHTS, blobs[:3]))


def from_google():
    css = curl('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans'
               ':wght@400;600;800&display=swap',
               '-H', 'User-Agent: ' + UA).decode('utf8', 'replace')
    out = {}
    for block in css.split('@font-face')[1:]:
        w = re.search(r'font-weight:\s*(\d+)', block)
        u = re.search(r'url\((https://[^)]+\.woff2)\)', block)
        if not w or not u or w.group(1) not in WEIGHTS or w.group(1) in out:
            continue
        # Google splits each weight across unicode-range subsets; the plain
        # latin one is the block that carries U+0000-00FF.
        if 'U+0000-00FF' not in block.upper():
            continue
        data = curl(u.group(1))
        if data:
            out[w.group(1)] = base64.b64encode(data).decode()
    return out if len(out) == 3 else None


def main(out_path, published_url):
    if os.path.exists(out_path) and os.path.getsize(out_path) > 1000:
        print('fonts: already present')
        return 0
    for name, fn in (('the published build', lambda: from_published(published_url)),
                     ('google fonts', from_google)):
        try:
            got = fn()
        except Exception as e:                    # network, parse, anything
            print('fonts: %s failed (%s)' % (name, e))
            continue
        if got:
            json.dump(got, open(out_path, 'w'))
            print('fonts: from %s, %d KB'
                  % (name, os.path.getsize(out_path) // 1024))
            return 0
        print('fonts: %s had nothing usable' % name)
    print('fonts: could not be recovered')
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], os.environ.get('CURRENT_BUILD', '')))
