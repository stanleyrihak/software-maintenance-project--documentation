# Technical documentation: ML-KEM Legacy Modernization

Sources for the technical documentation of
[Software-Development-and-Maintenance-Project](https://github.com/Rolko6/Software-Development-and-Maintenance-Project).
The documentation is written in Markdown and built into a PDF.

## Build the PDF

```sh
brew install pandoc typst      # once
./build.sh                     # metadata.yaml + chapters in chapters.txt -> technical-documentation.pdf
./build.sh notes.md            # any single Markdown file -> notes.pdf
```

Diagrams are written in Mermaid (`figures/*.mmd`). `build.sh` turns a changed
diagram into a PDF with `npx @mermaid-js/mermaid-cli`, which needs Node.js and
downloads a headless browser on first use. The generated diagram PDFs are
committed, so building without changing a diagram needs only pandoc and typst.

## Files

| Path | Purpose |
|---|---|
| `metadata.yaml` | title page: title, team, version, date; table of contents settings |
| `chapters.txt` | which chapters go into the PDF, and in which order (`#` leaves a line out) |
| `chapters/NN-*.md` | the documentation, one file per chapter (order and selection set in `chapters.txt`): introduction, baseline analysis, ML-KEM integration, operations, AI-assisted development, critical evaluation and maintenance, final evaluation, appendix |
| `template/report.typst` | page layout: title page, fonts, colours, header and footer |
| `figures/` | figures: Mermaid diagram sources (`.mmd`) with their rendered PDFs, and other images such as screenshots |
| `build.sh` | builds the PDF |

## Writing

The chapters follow the course brief's list of required work, one chapter per
item. HTML comments (`<!-- ... -->`) are not printed in the PDF and can hold
notes for the authors. Pull before you start and push often; working on
different chapters avoids merge conflicts. Open `TODO`s are marked in
`metadata.yaml` and in chapter 4 (continuous delivery).

Insert a diagram with `![Caption.](figures/name.pdf){width=60%}` after adding
`figures/name.mmd`. Other images (PNG, JPG, PDF) go into `figures/` too and are
inserted the same way.

`figures/tests.svg` (the pie chart of test counts) is not built from Mermaid:
Mermaid can only show percentages inside the slices, so the counts were written
into the SVG by hand. Edit the numbers in the file if the test counts change.
