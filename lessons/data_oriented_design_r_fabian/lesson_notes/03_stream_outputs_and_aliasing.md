# Stream Outputs And Aliasing

Sources:

- [Data-Oriented Design online book, "Stream Processing"](https://www.dataorienteddesign.com/dodbook/node3.html#SECTION00370000000000000000) (printed-book p54).
- [Data-Oriented Design online book, "Transforms"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00950000000000000000) (printed-book p151).
- [Data-Oriented Design online book, "Reducing order dependence"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001010000000000000000) (printed-book p163).
- [Data-Oriented Design online book, "Write buffer awareness"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001030000000000000000) (printed-book p165).
- [Data-Oriented Design online book, "Aliasing"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001040000000000000000) (printed-book p166).
- [Data-Oriented Design online book, "Auto vectorisation"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION0010110000000000000000) (printed-book p174).

Philosophy: Fabian frames transforms as stream or set processing: prepared
inputs, no hidden global accumulator, no write to state outside the process, and
an explicit output shape. That makes order less important and parallel execution
easier to reason about.

How Fabian gets there: He moves from database tables as unordered sets and GPU
shader kernels to schema iterators, map/reduce, write-buffer behavior, and
aliasing. The same pattern keeps appearing: hidden writes, mixed read/write
state, and pointer overlap make the transform harder for people, threads, and
the compiler.

Take home: Separate setup and gathering from the repeated kernel. Pass clear
read-only inputs and caller-owned output or scratch storage, write
contiguously, and avoid aliases or external writes in the hot step.

## Main Lessons

- A stream transform runs the same step over many rows.

  ```zig
  for (jobs, results) |job, *result| {
      result.* = runJob(job, constants);
  }
  ```

  One `job` produces one `result`. The loop does not depend on hidden state from
  another row.

- Put input, temporary memory, and output in the function boundary.

  ```zig
  fn fillScores(jobs: []const Job, scratch: *Scratch, out: []f64) !void {
      for (jobs, out) |job, *dst| dst.* = try scoreJob(job, scratch);
  }
  ```

  The signature shows the input rows, scratch memory, and output rows.

- Let the caller keep output memory between runs.

  ```zig
  try storage.output_values.resize(allocator, item_count);
  fillOutputs(storage.input_values.items, storage.output_values.items);
  ```

  The run fills existing storage instead of making a new output array from
  scratch.

- Mark input slices read-only and keep output separate.
  `[]const` says the function will not write through the input slice. The caller
  still needs to keep input and output from overlapping when the loop depends on
  that.

  ```zig
  fn fillRatio(
      numerator: []const f64,
      denominator: []const f64,
      output: []f64,
  ) void {
      for (numerator, denominator, output) |top, bottom, *dst| {
          dst.* = if (bottom != 0.0) top / bottom else 0.0;
      }
  }
  ```

## Practical Example

A calibration report has one prepared reading per sensor sample and one score
per reading. The weak shape treats the output as if its length were unknown and
lets the transform grow the list while it runs.

```zig
pub fn appendCalibrationScores(
    rows: []const MetricRow,
    scale: f64,
    results: *ArrayList(f64),
) !void {
    for (rows) |row| {
        try results.append(@mulAdd(f64, row.metric, row.weight, scale));
    }
}
```

The compiler output below is generated machine code. It makes the capacity
check, length update, and store visible.

```asm
ldr     x9, [x1, #16]          ; load output capacity
cmp     x0, x9                 ; compare current length with capacity
b.hs    LBB5_4                 ; branch out if the list is full
ldr     x9, [x1]               ; load output items pointer
fmadd   d1, d2, d1, d0         ; compute the calibration score
str     d1, [x9, x0, lsl #3]   ; store at items[len]
ldr     x9, [x1, #8]           ; reload the output length
add     x0, x9, #1             ; advance the output length
str     x0, [x1, #8]           ; write the updated length
```

The append-style loop carries output-list bookkeeping in the repeated path.
That bookkeeping is not part of calibration. It is a result of choosing an
output-owning API for a one-to-one transform.

A better approach sizes the output ahead of time and writes each result into
its slot.

```zig
pub fn fillCalibrationScores(
    rows: []const MetricRow,
    scale: f64,
    out: []f64,
) void {
    for (rows, out) |row, *dst| {
        dst.* = @mulAdd(f64, row.metric, row.weight, scale);
    }
}
```

The generated output for the explicit transform is a regular input/output
loop.

```asm
fmla.2d  v22, v3, v2           ; do two f64 multiply-adds in one vector register
stp      q22, q2, [x9, #-32]   ; store two vector registers into output slots
```

The same report later computes a ratio from two prepared columns. Allocating
that output inside the fill puts allocation calls around the repeated write.

```zig
pub fn makeRatios(
    allocator: Allocator,
    numerator: []const f64,
    denominator: []const f64,
) ![]f64 {
    const out = try allocator.alloc(f64, numerator.len);
    for (numerator, denominator, out) |top, bottom, *dst| {
        dst.* = if (bottom != 0.0) top / bottom else 0.0;
    }
    return out;
}
```

The compiler output makes the allocation and cleanup calls visible.

```asm
ldr     x8, [x0]       ; load allocator.alloc function pointer
mov     x0, x3         ; pass output length to allocator
blr     x8             ; call allocator before writing output
ldr     x8, [x19, #8]  ; load allocator.free function pointer
blr     x8             ; call free after using output
```

Caller-owned output leaves the repeated work as loads, selects, and stores.

```zig
pub fn fillRatios(
    numerator: []const f64,
    denominator: []const f64,
    out: []f64,
) void {
    for (numerator, denominator, out) |top, bottom, *dst| {
        dst.* = if (bottom != 0.0) top / bottom else 0.0;
    }
}
```

The LLVM output shows the vector loads, select, and output store.

```llvm
%wide.load = load <2 x double>, ptr ...
%17 = select <2 x i1> %9, <2 x double> %13, <2 x double> zeroinitializer
store <2 x double> %17, ptr ...
```

Input/output ownership also affects whether the compiler must check for overlap
before entering a vector loop.

```asm
sub     x9, x2, x0  ; compute distance between output and first input
cmp     x9, #64     ; check whether the slices might overlap
b.lo    LBB6_3      ; use scalar fallback if overlap is too close
sub     x9, x2, x1  ; repeat the overlap check for the second input
cmp     x9, #64     ; check whether output is too close to that input
b.lo    LBB6_3      ; use scalar fallback if this pair might overlap
```

Those checks exist because the function signature allows a caller to pass
overlapping slices, so the compiler ships both a vector loop and a scalar
fallback and decides at runtime. Zig can state the contract instead: marking
the parameters `noalias` promises the slices never overlap, and the generated
function for the same loop body enters the vector path directly, with the
distance checks gone. Read the progression in the machine code: an API that
owns its output pays allocator calls, an API that appends pays bookkeeping per
element, an API that fills caller-owned slices pays runtime overlap checks,
and an API that declares its aliasing contract pays only the loads, the math,
and the stores. The signature is not documentation; it is part of the
generated code.

A benchmark for caller-owned output showed it was `1.61x` faster than
allocating output every run, with the same checksum.

Two compiler-facing habits round out this lesson. Fabian's "Reducing order
dependence" point is that a loop body written in single-assignment style, with
each value computed once from named inputs, lets the compiler prove that
iterations do not depend on each other. His auto-vectorisation point is the
payoff: straight loops over separate read-only inputs and one output, with no
early exits on loaded data, are exactly the loops a compiler can turn into the
vector code shown above.
