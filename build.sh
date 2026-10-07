#!/usr/bin/env bash
# Build PDFs from the Markdown sources in this folder.
#   ./build.sh               -> technical-documentation.pdf from metadata.yaml + chapters/*.md
#   ./build.sh sample.md     -> sample.pdf from a single Markdown file
# Needs: pandoc, typst (brew install pandoc typst) and Node.js for changed diagrams.
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -gt 0 ]; then
  SOURCES=("$1")
  METADATA=()
  OUTPUT="${1%.md}.pdf"
else
  # Chapters are joined in file-name order (01-, 02-, ...).
  SOURCES=(chapters/*.md)
  METADATA=(--metadata-file=metadata.yaml)
  OUTPUT="technical-documentation.pdf"
fi

# Render each Mermaid diagram to a vector PDF when its source is newer.
for mmd in diagrams/*.mmd; do
  [ -e "$mmd" ] || continue
  out="${mmd%.mmd}.pdf"
  if [ ! -e "$out" ] || [ "$mmd" -nt "$out" ]; then
    echo "diagram: $mmd -> $out"
    npx -y @mermaid-js/mermaid-cli@11 -q -i "$mmd" -o "$out" -c diagrams/mermaid-config.json --pdfFit
  fi
done

pandoc "${SOURCES[@]}" ${METADATA[@]+"${METADATA[@]}"} \
  --from markdown \
  --pdf-engine=typst \
  --template=template/report.typst \
  --resource-path=. \
  -o "$OUTPUT"

echo "built: $OUTPUT"
