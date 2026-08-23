#!/usr/bin/env bash
# CI gate for the full-localization-web-apps OpenSpec change (sweetrpg/platform): fails if a
# Leaf template contains user-facing text that isn't served from Resources/Localizations via
# #(meta.l10n.<key>). Brand names and the footer build line are allowlisted.
set -euo pipefail

cd "$(dirname "$0")/.."

# "built" is part of the footer build line, which is deliberately not localized.
allowlist='SweetRPG|GitHub|Pilgrimage Software|built'
violations=0

while IFS= read -r -d '' file; do
    # Strip <script>/<style> blocks, HTML comments, and Leaf comments, then keep only text
    # between tags.
    content=$(perl -0777 -pe '
    s/<script\b[^>]*>.*?<\/script>//gis;
    s/<style\b[^>]*>.*?<\/style>//gis;
    s/<!--.*?-->//gs;
    s/#\(\*.*?\*\)//gs;
    s/#\((?:[^()]|\([^()]*\))*\)//g;
    s/#[a-zA-Z]+(?:\((?:[^()]|\([^()]*\))*\))?:?//g;
  ' "$file" | perl -0777 -ne '
    while (/>([^<]+)</g) { print "$1\n"; }
  ')
    while IFS= read -r text; do
        [ -z "$text" ] && continue
        # Skip whitespace/punctuation-only fragments and HTML entities.
        stripped=$(printf '%s' "$text" | perl -pe 's/&[a-zA-Z#0-9]+;|[\s[:punct:]]//g')
        [ -z "$stripped" ] && continue
        if ! printf '%s' "$text" | grep -Eq "$allowlist"; then
            echo "Hardcoded string in $file: $text"
            violations=$((violations + 1))
        fi
    done <<<"$content"
done < <(find Resources/Views -name '*.leaf' -print0)

if [ "$violations" -gt 0 ]; then
    echo "Found $violations hardcoded template string(s). Move them to Resources/Localizations/*.json and use #(meta.l10n.<key>)."
    exit 1
fi
