# Technical documentation: ML-KEM Legacy Modernization

Sources for the technical documentation of
[Software-Development-and-Maintenance-Project](https://github.com/Rolko6/Software-Development-and-Maintenance-Project).
The documentation is written in Markdown and built into a PDF.

## Build the PDF

```sh
brew install pandoc typst      # once
./build.sh                     # metadata.yaml + chapters/*.md -> technical-documentation.pdf
./build.sh sample.md           # a single Markdown file -> sample.pdf
```

Diagrams are written in Mermaid (`diagrams/*.mmd`). `build.sh` turns a changed
diagram into a PDF with `npx @mermaid-js/mermaid-cli`, which needs Node.js and
downloads a headless browser on first use. The generated diagram PDFs are
committed, so building without changing a diagram needs only pandoc and typst.

## Files

| Path | Purpose |
|---|---|
| `metadata.yaml` | title page: title, team, version, date; table of contents settings |
| `chapters/NN-*.md` | the documentation, one file per chapter, joined in number order: introduction, baseline analysis, ML-KEM integration, operations, AI-assisted development, critical evaluation and maintenance, final evaluation, appendix |
| `template/report.typst` | page layout: title page, fonts, colours, header and footer |
| `diagrams/` | Mermaid sources (`.mmd`) and their rendered PDFs |
| `build.sh` | builds the PDF |
| `sample.md` | layout sample |

## Writing

The chapters follow the course brief's list of required work, one chapter per
item. HTML comments (`<!-- ... -->`) are not printed in the PDF and can hold
notes for the authors. Pull before you start and push often; working on
different chapters avoids merge conflicts. Open `TODO`s are marked in
`metadata.yaml` and in chapter 4 (continuous delivery).

Insert a diagram with `![Caption.](diagrams/name.pdf){width=60%}` after adding
`diagrams/name.mmd`.
