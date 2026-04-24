{
  s = $1
  gsub(/\033\[[0-9;]*m/, "", s)
  if (s ~ /@/) print
}
