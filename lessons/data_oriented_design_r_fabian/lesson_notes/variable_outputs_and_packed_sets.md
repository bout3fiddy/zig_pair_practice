# Variable Outputs And Packed Sets

Sources:

- [Data-Oriented Design online book, "Types of processing"](https://www.dataorienteddesign.com/dodbook/node4.html#SECTION00440000000000000000) (printed-book p66).
- [Data-Oriented Design online book, "Varying length sets"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00990000000000000000) (printed-book p155).

Philosophy: Fabian classifies transforms by output cardinality before choosing
storage. A mutation, filter, emission, and generator are different shapes of
work because they produce one output, zero-or-one output, many outputs, or no
input at all.

How Fabian gets there: He defines those transform types, then returns to the
problem in varying-length sets. Fixed buffers fit many stream-processing cases,
but filters and emissions need staging: per-worker output vectors, counts,
offsets, concatenation, or prefix sums.

Take home: Match output storage to output cardinality. Use direct slots for
one-to-one transforms, compacted output plus counts or offsets for filters, and
packed rows with start/count metadata for many-output groups.

## Main Lessons

- A one-to-one transform writes one output slot for each input row.

  ```zig
  for (items, out_items) |item, *out| {
      out.* = prepareItem(item);
  }
  ```

  The input and output slices have the same length.

- A filter writes zero or one output row for each input row.

  ```zig
  var written: usize = 0;
  for (rows) |row| {
      if (!row.keep) continue;
      out[written] = .{ .row_index = row.index };
      written += 1;
  }
  return out[0..written];
  ```

  The output can be shorter than the input.

- An expansion can write many output rows for one input row.

  ```zig
  for (orders) |order| {
      for (order.lines) |line| {
          out[written] = makeLineItem(order, line);
          written += 1;
      }
  }
  return out[0..written];
  ```

  The output can grow faster than the input.

- Store variable-size groups in one big list.
  Each row stores where its group starts and how many items belong to it.

  ```zig
  const GroupRef = struct {
      item_start: u32,
      item_count: u16,
  };

  fn groupItems(ref: GroupRef, items: []const LineItem) []const LineItem {
      return items[ref.item_start .. ref.item_start + ref.item_count];
  }
  ```

  `GroupRef` keeps the range with the row that uses it.

- A prefix sum turns counts into starting positions.

  ```zig
  starts[0] = 0;
  for (counts[0 .. counts.len - 1], 1..) |count, i| {
      starts[i] = starts[i - 1] + count;
  }
  ```

  Counts become positions that later queries can read directly.

## Practical Example

A route importer reads one source row per planned trip. Cancelled trips produce
no runtime route, normal trips produce one summary, and multi-stop trips append
several stop rows. The weak shape still treats the importer as if every trip
produces exactly one output row.

```zig
for (trips, out_routes) |trip, *dst| {
    dst.* = buildRoute(trip);
}
```

That shape only works when each `trip` really produces exactly one route row.
It is the wrong storage shape when a trip can be rejected or can append several
stop rows.

For variable-size groups, another weak shape is recomputing the start offset
from counts every time a group is read.

```zig
var start: u32 = 0;
for (counts[0..i]) |count| {
    start += count;
}
return line_items[start..][0..counts[i]];
```

The compiler output below is generated machine code. It makes the repeated
count-summing work visible.

```asm
ldp     q4, q5, [x8, #-32]  ; load counts for this query
ldp     q6, q7, [x8], #64   ; load more counts and advance
add.4s  v0, v4, v0          ; add counts into a running sum
add.4s  v1, v5, v1          ; keep summing counts for this query
```

A better approach stores ranges after the output count is known.

```zig
const GroupRef = struct {
    start: u32,
    count: u32,
};

const ref = trip_stop_ranges[i];
return stop_rows[ref.start..][0..ref.count];
```

When the input supplies only counts, build `starts` once.

```zig
prefixStarts(counts, starts);
const start = starts[i];
return stop_rows[start..][0..counts[i]];
```

The first version re-adds counts for every query. The better version does the
setup pass once, then each query reads one saved start position.

```llvm
%6 = load i32, ptr %lsr.iv
store i32 %7, ptr %lsr.iv19
```

A benchmark for prepared starts showed querying them was `1970.82x` faster than
re-summing counts for every query, with the same checksum. The output count
changed the storage problem.
