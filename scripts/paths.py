"""Where the build puts things.

The decompilations are cloned into work/ by build.sh; generated artefacts go to
work/ as intermediates and public/ as things the site actually serves.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'work')
PUBLIC = os.path.join(ROOT, 'public')

REPOS = {
    'hoenn': os.path.join(WORK, 'pokeemerald'),
    'kanto': os.path.join(WORK, 'pokefirered'),
}

def work(*p):
    return os.path.join(WORK, *p)

def public(*p):
    return os.path.join(PUBLIC, *p)
