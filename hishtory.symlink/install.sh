# shellcheck disable=SC2016

curl https://hishtory.dev/install.py | python3 -
echo 'run "hishtory init $YOUR_HISHTORY_SECRET"'
echo 'where $YOUR_HISHTORY_SECRET is shown by "hishtory status" on a already setup machine.'
