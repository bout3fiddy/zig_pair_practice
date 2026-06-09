# Reusability And Reusable Functions

Sources:

- [Data-Oriented Design online book, "Reusability"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001130000000000000000) (printed-book p183).
- [Data-Oriented Design online book, "Reusable functions"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001140000000000000000) (printed-book p186).

Philosophy: Fabian argues that reuse is the preservation of useful information,
not the reuse of a source file or class. The reusable thing is the known
sequence of tasks, the vocabulary, and the transform shape, not the original
project's object graph.

How Fabian gets there: He separates source code from the information it
contains, then contrasts object-oriented adapters with data-oriented transforms.
Because the inputs and outputs are simpler and more regular, a transform can be
applied to any data that can be presented in the required shape.

Take home: Reuse the work shape: the sequence of transforms, schemas, and
simple functions over regular containers. Make inputs and outputs visible so a
caller can adapt its data without inheriting the original architecture.

## Main Lessons

- Reuse the sequence of data steps.
  A useful sequence such as "prepare rows, build groups, fill totals, write
  output" can be reused by another caller when each step has clear inputs and
  outputs.

- Small functions are easier to reuse when the input shape is simple.

  ```zig
  fn countInsideRange(values: []const f64, low: f64, high: f64) usize {
      var count: usize = 0;
      for (values) |value| {
          if (value >= low and value <= high) count += 1;
      }
      return count;
  }
  ```

  Notice that any caller with a numeric slice can use this rule.

- Put inputs and outputs in the function signature.

  ```zig
  fn writeDeltas(previous: []const f64, current: []const f64, out: []f64) void {
      for (previous, current, out) |before, now, *dst| {
          dst.* = now - before;
      }
  }
  ```

  The caller can see which values are read and which output buffer is written.

## Practical Example

Here is a pattern that treats reuse as copying a project-specific wrapper.

```zig
pub fn writeDailyReport(app: *App) !void {
    try app.loader.loadFiles();
    try app.report_builder.build(app.model, app.cache, app.writer);
}
```

Another tool can copy `writeDailyReport`, but then it inherits `App`, `loader`,
`model`, `cache`, and `writer`. The source file moved, but the useful knowledge
did not become easier to reuse.

A better approach preserves the data-changing sequence in a form another caller
can supply.

```zig
pub fn writeSummary(
    raw_rows: []const RawRow,
    storage: *SummaryStorage,
    writer: *Writer,
) !void {
    const rows = try prepareSummaryRows(raw_rows, storage.rows);
    const groups = try buildSummaryGroups(rows, storage.groups);
    const totals = fillSummaryTotals(rows, groups, storage.totals);
    try writer.writeTotals(totals);
}
```

The reusable part is the sequence: prepare rows, build groups, fill totals,
write totals. A batch job, a test, or an interactive tool can reuse that
sequence with different storage or a different writer.

The same rule applies inside small helpers. Here is a search helper tied to a
larger model object.

```zig
fn lowerBoundInModel(model: *const FullModel, needle: f64) usize {
    const values = model.values[0..model.len];
    var low: usize = 0;
    var high: usize = values.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (values[mid] < needle) low = mid + 1 else high = mid;
    }
    return low;
}
```

The compiler output below makes the model-object loads visible.

```asm
ldr     x9, [x0, #8]          ; load model.len from the model object
ldr     x8, [x0]              ; load model.values from the model object
ldr     d1, [x8, x10, lsl #3] ; load values[mid]
fcmp    d1, d0                ; compare values[mid] with the needle
```

A more reusable helper accepts the sorted values it needs.

```zig
fn lowerBound(values: []const f64, needle: f64) usize {
    var low: usize = 0;
    var high: usize = values.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (values[mid] < needle) low = mid + 1 else high = mid;
    }
    return low;
}
```

The generated output for the slice helper no longer loads a model wrapper.

```llvm
%7 = load double, ptr %6
%8 = fcmp olt double %7, %2
%.17 = select i1 %8, i64 %9, i64 %.068
```

The helper works on the slice it was given. It does not need the larger model
object.
