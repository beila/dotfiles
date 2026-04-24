{
  if (/^ /) {
    gsub(/^ +/, "")
    $1 = parent $1
  } else {
    parent = $1
    gsub(/:$/, "", parent)
    gsub(/\033\[[0-9;]*m/, "", parent)
  }
  print
}
