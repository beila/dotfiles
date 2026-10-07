# awk filter for the Enter key of the _jh/_jhh/_jyy fzf pickers.
# Input: the fzf indices of the selected rows ({+n}), a "--" line, then the change ids of the
# same rows ({+2}), one value on each line.
# If the indices are consecutive, print one "<oldest>::<newest>" revset. Otherwise, print each
# unique change id on its own line, as before.
# The index check does not examine the graph. Thus, adjacent rows of sibling branches also
# become a range.
# Rows without a change id (graph connector rows) count for the index check only. File rows of
# the files view give the change id of their commit, so duplicates are removed.

!sep && $0 == "--" { sep = 1; next }
!sep { idx[++n] = $0 + 0; next }
{ id[++m] = $0 }

END {
  lo = hi = -1
  for (i = 1; i <= n; i++) {
    if (lo < 0 || idx[i] < lo) lo = idx[i]
    if (hi < 0 || idx[i] > hi) hi = idx[i]
    if (id[i] == "") continue
    if (!(id[i] in seen)) { seen[id[i]] = 1; uniq[++u] = id[i] }
    # jj log lists the newest commit first, so the lowest index is the newest commit.
    if (top == "" || idx[i] < top_idx) { top = id[i]; top_idx = idx[i] }
    if (bottom == "" || idx[i] > bottom_idx) { bottom = id[i]; bottom_idx = idx[i] }
  }
  if (u > 1 && hi - lo + 1 == n) { print bottom "::" top; exit }
  for (i = 1; i <= u; i++) print uniq[i]
}
