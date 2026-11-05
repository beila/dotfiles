# Keep each graph column fixed. Adjust only the gap before a file row.
# Junctions can follow a vertical bar. A change to an earlier gap breaks the edges.
# Match only the graph prefix to preserve graph symbols in file names.
#
# Keep this program in a file. Reload commands cross shells that expand inline awk fields.
BEGIN { FS = "\t"; OFS = "\t" }
NF >= 3 && $3 != "" {
    $1 = gensub(/^([ │─╭╮╯╰├┤┬┴┼~]*[│─╭╮╯╰├┤┬┴┼~])[ ]+/, "\\1   ", 1, $1)
}
{ print }
