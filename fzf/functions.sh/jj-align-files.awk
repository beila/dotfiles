# gawk filter that fixes `jj log -s` file-line alignment for the _jh/_jhh fzf
# views. jj's graph renderer indents a commit's FIRST continuation line one
# space less than the rest (e.g. "│  M a" then "│   M b"), so file lines don't
# line up. Normalize the run of spaces after the last graph bar (│) to a fixed
# 3 — on file lines only (tab field 3 = path is non-empty), leaving commit
# lines untouched. Handles nested merge graphs ("│ │  M") via the greedy `.*│`.
#
# Lives in its own file (run via `gawk -F'\t' -f <thisfile>`) rather than an
# inline `-e` program string: the program contains $1/$3, and the reload
# command that invokes it passes through several shell hops (fzf transform →
# echo → fzf → sh -c). An inline program would have its $1/$3 eaten by those
# shells, producing a corrupt script ("NF>=3 && != { = gensub(...) }"). A file
# path carries no `$`, so it survives every hop intact.
BEGIN { FS = "\t"; OFS = "\t" }
NF >= 3 && $3 != "" { $1 = gensub(/^(.*│)[ ]+/, "\\1   ", 1, $1) }
{ print }
