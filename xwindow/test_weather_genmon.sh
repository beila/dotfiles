#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture="$root/xwindow/test_weather_genmon.json"

curl() {
    local url=${!#}
    if [[ $url != "$WEATHER_TEST_URL" ]]; then
        printf 'unexpected weather URL: %s\n' "$url" >&2
        return 1
    fi
    cat "$WEATHER_TEST_FIXTURE"
}
export -f curl

output=$(
    WEATHER_TEST_FIXTURE="$fixture" \
        WEATHER_TEST_URL="https://wttr.in/51.460,0.107?format=j1" \
        WEATHER_NOW="2026-10-27T08:00:00" \
        "$root/xwindow/bin/weather-genmon"
)

printf '%s\n' "$output" | rg -q '09:00.*☀️.*rain[[:space:]]+0%.*Sunny'
printf '%s\n' "$output" | rg -q '12:00.*🌧.*rain[[:space:]]+80%.*Light rain'
printf '%s\n' "$output" | rg -q '21:00.*🌙.*rain[[:space:]]+0%.*Clear'
printf '%s\n' "$output" | rg -q '☀️.*rain[[:space:]]+0%.*Clear'
printf '%s\n' "$output" | rg -q '🌧.*rain[[:space:]]+75%.*Heavy rain'
printf '%s\n' "$output" | rg -q '<tool>Welling, London'

printf 'PASS: weather forecast condition icons\n'
