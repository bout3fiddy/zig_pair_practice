# Lookup And Indexes

Sources:

- [Data-Oriented Design online book, "Indexes"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00710000000000000000) (printed-book p113).
- [Data-Oriented Design online book, "Data-oriented Lookup"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00720000000000000000) (printed-book p115).
- [Data-Oriented Design online book, "Finding random is a hash/tree issue"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00740000000000000000) (printed-book p121).

Philosophy: Fabian's lookup lesson starts by separating search criteria from
the data dependencies of those criteria. The search loop should not drag the
whole object or payload through memory just to answer a small question.

How Fabian gets there: He uses database indexes as the model for queries that
can learn from repeated use, then uses animation-key lookup to show the local
layout decision: compare against key times first, and fetch the full key only
after the match is known.

Take home: Search the smallest key stream that can answer the question. Fetch
the payload after the result is known, and keep indexes or saved positions when
the same query repeats.

## Main Lessons

- Search only the key values needed for the lookup.
  If the search is by time, search the time array before reading the larger
  payload row.

  ```zig
  const KeyTable = struct {
      times: []const f64,
      payloads: []const KeyPayload,
  };

  fn findPayload(table: KeyTable, t: f64) KeyPayload {
      const index = lowerBound(table.times, t);
      return table.payloads[index];
  }
  ```

  Notice that `lowerBound` reads only `times`. The payload is read once, after
  the index is known.

- An index is a remembered position.
  Build it when the same lookup happens often enough to justify the setup.

  ```zig
  for (row.result_indices) |result_index| {
      sum += results[result_index].score;
  }
  ```

  Notice that `result_index` is only a position. The real value still lives in
  `results`.

- Keep related lookup arrays together.
  If `times[i]` selects `payloads[i]`, those slices belong to the same table
  shape. Do not let callers mix keys from one table with payloads from another.

## Practical Example

This is Fabian's animation-sampling case, and it appears anywhere time-stamped
rows are queried: keyframe tracks, sensor logs, market ticks. The sampler runs
once per bone per frame, so its shape matters more than its code size. Here is
the pattern that searches full payload rows even though the search key is only
`payload.time`.

```zig
for (table.payloads) |payload| {
    if (payload.time >= t) return payload;
}
```

The compiler output below is generated machine code. It makes the full-row
stride and time-field comparison from the code above visible.

```asm
ldur    d0, [x8, #-16]  ; load the time field from a 32-byte payload row
fcmp    d0, d1          ; compare payload.time with the search key
b.ge    LBB14_5         ; branch when this payload row matches
add     x8, x8, #32     ; move to the next full payload row
```

This search walks payload rows while it is only trying to answer "which time?"

A better approach searches the key array first, then fetches one payload.

```zig
const index = lowerBound(table.times, t);
return table.payloads[index];
```

The generated output for the key search is narrower.

```llvm
%7 = load double, ptr %6
%8 = fcmp olt double %7, %2
%.17 = select i1 %8, i64 %9, i64 %.068
```

The search loop loads keys. It does not load payload rows while comparing.

If the same result lookup is repeated inside many rows, save the result
positions during preparation.

```zig
for (row.result_keys) |result_key| {
    const result_index = findResultIndex(results, result_key);
    sum += results[result_index].score;
}
```

The compiler output below shows the repeated search and comparison.

```asm
ldr     d1, [x1, x9, lsl #3]   ; load requested key
ldr     d2, [x2, x11, lsl #3]  ; load candidate result key
fcmp    d2, d1                 ; compare candidate with requested value
b.eq    LBB10_7                ; branch when the search finds a match
```

A prepared index stores the result positions once.

```zig
for (row.result_indices) |result_index| {
    sum += results[result_index].score;
}
```

The generated output then uses the saved position.

```asm
ldr     w11, [x1, x9, lsl #2]  ; load a saved u32 result index
ldr     d1, [x2, w11, uxtw #3] ; load the f64 score at results[result_index]
fadd    d0, d0, d1             ; add the score into the total
```

A benchmark for prepared indexes showed they were `1113.01x` faster than linear
search, with the same checksum. The lookup shape still matters after that:
saved indexes remove repeated search work, while key arrays keep the search
itself narrow.

When a lookup is by an arbitrary key instead of a position, Fabian's
"finding random" rule applies: pick the structure from the modification
pattern. Trees (especially wide, cache-line-friendly B-tree nodes) suit data
that stays mostly static between batched updates; hash tables win when many
modifications are interspersed with lookups; a perfect or precomputed hash wins
when the data is constant. A hash bucket sized to one cache line makes the
extra slot probes free, because those bytes arrive with the first load anyway.
