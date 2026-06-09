# Compiler Codegen Notes

These notes look at small Zig kernels that mirror the DOD study examples.
They are compileable shapes used to ask one question: what does the compiler do with this kind of data layout or
loop?

Tracked source:

- [`dod_codegen_examples.zig`](dod_codegen_examples.zig)
- [`dod_codegen_bench.zig`](dod_codegen_bench.zig)
- [`AGENTS.md`](AGENTS.md)

Local generated evidence, not meant for version control:

- `dod_codegen_examples.o`
- `dod_codegen_examples.s`
- `dod_codegen_examples.ll`
- `benchmark_results.md`

Refresh generated evidence using the local instructions in [`AGENTS.md`](AGENTS.md).

Example assembly command:

```sh
zig build-obj lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.zig \
  -OReleaseFast \
  -fstrip \
  -femit-bin=lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.o \
  -femit-asm=lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.s \
  -femit-llvm-ir=lessons/data_oriented_design_r_fabian/lesson_notes/codegen/dod_codegen_examples.ll
```

Do not treat this as a speed claim for the full model. It is compiler evidence
for the source shape on the local toolchain and target.

## How To Read The Assembly

- `x0`, `x1`, `x2` are integer or pointer registers. Function arguments often
  arrive in these registers.
- `d0`, `d1` are 64-bit floating-point registers.
- `q0`, `q1` are 128-bit vector registers. On this target, one `q` register can
  hold two `f64` values.
- `ldr` loads one value from memory. `str` stores one value.
- `ldp` loads a pair of registers. `stp` stores a pair of registers.
- `fadd` adds floating-point values. `fdiv` divides floating-point values.
- `fmadd` computes `a * b + c` in one instruction.
- `fmla.2d` is the vector form of multiply-add for two `f64` lanes.
- `cbz` means "compare with zero and branch if zero."
- `cmp` compares values. `b.*` branches based on a comparison.
- `csel` and `fcsel` choose between two values without a normal branch.
- `lsl #3` means shift left by 3 bits, which is the same as multiplying by 8.
  That often appears when indexing an `f64` array because each `f64` is 8 bytes.

## Lesson Map

| Codegen symbol | Study lessons it supports | Main point |
|---|---|---|
| `sumMetricRows` | Ch. 1.2 + 8.4 + 9.6 | A loop that reads one field from each row can become a simple repeated load/add. |
| `countSideGroupsTable` and `countSideGroupsInline` | Ch. 1.2 + 8.4 + 9.6 | A normalized side-count table adds an indexed lookup; a prepared row answers a hot-path question from the row already being walked. |
| `fillOutputValues` | Ch. 2.7 + 8.5 + 9.3-9.4, Ch. 3.4 + 8.9 | A straight input-to-output transform can vectorize when the memory shape is clear. |
| `fillRatio` | Ch. 2.7 + 8.5 + 9.3-9.4 | Separate read-only inputs and a write-only output give the compiler room to vectorize. |
| `integrateIndexed` | Ch. 6.1-6.2, Ch. 3.4 + 8.9, Ch. 9.2 | A saved index removes search work, but indexed gather loads are still less regular than a plain stream. |
| `lowerBound` | Ch. 6.1-6.2, Ch. 10.3-10.4 | Searching a small key array avoids pulling payload data into the search loop. |
| `sumScoreChain` and `sumScoreStream` | Ch. 9.2 | A pointer chain loads the next address from the current node; a stream walks adjacent values. |
| `refreshDirty` | Ch. 3 + 8.7-8.8 + 9.9 | A dirty list changes the loop length to only the work that must run. |
| `ensureOptionalStorage` | Ch. 3 + 8.7-8.8 + 9.9 | Optional work can be represented as a small count or mask before touching large buffers. |
| `prefixStarts` | Ch. 3.4 + 8.9 | Prefix starts are setup work. They make later variable-length reads cheap. |
| `workerSum` and `sum` | Ch. 9.7 | A local accumulator avoids shared writes inside the loop. |
| `sumSelected` | Ch. 3 + 8.7-8.8 + 9.9 | Random runtime flags still leave branches in the loop. Grouping must happen in data preparation. |

## Contrast Symbols

The chapter notes quote small snippets from these generated files. Use this
table when you want to inspect the whole function instead of only the selected
lines in a chapter.

| Wrong symbol | Better symbol | What to look for |
|---|---|---|
| `sumMetricRowsVerboseRecord` | `sum`, `sumMetricColumn` | Pointer loads from verbose rows versus direct numeric-column loads. |
| `countSideGroupsTable` | `countSideGroupsInline` | Loading `group.id` and indexing a side table versus reading `side_count` from the prepared group row. |
| `appendOutputValuesChecked` | `fillOutputValues` | Capacity checks and length stores inside the loop versus direct output slots. |
| `fillRatioAllocateLike` | `fillRatioNoAlias`, `fillRatio` | Allocator function calls near the boundary versus a direct input/input/output loop. |
| `integrateLinearSearch` | `integrateIndexed` | Repeated search through values versus a saved index load. |
| `sumScoreChain` | `sumScoreStream` | Loading the next pointer from the current node versus walking adjacent scores. |
| `lookupPayloadLinear` | `lowerBound` | Scanning payload rows versus searching a narrow key table. |
| `lowerBoundInModel` | `lowerBound` | Loading through a model wrapper versus passing the key array directly. |
| `refreshScanAllFlags` | `refreshDirty` | A branch over every row versus a loop over known dirty indexes. |
| `startByResummingCounts` | `prefixStarts` | Re-summing variable-length counts versus prepared prefix starts. |
| `workerWriteEveryItem` | `workerSum` | A shared store inside the loop versus one local accumulator and one final write. |
| `sumSelected` | `sumGroupedValues` | A runtime flag branch per item versus grouped values with no per-item flag check. |

## Row Loop: Read Only The Hot Field

Source shape:

```zig
export fn sumMetricRows(rows_ptr: [*]const MetricRow, len: usize) f64 {
    const rows = rows_ptr[0..len];
    var total: f64 = 0.0;
    for (rows) |row| {
        total += row.metric;
    }
    return total;
}
```

Selected assembly:

```asm
ldur    d1, [x9, #-48]  ; load metric from an earlier unrolled row
ldur    d2, [x9, #-24]  ; load metric from the next unrolled row
ldr     d3, [x9]        ; load metric from the row at x9
ldr     d4, [x9, #24]   ; load metric from the following 24-byte row
fadd    d0, d0, d1      ; add the first loaded value into running total d0
fadd    d0, d0, d2      ; add the second loaded value into running total d0
fadd    d0, d0, d3      ; add the third loaded value into running total d0
fadd    d0, d0, d4      ; add the fourth loaded value into running total d0
add     x9, x9, #96     ; advance by four 24-byte MetricRow rows
```

What is happening:

- `MetricRow` is 24 bytes in this example.
- The compiler unrolled the loop by 4 rows.
- The four loads are 24 bytes apart, so they read `metric` from four
  different rows.
- It does not load `group_id`, because the loop does not read that field.

Tie back to the lesson:

- "Make the runtime struct match the loop that reads it" means the compiler
  sees a simple repeated memory pattern.
- If the hot loop only needs one metric, keeping unrelated names, parser
  state, or debug text out of the row prevents those fields from being dragged
  through the loop.
- This is still an array-of-structs walk. It is clean, but not the same as a
  pure `[]f64` metric column.

## Nearby Field: Answer The Question From The Row

Source shape:

```zig
const side_index: usize = @intCast(group.id);
if (side_counts_ptr[side_index] != 0) {
    groups_with_side_items += 1;
}
```

Selected assembly:

```asm
ldr     w11, [x10], #12          ; load group.id, then advance group pointer
ldrh    w11, [x1, x11, lsl #1]   ; load side_counts[group.id]
cmp     w11, #0                  ; test side_count
cinc    x8, x8, ne               ; count this group when nonzero
```

What is happening:

- The loop walks group rows.
- It loads `group.id`.
- It uses that id to load a separate `side_counts` table.
- The second load answers a question the loop asks for every group.

The prepared-row version keeps the side count in the row.

```zig
if (group.side_count != 0) {
    groups_with_side_items += 1;
}
```

Selected assembly:

```asm
ldrh    w11, [x9], #12  ; load group.side_count, then advance group pointer
cmp     w11, #0         ; test side_count
cinc    x8, x8, ne      ; count this group when nonzero
```

Tie back to the lesson:

- Tables are a runtime choice, not a normal form rule.
- If the hot loop already walks the group row and always asks for side-item
  presence, keeping `side_count` beside the range data removes a lookup.
- This is cache-line awareness with a boundary: keep nearby bytes useful to the
  repeated question, not broadly domain-shaped.

## Straight Transform: One Input Row Writes One Output Row

Source shape:

```zig
export fn fillOutputValues(rows_ptr: [*]const MetricRow, out_ptr: [*]f64, len: usize, scale: f64) void {
    const rows = rows_ptr[0..len];
    const out = out_ptr[0..len];
    for (rows, out) |row, *dst| {
        dst.* = @mulAdd(f64, row.metric, row.weight, scale);
    }
}
```

Selected assembly:

```asm
ld3.2d   { v2, v3, v4 }, [x12]  ; load interleaved struct fields into vector registers
fmla.2d  v22, v3, v2            ; compute two f64 multiply-add lanes
stp      q22, q2, [x9, #-32]    ; store two vector registers to output memory
```

What is happening:

- `ld3.2d` loads fields from interleaved structs into separate vector registers.
- `fmla.2d` performs vector multiply-add on two `f64` lanes.
- `stp q...` stores vector results to the output array.
- Before this vector loop, the compiler emits overlap checks. If input and
  output might overlap in a bad way, it falls back to a simpler scalar loop.

Tie back to the lesson:

- A one-row-to-one-row transform is easy for the compiler to understand.
- Separate input and output slices make the read side and write side visible.
- The compiler can vectorize the straight path, but only after it proves the
  output writes will not clobber unread input.
- This is why the notes keep saying "make reads and writes explicit." It is not
  only for human readability. It affects what the compiler can safely do.

## Ratio: Read Inputs, Write Output

Source shape:

```zig
for (numerator, denominator, out) |l, e, *dst| {
    dst.* = if (e != 0.0) l / e else 0.0;
}
```

Selected scalar assembly:

```asm
ldr     d1, [x11], #8  ; load one numerator f64, then advance numerator pointer
ldr     d2, [x10], #8  ; load one denominator f64, then advance denominator pointer
fdiv    d1, d1, d2     ; divide numerator by denominator
fcmp    d2, #0.0       ; compare denominator with zero
fcsel   d1, d1, d0, ne ; keep division result if nonzero, otherwise choose 0.0
str     d1, [x9], #8   ; store one ratio f64, then advance output pointer
```

Selected vector assembly:

```asm
ldp       q0, q1, [x10, #-32]  ; load two vectors of numerator values
ldp       q4, q5, [x11, #-32]  ; load two vectors of denominator values
fcmeq.2d  v16, v4, #0.0        ; build a mask for lanes where denominator is zero
fdiv.2d   v0, v0, v4           ; divide two f64 numerator lanes by denominator lanes
bic.16b   v0, v0, v16          ; clear result lanes where the zero mask is set
stp       q0, q1, [x9, #-32]   ; store two output vectors
```

What is happening:

- The scalar path loads one numerator and one denominator, divides, checks for
  zero, then stores one output.
- The vector path handles several `f64` values at once.
- The zero check becomes a mask in the vector path instead of a normal branch.

Tie back to the lesson:

- Keeping `numerator` and `denominator` read-only and `out` writable gives a clean
  input/input/output loop.
- The zero rule is still visible in machine code. Data-oriented design does not
  remove metrics or correctness rules.
- The benefit is that the data shape lets the compiler express the rule in a
  tight vector loop.

## Saved Index Plan: No Search In The Hot Loop

Source shape:

```zig
const result_index: usize = @intCast(sample_indices_ptr[k]);
integrated += results_ptr[result_index].numerator;
```

Selected assembly:

```asm
ldr     w11, [x1, x9, lsl #2]  ; load one saved u32 result index
lsl     x11, x11, #4           ; multiply index by 16 bytes per ResultValue row
ldr     d1, [x2, x11]          ; load numerator from the indexed result row
fadd    d0, d0, d1             ; add numerator into the integration total
```

What is happening:

- `x1` is the pointer to `sample_indices`.
- `x9` is the current index into that index list.
- `lsl #2` multiplies by 4 because each `u32` index is 4 bytes.
- `lsl #4` multiplies the loaded result index by 16 because `ResultValue` is
  16 bytes in this example.
- The final `ldr d1` reads `numerator` from the selected result row.

Tie back to the lesson:

- The hot loop does not search for the matching id or hash anything.
  It follows saved positions.
- That is the win from an index.
- The codegen also shows the cost that remains: this is still an indexed gather.
  The next address depends on the loaded index, so it is less regular than a
  plain `for (values)` stream.
- This is why an index is useful but not magic. It removes lookup work; it does
  not make random memory access sequential.

## Pointer Chain: Next Address Comes From Current Node

Source shape:

```zig
while (node) |current| {
    total += current.score;
    node = current.next;
}
```

Selected assembly:

```asm
ldr     d1, [x0]      ; load current.score
fadd    d0, d0, d1    ; add the score
ldr     x0, [x0, #8]  ; load current.next
cbnz    x0, LBB11_2   ; repeat only after next is known
```

What is happening:

- `x0` is the current node pointer.
- The loop loads the score from the current node.
- The next node pointer also comes from the current node.
- The branch cannot continue until that next pointer has been loaded.

Tie back to the lesson:

- This is the memory-dependency problem Fabian is pointing at.
- Each iteration discovers the next address from data that just arrived.
- A plain score stream has a visible next address: the next slot in the array.

The stream version calls the shared `sum` body, which walks adjacent `f64`
values.

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent scores
ldp     q5, q6, [x9], #64   ; load four more and advance
fadd    d0, d0, d1          ; add loaded score lanes
fadd    d0, d0, d3
```

## Key Lookup: Search The Key Table, Not The Payload

Source shape:

```zig
const mid = low + (high - low) / 2;
if (values[mid] < needle) {
    low = mid + 1;
} else {
    high = mid;
}
```

Selected assembly:

```asm
sub     x9, x1, x8           ; compute high - low
add     x9, x8, x9, lsr #1   ; compute mid = low + ((high - low) / 2)
ldr     d1, [x0, x9, lsl #3] ; load values[mid], using mid * 8 bytes for f64
fcmp    d1, d0               ; compare values[mid] with the needle
csinc   x8, x8, x9, pl       ; keep low, or set low to mid + 1 when value < needle
csel    x1, x1, x9, mi       ; keep high when value < needle, otherwise set high to mid
```

What is happening:

- `sub` and `add ... lsr #1` compute the midpoint.
- `ldr d1, [x0, x9, lsl #3]` loads `values[mid]`.
- The shift by 3 is `mid * 8`, because `f64` is 8 bytes.
- `fcmp` compares the table value with the needle.
- `csinc` and `csel` update `low` and `high` with conditional select
  instructions.

Tie back to the lesson:

- The search only loads the key array.
- The payload table is not touched until after the index is known.
- This is the codegen reason to keep lookup keys separate from large payloads:
  the search loop stays small.

## Dirty List: Loop Only Over Work That Is Dirty

Source shape:

```zig
for (values, out) |value, *dst| {
    dst.* = value * 2.0 + 1.0;
}
```

Selected assembly:

```asm
ldp       q1, q2, [x10, #-32]  ; load vectors of dirty id values
fadd.2d   v1, v1, v1           ; double two f64 lanes: id * 2.0
fadd.2d   v1, v1, v0           ; add the 1.0 vector to those lanes
stp       q1, q2, [x9, #-32]   ; store refreshed id values
```

What is happening:

- The compiler vectorizes the loop over the dirty id list.
- `fadd.2d v1, v1, v1` doubles the id values.
- The next `fadd.2d` adds `1.0`.
- It stores the refreshed values in order.

Tie back to the lesson:

- The compiler optimizes the loop it is given.
- It does not know about every possible id. The offset code already
  narrowed the work to `dirty_len`.
- The DOD move is building the list of dirty rows before this loop.

## Optional Work: Count Or Mask Before Touching Buffers

Source shape:

```zig
if (states_count == 0) {
    return 0;
}
if (capacity >= states_count) {
    return capacity;
}
return states_count;
```

Selected assembly:

```asm
cmp     x1, x0          ; compare capacity with requested state count
csel    x8, x1, x0, hi  ; choose capacity if larger, otherwise choose count
cmp     x0, #0          ; check whether requested state count is zero
csel    x0, xzr, x8, eq ; return 0 for no work, otherwise return chosen size
```

What is happening:

- The compiler turns the small choices into conditional selects.
- There is no loop here and no allocation call in this tiny example.

Tie back to the lesson:

- The important idea is deciding whether optional work exists before
  touching big storage.
- In real code, this can keep optional buffers, temporary terms, or extra
  support out of paths that do not need them.
- Codegen for this tiny function shows the decision is cheap. It does not prove
  the full product run is faster.

## Prefix Starts: Setup For Variable-Length Sets

Source shape:

```zig
starts[0] = 0;
var i: usize = 1;
while (i < len) : (i += 1) {
    starts[i] = starts[i - 1] + counts[i - 1];
}
```

Selected assembly:

```asm
str     wzr, [x1]       ; write 0 to starts[0]
ldr     w11, [x0], #4   ; load the next count, then advance counts pointer
add     w9, w11, w9     ; add count to the running prefix total
str     w9, [x10], #4   ; store the next start, then advance starts pointer
```

What is happening:

- `str wzr, [x1]` writes zero to `starts[0]`.
- Each loop reads the next count, adds it to the running total, and writes one
  start value.
- This loop is scalar because each output depends on the previous sum.

Tie back to the lesson:

- Prefix starts are preparation work for variable-length data.
- The setup loop has a dependency, but after it runs, the hot code can use
  `start` and `count` directly.
- This is a normal DOD trade: pay a simple setup pass so repeated reads do not
  search or resize.

## Worker Local Sum: No Shared Write Inside The Loop

Source shape:

```zig
var local: f64 = 0.0;
var i = start;
while (i < end) : (i += 1) {
    local += values_ptr[i];
}
return local;
```

Selected assembly:

```asm
ldp     q1, q2, [x10, #-32]  ; load two vector registers of input values
ldp     q5, q6, [x10], #64   ; load two more vectors, then advance pointer
fadd    d0, d0, d1           ; add one loaded f64 lane into accumulator d0
fadd    d0, d0, d3           ; add another loaded f64 lane into accumulator d0
fadd    d0, d0, d2           ; add another loaded f64 lane into accumulator d0
fadd    d0, d0, d4           ; add another loaded f64 lane into accumulator d0
```

What is happening:

- The compiler unrolls the loop and loads several values per pass.
- The running total stays in floating-point register `d0`.
- There is no store inside the repeated loop.

Tie back to the lesson:

- For false sharing, the offset lesson is "do the repeated accumulation in
  worker-local state."
- Codegen shows the local state is a register, not a shared memory slot.
- A shared write can happen once after the worker returns its final sum.

## Branchy Selection: Runtime Flags Stay Branchy

Source shape:

```zig
for (flags, values) |flag, value| {
    if (flag != 0) {
        selected_total += value;
    }
}
```

Selected assembly:

```asm
ldrb    w10, [x8], #1  ; load one flag byte, then advance flag pointer
cbz     w10, LBB22_5   ; branch over the add when the flag is zero
ldr     w10, [x11]     ; load the value only for a nonzero flag
add     w0, w10, w0    ; add that value into the selected total
```

What is happening:

- `ldrb` loads one flag byte.
- `cbz` branches when the flag is zero.
- Only when the flag is nonzero does the code load the value and add it.
- The compiler unrolls parts of this loop, but the per-flag branches remain.

Tie back to the lesson:

- If flags are random, the CPU may guess these branches badly.
- The compiler cannot know the future flag pattern.
- The DOD fix is to group rows before the hot loop when that grouping is worth
  its cost. Then the hot loop can run one path without asking the same question
  for every row.
- The benchmark harness times both the already-grouped sum and the full
  group-then-sum path. Use the already-grouped number only when the selected
  list is reused or prepared by an earlier boundary.

## When Codegen Is The Wrong Tool

Some study sections are still important, but compiler output is not the first
thing to inspect:

- Ch. 1.5-1.6 is about data formation and explicit state changes.
  Codegen of the top-level wrapper mostly shows calls. The useful check is the
  source boundary: which data shape is produced and which phase consumes it.
- Ch. 8.1-8.3 is a measurement loop. It does not need assembly. The output is a
  short benchmark note: problem, baseline, workload, change, result, and
  checksum.
- Ch. 10.3-10.4 includes reusable source shapes. Codegen is useful for the small
  function examples, such as `lowerBound`, but not for proving a high-level
  reuse sequence.

Use codegen when the question is concrete:

- Did this hot loop vectorize?
- Is there still a branch inside the per-row loop?
- Did the hot function still call an allocator, formatter, hash map, or parser?
- Does the loop load only the fields it claims to read?
- Did an index remove search work, or did a search remain?
