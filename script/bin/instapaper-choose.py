#!/usr/bin/python

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
from functools import partial, reduce
from pprint import pformat
from unicodedata import east_asian_width
import csv
import random

from operator import itemgetter
from itertools import groupby,count,chain
from urllib.parse import urlparse

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

ui={
        "1월": "https://www.instapaper.com/u/folder/4737137/1-",
        "10월": "https://www.instapaper.com/u/folder/4676196/10-",
        "11월": "https://www.instapaper.com/u/folder/4697235/11-",
        "12월": "https://www.instapaper.com/u/folder/4716737/12-",
        "2월": "https://www.instapaper.com/u/folder/4760978/2-",
        "2013": "https://www.instapaper.com/u/folder/4467764/2013",
        "2014": "https://www.instapaper.com/u/folder/4467674/2014",
        "2015": "https://www.instapaper.com/u/folder/4467679/2015",
        "2016": "https://www.instapaper.com/u/folder/4467687/2016",
        "2017": "https://www.instapaper.com/u/folder/4467703/2017",
        "2018": "https://www.instapaper.com/u/folder/4467710/2018",
        "2019": "https://www.instapaper.com/u/folder/4467712/2019",
        "2020": "https://www.instapaper.com/u/folder/4467732/2020",
        "2021": "https://www.instapaper.com/u/folder/4467684/2021",
        "2022": "https://www.instapaper.com/u/folder/4533788/2022",
        "2023": "https://www.instapaper.com/u/folder/4753994/2023",
        "3월": "https://www.instapaper.com/u/folder/4778123/3-",
        "4월": "https://www.instapaper.com/u/folder/4575254/4-",
        "5월": "https://www.instapaper.com/u/folder/4585171/5-",
        "6월": "https://www.instapaper.com/u/folder/4593011/6-",
        "7월": "https://www.instapaper.com/u/folder/4608754/7-",
        "8월": "https://www.instapaper.com/u/folder/4630562/8-",
        "9월": "https://www.instapaper.com/u/folder/4652850/9-",
        "choi": "https://www.instapaper.com/u/folder/1538044/choi",
        "morpheus": "https://www.instapaper.com/u/folder/1185287/morpheus",
        "oracle": "https://www.instapaper.com/u/folder/1536331/oracle",
        "rhineheart": "https://www.instapaper.com/u/folder/1538043/rhineheart",
        "switch": "https://www.instapaper.com/u/folder/1536336/switch",
        "trinity": "https://www.instapaper.com/u/folder/1515162/trinity",
        }

biggest_page={
        "1월": 9999,
        "10월": 9999,
        "11월": 9999,
        "12월": 9999,
        "2월": 9999,
        "2013": 9999,
        "2014": 9999,
        "2015": 9999,
        "2016": 9999,
        "2017": 9999,
        "2018": 9999,
        "2019": 9999,
        "2020": 9999,
        "2021": 9999,
        "2022": 9999,
        "2023": 9999,
        "3월": 9999,
        "4월": 9999,
        "5월": 9999,
        "6월": 9999,
        "7월": 9999,
        "8월": 9999,
        "9월": 9999,
        "choi": 9999,
        "morpheus": 3,
        "oracle": 4,
        "rhineheart": 9999,
        "switch": 9999,
        "trinity": 7,
        }

heavier_folders =[
        "choi",
        "morpheus",
        "oracle",
        "rhineheart",
        "trinity"]

folderlines = {}
org_dicts = (dict(zip(header, r)) for r in reader)
timed_dicts = sorted(org_dicts, key=lambda d: d["Timestamp"], reverse=True)
f_grouped = groupby(sorted(timed_dicts, key=lambda d: d["Folder"]),lambda d: d["Folder"])
f_indexed = ({**d,
                "findex":i,
                "ui":ui[d["Folder"]]+("/"+str(int(i/40)+1) if i >= 40 else ''),
                "weight":30 if d["Folder"] in heavier_folders else 1,
                "domain":urlparse(d["URL"]).netloc}
                    for grouper in f_grouped
                        if grouper[0] in ui.keys()
                    for i, d in enumerate(grouper[1])
                        if i/40+1 < biggest_page[d["Folder"]])
grouped = groupby(f_indexed, lambda d: d["domain"])
lasts = list(list(g[1])[-1] for g in grouped)
# lasts = list(chain.from_iterable(g[1] for g in grouped))

for l in random.choices(lasts, weights=(d["weight"] for d in lasts), k=9):
    del l["Selection"]
    del l["Timestamp"]
    del l["domain"]
    del l["weight"]
    del l["findex"]
    view(l)
