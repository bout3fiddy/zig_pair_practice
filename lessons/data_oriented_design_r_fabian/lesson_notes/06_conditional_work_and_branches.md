# Conditional Work And Branches

Sources:

- [Data-Oriented Design online book, "Existential Processing"](https://www.dataorienteddesign.com/dodbook/node4.html) (printed-book p57).
- [Data-Oriented Design online book, "Lazy evaluation"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00970000000000000000) (printed-book p153).
- [Data-Oriented Design online book, "Necessity"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00980000000000000000) (printed-book p154).
- [Data-Oriented Design online book, "Branch prediction"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001090000000000000000) (printed-book p172).

Philosophy: Fabian's optional-work lessons are about removing unnecessary
queries about whether data should be processed. Branches are not banned; the
target is unpredictable or data-dependent control flow that makes the machine do
work it later has to throw away.

How Fabian gets there: He starts with existential processing and to-do lists,
then revisits the same issue through dirty-bit lazy evaluation, unnecessary
object data loads, and branch prediction. The examples all ask whether a hot
loop should carry a flag check, dirty check, virtual dispatch, or optional data
for work it may not do.

Take home: Let existence in an active list, dirty list, or grouped table stand
for requested work when that removes many unpredictable checks. Recompute cheap
work when checking costs more, and batch similar cases so branches and dispatch
become predictable.

## Main Lessons

- A row in a list can mean "this work is active."

  ```zig
  for (active_tasks) |task| {
      try runTask(task, storage);
  }
  ```

  Being in `active_tasks` already means the work is enabled.

- Do not add checks that cost more than the work.
  If an update is cheap, doing it for every row may be faster and clearer than
  checking a dirty flag for every row.

  ```zig
  for (items, transforms) |item, *dst| {
      dst.* = rebuildCheapTransform(item);
  }
  ```

- For expensive refresh work, keep the dirty items as a list.

  ```zig
  for (dirty_items) |item_id| {
      try refreshCache(cache, item_id);
  }
  ```

  The list itself says what needs refresh.

- If a branch inside a repeated loop is unpredictable, group the data before
  the repeated work when the setup cost is worth it.

  ```zig
  const split = partitionRows(rows, scratch);
  try processNormalRows(split.normal);
  try processReviewRows(split.review);
  ```

  The review decision is made before the repeated loop.

- Do not give a repeated step fields for features it will not read.

  ```zig
  const ScoreItem = struct {
      amount: f64,
      rate: f64,
  };

  fn sumScores(items: []const ScoreItem) f64 {
      var total: f64 = 0;
      for (items) |item| total += item.amount * item.rate;
      return total;
  }
  ```

## Practical Example

A monitoring pipeline receives many readings. Some readings need manual review,
and a smaller set needs an expensive preview refresh. The weak shape keeps both
questions on every row in the repeated path.

```zig
const RuntimeReading = struct {
    value: i32,
    needs_review: bool,
    preview_dirty: bool,
    report_name: []const u8,
    preview_path: []const u8,
};

for (readings) |reading| {
    if (reading.needs_review) review_total += reading.value;
    if (reading.preview_dirty) try refreshPreview(reading, storage);
}
```

The compiler output below is generated machine code for the selected-value sum.
It makes the per-row flag load and branch visible.

```asm
ldrb    w10, [x8], #1  ; load one runtime flag
cbz     w10, LBB22_5   ; branch when the flag is zero
ldr     w10, [x11]     ; load value only for selected rows
add     w0, w10, w0    ; add selected value
```

Every row carries the question into the loop. Reporting fields also travel
through a step that only needs numeric review values and preview work ids.

A better shape forms the conditional work as data.

```zig
const WorkPlan = struct {
    review_values: []const i32,
    dirty_preview_ids: []const u32,
    report_rows: []const ReportRow,
};

review_total += sumValues(plan.review_values);
for (plan.dirty_preview_ids) |reading_id| {
    try refreshPreview(reading_id, preview_storage);
}
```

The generated output for the grouped values is a straight sum loop.

```asm
ldp     q4, q5, [x8, #-32]  ; load grouped values with no flag load
ldp     q6, q7, [x8], #64   ; load more grouped values and advance
add.4s  v0, v4, v0          ; add four i32 lanes
add.4s  v1, v5, v1          ; add four more i32 lanes
```

The report data is still kept, but it belongs to the reporting step.

```zig
const ReportRow = struct {
    reading_id: u32,
    report_name: []const u8,
    preview_path: []const u8,
};
```

Cheap work can still stay as a direct pass when checking would cost more than
the update.

```zig
for (readings, transforms) |reading, *dst| {
    dst.* = rebuildCheapTransform(reading);
}
```

A benchmark for requested-task lists showed processing only requested rows was
`4.20x` faster elapsed time than scanning all rows with flags. A benchmark for
pre-grouped values showed summing them was `34.94x` faster than branching on
every flag, with the same checksum. The grouped-values benchmark excluded
grouping setup; a rebuild-each-time measurement was `1.61x` faster on the same
local workload.
