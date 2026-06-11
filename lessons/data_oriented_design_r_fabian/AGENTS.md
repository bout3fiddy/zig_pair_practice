@../../AGENTS.md

# Data-Oriented Design Lesson Pack

This lesson pack studies Richard Fabian's *Data-Oriented Design* through small
Zig exercises. Keep the root `AGENTS.md` as the generic study loop; this file
owns the data-oriented design focus.

## Lesson Order

Lesson notes are numbered by learning progression, not book order. Follow the
filename numbers:

1. `lesson_notes/01_data_shape_tables_cache_lines.md` - foundations: shape data
   for the loop that reads it.
2. `lesson_notes/02_data_formation_framework.md` - pipeline thinking: source
   data versus prepared data, staged state changes.
3. `lesson_notes/03_stream_outputs_and_aliasing.md` - transforms: ownership,
   one-to-one outputs, aliasing contracts.
4. `lesson_notes/04_variable_outputs_and_packed_sets.md` - transforms: output
   cardinality, prefix starts, packed groups.
5. `lesson_notes/05_conditional_work_and_branches.md` - decisions as data:
   move per-row questions into preparation.
6. `lesson_notes/06_existence_based_processing.md` - decisions as data: state
   as table membership, sorted wake-up lists.
7. `lesson_notes/07_lookup_and_indexes.md` - finding things: key streams,
   saved positions, hash/tree choice.
8. `lesson_notes/08_sorting_and_best_value_sets.md` - finding things: partial
   answers, maintained best-N, counting sorts.
9. `lesson_notes/09_optimisation_feedback_strategy.md` - method checkpoint:
   measure, baseline, and report claims honestly.
10. `lesson_notes/10_components_and_managers.md` - architecture: per-component
    tables, update by type, no entity class.
11. `lesson_notes/11_hierarchical_lod_and_mementos.md` - architecture: row
    counts as a budget, mementos, seeded state.
12. `lesson_notes/12_false_sharing.md` - parallelism: worker-local
    accumulation, cache-line interference.
13. `lesson_notes/13_debugging_and_testing_transforms.md` - maintenance:
    lifetimes, kept inputs, table-driven tests.
14. `lesson_notes/14_reusability_and_reusable_functions.md` - maintenance:
    reuse as information preservation.

Paths are relative to `lessons/data_oriented_design_r_fabian/`. Stay in the
current note until the user can explain and apply the idea in a different
small story.

## Study Focus

The core focus is the gap between human/domain input and the smaller runtime
data a loop actually reads. Keep asking the user to separate:

- domain input;
- prepared data;
- hot-loop data;
- output data.

Prefer questions that reveal whether setup and parsing happen before repeated
work, whether the loop receives only the fields it reads, and whether ownership
of buffers and slices is clear.

The next prompt should reveal one concrete DOD question, such as whether a fixed
boolean filter belongs in preparation or in a repeated loop.

For the existence, component, and LOD lessons, also ask whether a state lives
as a flag checked per row or as membership in a table, and whether update code
is organised per instance or per component table.

## DOD Drill Expectations

Use the root drill patterns with these data-oriented interpretations:

- `boundary_audit` - mark domain input, prepared data, hot-loop data, and
  output data.
- `invariant_check` - name one DOD invariant, such as "no allocation inside the
  repeated loop" or "the output slice is caller-owned."
- `contrast_drill` - compare broad domain-shaped code against smaller prepared
  runtime data.
- `regression_prompt` - intentionally move setup back into the loop, add an
  unnecessary branch, pass a larger record than needed, or allocate per item.
- `transfer_check` - repeat the same data-shaping idea with a new story and new
  names.

Inline questions should make the user practice seeing data flow, ownership,
allocation, branches, pointer chasing, and loop shape in code.

## Score Dimensions

Use these score dimensions for this lesson pack:

- `data_shape`
- `boundary_design`
- `loop_reasoning`
- `ownership_lifetimes`
- `allocation_habit`
- `zig_syntax`
- `verification_habit`

Record progress as testable claims, for example: "handles borrowed slices in
fixed-array examples; still needs allocator-owned slice practice."

## Exercise Shape

Use original small Zig tasks. Do not use `prepare_records` naming and do not
copy the chapter's example shape. Keep file-based tasks single-file by default:
structs, arrays, slices, caller-owned buffers or output arrays when useful, one
calculation loop, and a `main` or test that can be run.

## Review Checklist

Assess DOD attempts on:

- Boundary: did parsing/setup happen before the repeated loop?
- Data shape: does the loop receive only the data it actually reads?
- Ownership: are borrowed slices and caller-owned outputs clear?
- Allocation: are allocations outside hot loops unless the task is about them?
- Loop shape: are branches, pointer chasing, and repeated searches intentional?
- Evidence: was the code run, tested, benchmarked, or inspected when useful?
