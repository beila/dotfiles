# Adding TTS Responses to Your Kiro Agent

Make your AI agent speak a summary aloud at the end of every response.

## How It Works

1. A small MCP server exposes TTS as tools to the agent
2. A steering instruction tells the agent to call the tool after every response
3. The agent translates/summarizes and calls the tool — audio plays locally

## Setup

### 1. Install a TTS engine

Pick one (or both):

**Offline — piper-tts** (English, no internet needed):
```bash
# Install piper via your package manager (nix, apt, etc.)
# Voice model auto-downloads on first run
nix profile install nixpkgs#piper-tts
```

**Online — edge-tts** (any language, needs internet):
```bash
# Runs via uv (or pip install edge-tts)
# Supports 400+ voices: https://github.com/rany2/edge-tts
uv run --with edge-tts -- edge-tts --list-voices
```

### 2. Create TTS scripts

**`bin/say`** — English, offline:
```bash
#!/usr/bin/env bash
MODEL="${PIPER_MODEL:-$HOME/.local/share/piper/en_GB-alba-medium.onnx}"
if [ ! -f "$MODEL" ]; then
    mkdir -p "$(dirname "$MODEL")"
    BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alba/medium"
    curl -sfL "$BASE/en_GB-alba-medium.onnx" -o "$MODEL"
    curl -sfL "$BASE/en_GB-alba-medium.onnx.json" -o "$MODEL.json"
fi
if [ $# -gt 0 ]; then echo "$*"; else cat; fi \
  | piper --model "$MODEL" --output-raw 2>/dev/null \
  | aplay -r 22050 -f S16_LE -c 1 -q 2>/dev/null
```

Browse voices at https://rhasspy.github.io/piper-samples/ — override with `$PIPER_MODEL`.

**`bin/say-ko`** — Korean example, online (swap voice for your language):
```bash
#!/usr/bin/env bash
VOICE="${EDGE_TTS_VOICE:-ko-KR-SunHiNeural}"
RATE="${EDGE_TTS_RATE:-+50%}"
if [ $# -gt 0 ]; then TEXT="$*"; else TEXT="$(cat)"; fi
[ -z "$TEXT" ] && exit 0
TMP="$(mktemp /tmp/say-XXXXXX.mp3)"
trap 'rm -f "$TMP"' EXIT
uv run --quiet --with edge-tts -- edge-tts --voice "$VOICE" --rate "$RATE" \
  --text "$TEXT" --write-media "$TMP" 2>/dev/null \
  && ffmpeg -v quiet -i "$TMP" -f wav -acodec pcm_s16le -ar 24000 -ac 1 pipe:1 2>/dev/null \
  | aplay -q 2>/dev/null
```

Make both executable: `chmod +x bin/say bin/say-ko`

### 3. Create the MCP server

**`bin/mcp-tts`** — a bash script implementing MCP over stdio:
```bash
#!/usr/bin/env bash
set -euo pipefail

read_msg() { local line; IFS= read -r line; printf '%s' "$line"; }
send_msg() { printf '%s\n' "$1"; }

# Adapt these to your tools — name, description, and the command they run
TOOLS='[
  {"name":"say","description":"Speak English text aloud via piper-tts (offline)",
   "inputSchema":{"type":"object","properties":{"text":{"type":"string","description":"Text to speak"}},"required":["text"]}},
  {"name":"say_ko","description":"Speak Korean text aloud via edge-tts (online)",
   "inputSchema":{"type":"object","properties":{"text":{"type":"string","description":"Text to speak in Korean"}},"required":["text"]}}
]'

while true; do
  msg="$(read_msg)" || exit 0
  id="$(printf '%s' "$msg" | jq -r '.id // empty')"
  method="$(printf '%s' "$msg" | jq -r '.method // empty')"
  case "$method" in
    initialize)
      send_msg "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"tts\",\"version\":\"1.0.0\"}}}" ;;
    notifications/initialized) ;;
    tools/list)
      send_msg "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"tools\":$TOOLS}}" ;;
    tools/call)
      tool="$(printf '%s' "$msg" | jq -r '.params.name')"
      text="$(printf '%s' "$msg" | jq -r '.params.arguments.text')"
      case "$tool" in
        say)    ~/bin/say "$text" &>/dev/null & ;;
        say_ko) ~/bin/say-ko "$text" &>/dev/null & ;;
        *)      send_msg "{\"jsonrpc\":\"2.0\",\"id\":$id,\"error\":{\"code\":-32601,\"message\":\"Unknown tool: $tool\"}}"; continue ;;
      esac
      send_msg "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Spoke: $text\"}]}}" ;;
    *)
      [ -n "$id" ] && send_msg "{\"jsonrpc\":\"2.0\",\"id\":$id,\"error\":{\"code\":-32601,\"message\":\"Unknown method\"}}" ;;
  esac
done
```

Make executable: `chmod +x bin/mcp-tts`

### 4. Register the MCP server with Kiro

In `~/.kiro/agents/default.json`:
```json
{
  "name": "default",
  "mcpServers": {
    "tts": {
      "command": "~/bin/mcp-tts"
    }
  }
}
```

### 5. Add the steering instruction

In `~/.kiro/steering/instructions.md`, add:
```markdown
- **TTS** — at the end of every response, call the `say` MCP tool with a
  brief summary of what was done or answered
```

For a second language, you can tell the agent to translate:
```markdown
- **Korean TTS** — at the end of every response, call the `say_ko` MCP tool
  with a Korean translation of a full summary of what was done or answered
```

## Working Example

A complete working implementation lives at
[github.com/beila/dotfiles](https://github.com/beila/dotfiles). Key files:

| File | What it does |
|------|-------------|
| [`bin/say`](https://github.com/beila/dotfiles/blob/master/bin/say) | English TTS via piper-tts (offline, auto-downloads voice model) |
| [`bin/say-ko`](https://github.com/beila/dotfiles/blob/master/bin/say-ko) | Korean TTS via edge-tts (online, configurable voice/rate) |
| [`bin/mcp-tts`](https://github.com/beila/dotfiles/blob/master/bin/mcp-tts) | MCP server exposing `say` and `say_ko` as tools |
| [`kiro.filesymlink/agents/default.json`](https://github.com/beila/dotfiles/blob/master/kiro.filesymlink/agents/default.json) | Kiro agent config registering the MCP server |
| [`.kiro/steering/instructions.md`](https://github.com/beila/dotfiles/blob/master/.kiro/steering/instructions.md) | Steering instruction telling the agent to call `say_ko` after every response |

In that setup, the agent speaks a Korean summary after every response. The
steering instruction is just one line:

```markdown
- **Korean TTS** — at the end of every response, call the `say_ko` MCP tool
  with a Korean translation of a full summary of what was done or answered
```

The user can say "pause tts" or "resume tts" mid-conversation and the agent
remembers for the rest of the session.

## Customization

- **Add more languages**: add another `say-<lang>` script using edge-tts with a different voice, register it in `mcp-tts`, and reference it in your steering instruction
- **English-only setup**: drop `say_ko` from the MCP server and just use `say`
- **Voice selection**: edge-tts has 400+ voices — run `edge-tts --list-voices` and set `$EDGE_TTS_VOICE`
- **Speed**: adjust `$EDGE_TTS_RATE` (e.g. `+30%`, `-10%`)
- **Pause/resume**: tell the agent "pause tts" / "resume tts" mid-session — it remembers
- **Pre-permission announcement**: tell the agent to call TTS before any tool that requires user permission, starting with a fixed phrase like "running a tool" followed by what specifically it's about to do (e.g. "Running a tool. Updating the TTS guide doc.")

## Dependencies

| Component | Purpose | Install |
|-----------|---------|---------|
| piper-tts | Offline English TTS | `nix profile install nixpkgs#piper-tts` |
| edge-tts | Online multilingual TTS | `uv run --with edge-tts` (or `pip install edge-tts`) |
| ffmpeg | Audio format conversion (edge-tts) | `nix profile install nixpkgs#ffmpeg` |
| jq | JSON parsing in MCP server | `nix profile install nixpkgs#jq` |
| aplay | Audio playback (ALSA, usually pre-installed on Linux) | `alsa-utils` |
