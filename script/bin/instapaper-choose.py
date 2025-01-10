#!/usr/bin/python

"""
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
for line in random.choices(L, k=10): view(line)

-p
PARAMS
)"
"""

# IMPORT
import csv
import random
import sys
from functools import partial
from itertools import filterfalse, groupby, islice
from operator import itemgetter
from pprint import pformat
from unicodedata import east_asian_width

from urllib.parse import urlparse
from urllib.parse import quote_plus


def _write(*args, writer=None):
    if len(args) == 1 and isinstance(args[0], (list, tuple)):
        writer.writerow(args[0])
    else:
        writer.writerow(args)


reader = csv.reader(sys.stdin, delimiter=",")
writer = csv.writer(sys.stdout, delimiter=",")
_w = writer.writerow  # ABBREV
header = next(reader)

# PRE
_p = partial(print, sep="\t")  # ABBREV
I, S, B, L, D, SET = 0, "", False, [], {}, set()  # ABBREV  # noqa: E741

CLEAR = "\033[0m"
GREEN = "\033[32m"
CYAN = "\033[36m"
BOLD = "\033[1m"


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
                    print(tmpl.format(".", self.color2(line)))

    def _view_with_headers(self, vals, headers):
        num_width = len(str(len(vals)))
        header_width = max(self.wlen(h) for h in headers)
        tmpl = rf"{{0:<{num_width}}} | {{1}} | {{2}}"
        for i, (header, val) in enumerate(zip(headers, vals), 1):
            for j, line in enumerate(self.format(val).split("\n")):
                if j == 0:
                    print(
                        tmpl.format(
                            i, self.ljust(header, header_width), self.color2(line)
                        )
                    )
                else:
                    print(
                        tmpl.format("", self.ljust("", header_width), self.color2(line))
                    )

    def view(self, *args, recnum=None, headers=None):
        print(self.color1(f"[Record {recnum or self.num}]", bold=True))
        vals = (
            args[0] if len(args) == 1 and isinstance(args[0], (list, tuple)) else args
        )
        if headers and len(vals) == len(headers):
            self._view_with_headers(vals, headers)
        else:
            self._view(vals)
        print()
        self.num += 1


viewer = Viewer(colored=True)
view = viewer.view


def _print(*args, sep=","):
    if len(args) == 1 and isinstance(args[0], (list, tuple)):
        print(sep.join(str(v) for v in args[0]))
    else:
        print(sep.join(str(v) for v in args))


folders = {
    "10월": "https://www.instapaper.com/u/folder/4676196/10-",
    "11월": "https://www.instapaper.com/u/folder/4697235/11-",
    "12월": "https://www.instapaper.com/u/folder/4716737/12-",
    "1월": "https://www.instapaper.com/u/folder/4737137/1-",
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
    "2024": "https://www.instapaper.com/u/folder/4949749/2024",
    "2025": "https://www.instapaper.com/u/folder/5111825/2025",
    "2월": "https://www.instapaper.com/u/folder/4760978/2-",
    "3월": "https://www.instapaper.com/u/folder/4778123/3-",
    "4월": "https://www.instapaper.com/u/folder/4575254/4-",
    "5월": "https://www.instapaper.com/u/folder/4585171/5-",
    "6월": "https://www.instapaper.com/u/folder/4593011/6-",
    "7월": "https://www.instapaper.com/u/folder/4608754/7-",
    "8월": "https://www.instapaper.com/u/folder/4630562/8-",
    "9월": "https://www.instapaper.com/u/folder/4652850/9-",
    "Books 2": "https://www.instapaper.com/u/folder/4845144/books-2",
    "Books": "https://www.instapaper.com/u/folder/4845142/books",
    "choi": "https://www.instapaper.com/u/folder/1538044/choi",
    "jones": "https://www.instapaper.com/u/folder/1538042/jones",
    "morpheus": "https://www.instapaper.com/u/folder/1185287/morpheus",
    "oracle": "https://www.instapaper.com/u/folder/1536331/oracle",
    "rhineheart": "https://www.instapaper.com/u/folder/1538043/rhineheart",
    "smith": "https://www.instapaper.com/u/folder/1514058/smith",
    "switch": "https://www.instapaper.com/u/folder/1536336/switch",
    # "brown": "https://www.instapaper.com/u/folder/1538041/brown",
    # "trinity": "https://www.instapaper.com/u/folder/1515162/trinity",
}

folder_weights = {
    "10월": 6,
    "11월": 6,
    "12월": 6,
    "1월": 6,
    "2013": 6,
    "2014": 6,
    "2015": 6,
    "2016": 6,
    "2017": 6,
    "2018": 6,
    "2019": 6,
    "2020": 6,
    "2021": 6,
    "2022": 6,
    "2023": 6,
    "2024": 12,
    "2025": 12,
    "2월": 6,
    "3월": 6,
    "4월": 6,
    "5월": 6,
    "6월": 6,
    "7월": 6,
    "8월": 6,
    "9월": 6,
    "Books 2": 1,
    "Books": 1,
    "brown": 6,
    "choi": 6,
    "jones": 1,
    "morpheus": 40,
    "oracle": 40,
    "rhineheart": 40,
    "smith": 1,
    "switch": 6,
    "trinity": 40,
}

biggest_page = {
    "morpheus": 2,
    "oracle": 5,
    "smith": 4,
}

folderlines = {}
org_dicts = (dict(zip(header, r)) for r in reader)
timed_dicts = sorted(org_dicts, key=itemgetter("Timestamp"), reverse=True)
f_grouped = groupby(sorted(timed_dicts, key=itemgetter("Folder")), itemgetter("Folder"))
f_indexed = [
    {
        **d,
        "findex": index_in_the_folder,
        "page": folders[d["Folder"]] + "/" + str(int(index_in_the_folder / 40) + 1),
        "loc": folders[d["Folder"]]
        + "/"
        + str(int(index_in_the_folder / 40) + 1)
        + "#:~:text="
        + quote_plus(d["Title"]),
        "weight": folder_weights[d["Folder"]],
        "domain": urlparse(d["URL"]).netloc,
    }
    for folder_name, all_data_in_a_folder in f_grouped
    if folder_name in folders.keys()
    for index_in_the_folder, d in enumerate(all_data_in_a_folder)
    if index_in_the_folder / 40 + 1 < biggest_page.get(d["Folder"], 9999)
]
# grouped = groupby(f_indexed, lambda d: d["domain"])
grouped = groupby(sorted(f_indexed, key=itemgetter("page")), itemgetter("page"))
# FIXME change to deduplication inside the page
chosen_data_in_each_page = list(
    random.choice(list(all_data_in_consecutive_domain))
    for _, all_data_in_a_page in grouped
    for _, all_data_in_consecutive_domain in groupby(
        all_data_in_a_page, itemgetter("domain")
    )
)
# lasts = list(chain.from_iterable(g[1] for g in grouped))


def _chooser():
    if not chosen_data_in_each_page:
        return

    for line in random.choices(
        chosen_data_in_each_page,
        weights=(d["weight"] for d in chosen_data_in_each_page),
        k=len(chosen_data_in_each_page),
    ):
        yield line


# https://docs.python.org/3/library/itertools.html#itertools-recipes
def unique_everseen(iterable, key=None):
    "Yield unique elements, preserving order. Remember all elements ever seen."
    # unique_everseen('AAAABBBCCDAABBB') → A B C D
    # unique_everseen('ABBcCAD', str.casefold) → A B c D
    seen = set()
    if key is None:
        for element in filterfalse(seen.__contains__, iterable):
            seen.add(element)
            yield element
    else:
        for element in iterable:
            k = key(element)
            if k not in seen:
                seen.add(k)
                yield element


for line in islice(unique_everseen(_chooser(), itemgetter("URL")), 10):
    view(dict((k, line[k]) for k in ["Title", "URL", "loc"]))
