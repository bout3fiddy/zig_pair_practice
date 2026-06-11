# Fabian Book Section Notes

This folder contains personal notes keyed by lesson title. Filenames carry a
two-digit prefix giving the study progression, which is ordered for learning
and difficulty rather than book chapter order: machine foundations (01-02),
the transform pipeline (03-05), decisions as data (06-07), search and sort
structures (08-09), a measurement-method checkpoint (10), architecture scale
(11-12), parallelism (13), and maintenance (14-15). Closely related Richard
Fabian book sections may share one file when they are best practiced as one
lesson. Each file extracts:

- the Fabian philosophy to practice;
- how Fabian gets to that idea;
- the take-home rule;
- the main lesson details;
- the relevant code or table idea where code actually helps explain the lesson,
  adapted as short pseudocode instead of reproducing long book listings
  verbatim;

Many chapter compiler notes include a `Wrong pattern` or `Wrong evidence`
snippet. Those snippets are not recommendations. They mean "wrong for this hot
loop or study claim," not "always wrong in every program." They are included so
the better pattern is easier to see, and each one is tied to a compiler
artifact or benchmark result where possible.

Compiler-output companion notes live in
[`codegen/README.md`](codegen/README.md). They compile small Zig kernels that
mirror the lesson shapes and explain generated code on the local target.

Source: <https://www.dataorienteddesign.com/dodbook/>. Each chapter note links
to the matching online section and keeps the printed-book page number only as a
locator for readers using the 2018 paper book.
