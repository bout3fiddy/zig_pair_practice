# Data-Oriented Design Study: R. Fabian

This folder contains personal study notes based on Richard Fabian's
*Data-Oriented Design*. It is a lesson pack for guided Zig practice, not a
refactor plan.

## Book Source

Use Richard Fabian's book as the source of record:

- Free online reduced version:
  <https://www.dataorienteddesign.com/dodbook/>
- Paper book:
  <https://www.amazon.com/dp/1916478700>
- Google Books reference:
  <https://books.google.com/books/about/Data_oriented_Design.html?id=_XShvAEACAAJ>
- Barnes & Noble listing:
  <https://www.barnesandnoble.com/w/data-oriented-design-richard-fabian/1139451623?ean=9781916478701>

ISBN: `9781916478701`.

The online page says this is the free online reduced version of
*Data-Oriented Design* by Richard Fabian. Some formatting, images, and listings
may be imperfect because the HTML was generated from the book source.

Do not commit a local PDF copy into this study folder. Chapter files should
link to the matching online section. Printed-book page numbers are kept only as
orientation hints for people using the 2018 paper book.

## Files

- `lesson_notes/` - one study note per Fabian section.
- `lesson_notes/codegen/README.md` - compiler-output companion for representative
  Zig lesson shapes.
- `lesson_notes/codegen/benchmark_results.md` - local microbenchmark numbers used
  by the chapter compiler notes.

## How To Extend This Study

When adding a new entry:

- add or update one `lesson_notes/` chapter note when the lesson needs a
  plain-language explanation;
- include a `Wrong pattern` / `Better pattern` contrast when it makes the lesson
  easier to see;
- back performance claims with a benchmark, trace, compiler output, or another
  concrete artifact. Code shape alone is not proof;
- do not commit local PDFs or generated object files.
