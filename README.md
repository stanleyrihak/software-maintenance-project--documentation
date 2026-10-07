# Technical documentation: ML-KEM Legacy Modernization

Sources for the technical documentation of
[Software-Development-and-Maintenance-Project](https://github.com/Rolko6/Software-Development-and-Maintenance-Project).
The documentation is written in Markdown and built into a PDF.

## Build the PDF

```sh
brew install pandoc typst      # once
./build.sh                     # technical-documentation.md -> technical-documentation.pdf
./build.sh sample.md           # any other Markdown file in this folder
```

Diagrams are written in Mermaid (`diagrams/*.mmd`). `build.sh` turns a changed
diagram into a PDF with `npx @mermaid-js/mermaid-cli`, which needs Node.js and
downloads a headless browser on first use. The generated diagram PDFs are
committed, so building without changing a diagram needs only pandoc and typst.

## Files

| Path | Purpose |
|---|---|
| `technical-documentation.md` | the documentation (to be written) |
| `sample.md` | layout sample |
| `template/report.typst` | page layout: title page, fonts, colours, header and footer |
| `diagrams/` | Mermaid sources (`.mmd`) and their rendered PDFs |
| `build.sh` | builds the PDF |
