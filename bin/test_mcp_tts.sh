#!/usr/bin/env bash
# Test: mcp-tts server survives kill of already-exited TTS process
# Reproduces: "Transport to MCP server 'tts' is closed" error
# Run: bash bin/test_mcp_tts.sh

set -uo pipefail
pass=0 fail=0
assert_eq() {
  if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; ((pass++)); else echo "  ✗ $1"; echo "    expected: $3"; echo "    got: $2"; ((fail++)); fi
}

mcp="$(dirname "$0")/mcp-tts"

echo "mcp-tts rapid calls (TTS still running, kill succeeds):"
out=$(
{
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}'
  echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"say","arguments":{"text":"hello world this is a longer sentence"}}}'
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"say","arguments":{"text":"second call immediately"}}}'
} | timeout 5 "$mcp" 2>&1
)
count=$(echo "$out" | grep -c '"result"')
assert_eq "should get 3 responses (init + 2 calls)" "$count" "3"

echo "mcp-tts init + tools/list:"
out=$(
{
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}'
  echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
} | timeout 5 "$mcp" 2>&1
)
assert_eq "init response" "$(echo "$out" | head -1 | jq -r '.result.serverInfo.name')" "tts"
assert_eq "lists say tool" "$(echo "$out" | tail -1 | jq -r '.result.tools[0].name')" "say"
assert_eq "lists say_ko tool" "$(echo "$out" | tail -1 | jq -r '.result.tools[1].name')" "say_ko"

echo "mcp-tts consecutive calls (short text, process exits before next call):"
# Use a very short text so TTS finishes quickly, then the kill targets a dead PGID
out=$(
{
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}'
  echo '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"say","arguments":{"text":"hi"}}}'
  sleep 3  # let short TTS finish and process exit
  echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"say","arguments":{"text":"bye"}}}'
} | timeout 10 "$mcp" 2>&1
)
count=$(echo "$out" | grep -c '"result"')
assert_eq "should get 3 responses (init + 2 calls)" "$count" "3"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
