# Optimisation, Feedback, And Strategy

Sources:

- [Data-Oriented Design online book, "When should we optimise?"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00910000000000000000) (printed-book p137).
- [Data-Oriented Design online book, "Feedback"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00920000000000000000) (printed-book p138).
- [Data-Oriented Design online book, "A strategy"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00930000000000000000) (printed-book p142).

Philosophy: Fabian treats optimisation as a feedback loop, not a hunch. An
optimisation is premature when there is no data showing the problem or no way to
judge whether the change helped.

How Fabian gets there: He starts from production limits such as frame time,
memory, load time, and battery usage, then argues for complete and immediate
feedback. His strategy is to define the problem objectively, measure it
reproducibly, analyse the measurements, implement an experiment, confirm the
result, and keep the report.

Take home: Do not start with the fix. Name the measured problem, keep a
repeatable baseline, predict the effect before implementing, test the change in
isolation when possible, and write down what happened.

## Main Lessons

- Measure the boundary you want to improve.
  If score filling is the concern, time score filling instead of the whole
  program.

  ```zig
  const start = timer.read();
  try fillScores(plan, storage);
  const elapsed_ns = timer.read() - start;
  ```

  Notice that the timer wraps the phase being judged.

- Record workload and correctness with the timing.
  A time without item count, iteration count, or checksum cannot explain much.

  ```zig
  bench fill_scores items=131072 iterations=300 elapsed_ns=26615500 checksum=127247609.700
  ```

  Notice that the number now says what ran and whether the result matched the
  expected output.

- Keep the old result next to the new result.
  Without the baseline, the new number has no comparison.

- Change one thing at a time.
  If the data layout, loop body, allocator, and benchmark size all change at
  once, the result cannot say which change helped.

## Practical Example

Here is a misleading optimization note.

```text
The selected-row branch was slow.
Grouping was 34.84x faster, so replace the branchy scan.
```

The number sounds decisive, but it hides the boundary. It compared a raw scan
against an already-grouped list. That may be the right comparison if the grouped
list is reused many times. It is not enough evidence for rebuilding the grouped
list every call.

A stronger note separates the claims.

```text
question
  Should selected values be grouped before the repeated sum?

workload
  raw_rows=262144 selected_rows=131072 iterations=1000 seed=fixed

baseline
  sum_selected_branchy elapsed_ns=145675625 ns_per_item=0.556 checksum=8387918000

prepared-only result
  sum_grouped_values elapsed_ns=4181417 ns_per_selected_item=0.032 checksum=8387918000
  grouped_values_vs_branchy=34.84x

full rebuild-each-time result
  group_then_sum_values elapsed_ns=90679875 ns_per_raw_item=0.346 checksum=8387918000
  group_then_sum_vs_branchy=1.61x

decision
  Grouping is promising when the selected list is reused.
  If grouping changes every call, measure the caller that builds it.
```

Now the result can be checked. The note names the problem, the workload, the
baseline, the prepared-only result, the full rebuild result, and the matching
checksum. Compiler output becomes useful after this point, when there is a
measured question to ask of the generated code.
