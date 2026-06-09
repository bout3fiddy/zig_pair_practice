# Data Shape, Tables, And Cache Lines

Sources:

- [Data-Oriented Design online book, "Data is not the problem domain"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00220000000000000000) (printed-book p6).
- [Data-Oriented Design online book, "Tables"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00940000000000000000) (printed-book p146).
- [Data-Oriented Design online book, "Cache line utilisation"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001060000000000000000) (printed-book p168).

Philosophy: Fabian starts from the claim that data has no inherent meaning.
The problem domain, class name, or nearby fields should not dictate the shape
of hot runtime data. Rows, columns, grids, and cache-line neighbors are choices
made for computation.

How Fabian gets there: He starts with game-world data hidden in objects when a
grid or simpler count would have made the real shape visible. He then moves to
tables, hot/cold separation, and cache lines to show that the useful layout
depends on which values a transform reads, writes, or asks about together.

Take home: First name the repeated work and the values it actually touches.
Then choose the grid, table, row, column, or nearby cache-line fields that serve
that work, instead of carrying the domain object into the loop.

## Main Lessons

- Do not pass a large domain object into a calculation if the calculation only
  reads a few values.

  ```zig
  const RunInput = struct {
      threshold: f64,
      records: []const PreparedRecord,
      config: RunConfig,
  };

  fn buildRunInput(request: RequestInput, config: RunConfig) RunInput {
      return .{
          .threshold = request.threshold,
          .records = request.prepared_records,
          .config = config,
      };
  }
  ```

  `buildRunInput` is the handoff. It reads the larger request, then returns only
  the values the repeated calculation will read.

- A list is often the clearest shape for repeated work.

  ```zig
  for (records) |record| {
      total += record.score;
  }
  ```

  The loop says the real work directly: visit each prepared record and read the
  score.

- Split fields only when that helps the loop.
  If one loop reads only `amount`, keeping amounts together can help. If another
  loop always reads `amount` and `weight` together, keeping those two values
  aligned as one table matters.

  ```zig
  const ItemTable = struct {
      amounts: []const f64,
      weights: []const f64,
  };

  fn sumAmounts(table: ItemTable) f64 {
      var total: f64 = 0;
      for (table.amounts) |amount| total += amount;
      return total;
  }

  fn sumWeighted(table: ItemTable) f64 {
      var total: f64 = 0;
      for (table.amounts, table.weights) |amount, weight| {
          total += amount * weight;
      }
      return total;
  }
  ```

  `ItemTable` keeps aligned columns together while still allowing a loop to read
  only one column.

- Cache lines make nearby bytes matter, but only when the hot path reads those
  bytes.

  ```zig
  const GroupRef = struct {
      start: u32,
      count: u16,
  };

  fn sideItems(ref: GroupRef, items: []const ItemRef) []const ItemRef {
      return items[ref.start .. ref.start + ref.count];
  }
  ```

  `sideItems` reads `start` and `count` together to answer one question: where
  are this group's side items?

- Do not fill nearby bytes with unrelated data.
  Debug text belongs somewhere else if the repeated loop never asks for it.

  ```zig
  fn describeGroup(
      group_index: usize,
      group_source_names: []const []const u8,
  ) []const u8 {
      return group_source_names[group_index];
  }
  ```

  Reporting data remains available without putting source names in the repeated
  item path.

## Practical Example

Here is a pattern from a renderer that walks prepared groups. Each group always
has main items, and some groups also have side items. The group row is already
loaded, but the side-item count still lives in a separate table keyed by
`group.id`.

```zig
const GroupShell = struct {
    id: u32,
    item_start: u32,
    item_count: u16,
};

for (groups) |group| {
    appendItems(items[group.item_start..][0..group.item_count], out);

    const side_count = side_counts[group.id];
    if (side_count != 0) {
        appendSideItems(group.id, side_count, side_items, out);
    }
}
```

That shape looks tidy in a source-data table, but the repeated loop pays for
another lookup just to answer a question it asks for every group.

The compiler output below is generated machine code. It makes the extra lookup
visible.

```asm
ldr     w11, [x10], #12          ; load group.id, then advance to next group row
ldrh    w11, [x1, x11, lsl #1]   ; load side_counts[group.id]
cmp     w11, #0                  ; ask whether side items exist
cinc    x8, x8, ne               ; count this group when side_count is nonzero
```

The row has already arrived, but the hot path still uses `group.id` to read the
side-count table.

A better runtime row carries the side range beside the main range because this
loop asks for both.

```zig
const GroupWork = struct {
    item_start: u32,
    item_count: u16,
    side_count: u16,
    side_start: u32,
};

for (groups) |group| {
    appendItems(items[group.item_start..][0..group.item_count], out);

    if (group.side_count != 0) {
        appendSideItems(
            side_items[group.side_start..][0..group.side_count],
            out,
        );
    }
}
```

The generated output for the prepared row reads the side count from the group
row stride.

```asm
ldrh    w11, [x9], #12  ; load group.side_count, then advance to next group row
cmp     w11, #0         ; ask whether side items exist
cinc    x8, x8, ne      ; count this group when side_count is nonzero
```

The better row is not a bigger domain object. It is a runtime row built around
one repeated question: where are this group's main items, and does it also have
side items? Fabian's cache-line measurement showed the same kind of effect: on
his i5-4430, a simple map check took `11.31ms`, a cached presence check took
`3.71ms`, and a fully cached query took `0.30ms`.
