# False Sharing

Source: [Data-Oriented Design online book, "False sharing"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001070000000000000000) (printed-book p169).

Philosophy: Fabian describes false sharing as a cache problem in threaded code:
workers can write different values and still interfere when those values share
one cache line.

How Fabian gets there: He contrasts shared per-thread sum slots with local
accumulators, then stresses that a trivial reproduction only showed the issue
with optimisations off. That warning is part of the lesson: hardware folklore
still needs measurement.

Take home: Let each worker write locally during the main loop, and combine
results after the local work is finished. Check that suspected false sharing is
real in the optimized build you care about.

## Main Lessons

- Give each worker its own scratch area.
  Workers should not fight over the same output memory while they are doing
  their main work.

  ```zig
  const worker_output = worker_outputs[worker_id];
  try fillWorkerResults(range, worker_output);
  ```

  Notice that the worker receives the output area it is allowed to write. The
  main work writes there, not into another worker's output. Later code can read
  `worker_output` after this worker has finished filling it.


- Add into a local variable first.
  Write the worker's final answer once, after the loop is done.

  ```zig
  var local_sum: f64 = 0;
  for (range) |i| local_sum += values[i];
  partial_sums[worker_id] = local_sum;
  ```

  Notice that the loop updates `local_sum`, which only one worker can see.
  Shared memory is written once at the end.

- Do not guess that false sharing is the problem.
  First compare one worker, two workers, four workers, and so on.

## Practical Example

Here is a pattern from a tiled worker loop. The worker wants a final sum, but a
shared progress slot is updated on every item so another system can inspect
partial progress.

```zig
for (range) |i| {
    partial_sums[worker_id] += values[i];
}
```

The compiler output below is generated machine code. It makes the repeated
shared-slot store from the code above visible.

```asm
ldr     d1, [x9], #8  ; load one input value
fadd    d0, d0, d1    ; update the running sum
str     d0, [x1]      ; write partial sum storage every item
b.lo    LBB21_2       ; repeat the load/add/store loop
```

This shows that the repeated loop stores to result memory on every item. In a
multi-worker run, adjacent `partial_sums` slots can sit in the same cache line,
so workers can interfere even though each worker writes a different slot.

A better approach accumulates locally and writes once.

```zig
var local_sum: f64 = 0;
for (range) |i| local_sum += values[i];
partial_sums[worker_id] = local_sum;
```

The first version writes to shared result storage on every item. The better
version accumulates in a local variable and writes the worker result once.

The generated output for the better approach is easier to read.

```asm
ldp     q1, q2, [x10, #-32]  ; load two vector registers of input values
fadd    d0, d0, d1           ; add one loaded f64 lane into local accumulator d0
fadd    d0, d0, d2           ; add another loaded f64 lane into local accumulator d0
```

The repeated loop loads values and accumulates in register `d0`. There is no
store to shared result memory inside the loop body. The progress system can
read the final worker result after the local loop has finished, or it can use a
separate lower-frequency reporting path.

A benchmark for local accumulation showed it was `4.62x` faster than
forcing a shared slot write on every item, with the same checksum. This is a
single-threaded microbenchmark, so it proves the cost of repeated stores, not
the full multi-worker false-sharing cost.
