@../../../../AGENTS.md

# Codegen Evidence Workspace

This folder holds small Zig kernels used as local evidence for the chapter
notes. The assembly, LLVM IR, object file, and benchmark results are
environment-specific generated evidence.

## Prep Command

When the user asks to prep, initialize, or refresh codegen evidence, run the
local examples and update the generated evidence before using the chapter notes.

From the repository root:

```sh
zig build-obj lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.zig \
  -OReleaseFast \
  -fstrip \
  -femit-bin=lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.o \
  -femit-asm=lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.s \
  -femit-llvm-ir=lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.ll
```

Then run:

```sh
zig run lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_bench.zig -OReleaseFast
```

Rewrite `benchmark_results.md` from the fresh benchmark output. Include the Zig
version, target, build mode, date, summarized ratios, and raw output. If chapter
notes quote benchmark ratios or selected assembly, refresh those references from
the newly generated files.

Do not publish generated evidence files. Keep `benchmark_results.md`,
`dod_codegen_examples.o`, `dod_codegen_examples.s`, and
`dod_codegen_examples.ll` local.
