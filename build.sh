#!/usr/bin/env bash
# Build PDFs from the Markdown sources in this folder.
#   ./build.sh                          -> builds technical-documentation.pdf
#   ./build.sh sample.md                -> builds sample.pdf
# Needs: pandoc, typst (brew install pandoc typst) and Node.js for diagrams.
set -euo pipefail
cd "$(dirname "$0")"

SOURCE="${1:-technical-documentation.md}"
OUTPUT="${SOURCE%.md}.pdf"

# Render each Mermaid diagram to a vector PDF when its source is newer.
for mmd in diagrams/*.mmd; do
  [ -e "$mmd" ] || continue
  out="${mmd%.mmd}.pdf"
  if [ ! -e "$out" ] || [ "$mmd" -nt "$out" ]; then
    echo "diagram: $mmd -> $out"
    npx -y @mermaid-js/mermaid-cli@11 -q -i "$mmd" -o "$out" -c diagrams/mermaid-config.json --pdfFit
  fi
done

pandoc "$SOURCE" \
  --from markdown \
  --pdf-engine=typst \
  --template=template/report.typst \
  --resource-path=. \
  -o "$OUTPUT"

echo "built: $OUTPUT"
