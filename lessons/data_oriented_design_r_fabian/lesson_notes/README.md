# Fabian Book Section Notes

This folder contains personal notes keyed by Richard Fabian book
chapter/section. Each file extracts:

- the main lesson to practice;
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
