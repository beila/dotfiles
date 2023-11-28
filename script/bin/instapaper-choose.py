#!python

'''
#!/bin/bash -x
# https://github.com/bugen/pypipe
#echo $(
bash -x -c "$(
(grep -v '^ *$' | sed "s:^:':" | sed "s:$:':" | tr '\n' ' ') << PARAMS
ppp
csv
-H
-i
random

--pre
lastfolder = ""
--pre
folderlines = {}

--loop-head
folder = dic["Folder"]
--loop-head
folderlines[folder] = folderlines.get(folder,0)+1

-f
folder not in [lastfolder, "Unread", "Starred", "Archive", "neo", "smith", "cypher", "tank", "apoc", "mouse", "switch", "dozer", "brown", "jones", "haren", "temp", "Books", "Books 2", "Books 3"]

-n
L[len(L):] = [{**dic,"findex":folderlines[folder]}]
lastfolder = folder

-v
--post
for l in random.choices(L, k=10): view(l)

-p
PARAMS
)"
'''

# IMPORT
import sys
from functools import partial
from pprint import pformat
from unicodedata import east_asian_width
import csv
import random

def _write(*args, writer=None):
    if len(args) == 1 and isinstance(args[0], (list, tuple)):
        writer.writerow(args[0])
    else:
        writer.writerow(args)


reader = csv.reader(sys.stdin, delimiter=',')
writer = csv.writer(sys.stdout, delimiter=',')
_w = writer.writerow   # ABBREV
header = next(reader)

# PRE
_p = partial(print, sep="\t")  # ABBREV
I, S, B, L, D, SET = 0, "", False, [], {}, set()  # ABBREV

CLEAR = '\033[0m'
GREEN = '\033[32m'
CYAN = '\033[36m'
BOLD = '\033[1m'

def color(s, color_code=CYAN, bold=False):
    if color_code is None:
        return s
    return f"{BOLD}{color_code}{s}{CLEAR}" if bold else f"{color_code}{s}{CLEAR}"

nocolor = partial(color, color_code=None)
cyan = partial(color, color_code=CYAN)
green = partial(color, color_code=GREEN)

class Viewer:

    def __init__(self, colored=True):
        self.num = 1
        self.color1, self.color2 = (cyan, green) if colored else (nocolor, nocolor)

    def wlen(self, w):
        return sum(2 if east_asian_width(c) in "FWA" else 1 for c in w)

    def ljust(self, w, length):
        return w + " " * max(length - self.wlen(w), 0)

    def format(self, val):
        if isinstance(val, (dict, list, tuple, set)):
            return pformat(val, indent=1, width=120)
        return str(val)

    def _view(self, vals):
        num_width = len(str(len(vals)))
        tmpl = rf"{{0:<{num_width}}}  {{1}}"
        for i, val in enumerate(vals, 1):
            for j, line in enumerate(self.format(val).split("\n")):
                if j == 0:
                    print(tmpl.format(i, self.color2(line)))
                else:
                    print(tmpl.format('.', self.color2(line)))

    def _view_with_headers(self, vals, headers):
        num_width = len(str(len(vals)))
        header_width = max(self.wlen(h) for h in headers)
        tmpl = rf"{{0:<{num_width}}} | {{1}} | {{2}}"
        for i, (header, val) in enumerate(zip(headers, vals), 1):
            for j, line in enumerate(self.format(val).split("\n")):
                if j == 0:
                    print(tmpl.format(i, self.ljust(header, header_width), self.color2(line)))
                else:
                    print(tmpl.format('', self.ljust('', header_width), self.color2(line)))

    def view(self, *args, recnum=None, headers=None):
        print(self.color1(f'[Record {recnum or self.num}]', bold=True))
        vals = args[0] if len(args) == 1 and isinstance(args[0], (list, tuple)) else args
        if headers and len(vals) == len(headers):
            self._view_with_headers(vals, headers)
        else:
            self._view(vals)
        print()
        self.num += 1

viewer = Viewer(colored=False)
view = viewer.view

def _print(*args, sep=','):
    if len(args) == 1 and isinstance(args[0], (list, tuple)):
        print(sep.join(str(v) for v in args[0]))
    else:
        print(sep.join(str(v) for v in args))

lastfolder = ""
folderlines = {}

for i, rec in enumerate(reader, 1):
    r = rec  # ABBREV
    # LOOP HEAD
    dic = dict(zip(header, rec))
    d = dic # ABBREV
    folder = dic["Folder"]
    folderlines[folder] = folderlines.get(folder,0)+1
    # LOOP FILTER
    if not (folder not in [lastfolder, "Unread", "Starred", "Archive", "neo", "smith", "cypher", "tank", "apoc", "mouse", "switch", "dozer", "brown", "jones", "haren", "temp", "Books", "Books 2", "Books 3"]): continue
    # MAIN
    L[len(L):] = [{**dic,"findex":folderlines[folder]}]
    lastfolder = folder

# POST
for l in random.choices(L, k=10): view(l)
