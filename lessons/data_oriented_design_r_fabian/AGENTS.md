@../../AGENTS.md

# Data-Oriented Design Lesson Pack

This lesson pack studies Richard Fabian's *Data-Oriented Design* through small
Zig exercises. Keep the root `AGENTS.md` as the generic study loop; this file
owns the data-oriented design focus.

## Lesson Order

Start with
`lessons/data_oriented_design_r_fabian/lesson_notes/ch01_02_data_is_not_problem_domain.md`.
Continue through `lesson_notes/` in chapter/section filename order. Stay in the
current note until the user can explain and apply the idea in a different small
story.

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
