# Sorting And Best-Value Sets

Sources:

- [Data-Oriented Design online book, "Finding lowest or highest is a sorting problem"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00730000000000000000) (printed-book p120).
- [Data-Oriented Design online book, "Do you need to?"](https://www.dataorienteddesign.com/dodbook/node8.html#SECTION00810000000000000000) (printed-book p125).
- [Data-Oriented Design online book, "Maintain by insertion sort or parallel merge sort"](https://www.dataorienteddesign.com/dodbook/node8.html#SECTION00820000000000000000) (printed-book p128).
- [Data-Oriented Design online book, "Sorting for your platform"](https://www.dataorienteddesign.com/dodbook/node8.html#SECTION00830000000000000000) (printed-book p128).

Philosophy: Fabian's first sorting question is whether you need to sort at
all. Sorting is memory-intensive work, and much of it is done to answer
questions that a cheaper structure answers directly: a partition, a partial
sort, a maintained best-N subset, or no order at all.

How Fabian gets there: He starts from render queues, where opaque and
alpha-blended calls do not need sorting against each other, so a bucket split
saves work before any sort runs. He covers partial answers: `nth_element` and
`partial_sort` when only the first n items matter, unstable algorithms when
ties can land in any order, and an `unstable_remove` that swaps the last
element in rather than shuffling everything down. For repeated nearest-N
queries, he promotes the query to a maintained sorted subset updated on
insert and delete. Finally, algorithm choice is data plus platform: counting
and radix sorts beat comparison sorts for discrete keys, insertion sort
maintains an almost-sorted list cheaply, and merge sort has parallel-friendly
variants.

Take home: Before sorting, name the question the order answers. Split into
buckets when groups do not compare across each other, keep a small maintained
best-set when the same extreme is queried repeatedly, use partial or unstable
algorithms when full stable order is not part of the contract, and pick
counting or radix sorts when keys are small integers.

## Main Lessons

- Partition first when groups never compare across each other.

  ```zig
  // Urgent tickets are handled before normal ones; order across the
  // boundary never matters.
  const urgent_count = partitionUrgent(tickets);
  sortByAge(tickets[0..urgent_count]);
  sortByAge(tickets[urgent_count..]);
  ```

  Two small sorts replace one big sort with a compound comparator, and each
  part can be profiled on its own.

- Removal does not need to preserve order unless the contract says so.

  ```zig
  fn unstableRemove(items: []Job, index: usize, len: *usize) void {
      len.* -= 1;
      items[index] = items[len.*];
  }
  ```

  Swap the last element in and shrink. `std.ArrayList.swapRemove` is this
  exact tool. Ordered remove shuffles every later element down to preserve an
  order nobody may be reading.

- A repeated min/max query is a maintained subset, not a search.

  ```zig
  // best_offers holds the three lowest prices, kept sorted.
  fn addOffer(best_offers: *BoundedArray(Offer, 3), offer: Offer) void {
      if (best_offers.len < 3) {
          insertSorted(best_offers, offer);
      } else if (offer.price < best_offers.get(2).price) {
          _ = best_offers.pop();
          insertSorted(best_offers, offer);
      }
  }
  ```

  Each insert does constant work. The query reads element zero. Keeping a few
  more than needed makes deletions rarely force a full rescan.

- Discrete keys deserve counting or radix sorts.

  ```zig
  // Sort draw calls by one of 64 material ids: count, prefix, scatter.
  for (calls) |call| counts[call.material] += 1;
  prefixStarts(&counts, &starts);
  for (calls) |call| {
      sorted[starts[call.material]] = call;
      starts[call.material] += 1;
  }
  ```

  Two passes and no comparisons. The prefix-starts step is the same setup
  pass as the variable-outputs lesson.

- An almost-sorted list wants insertion-style maintenance.
  When one row's key changes per update, re-inserting that row costs less than
  re-sorting the list. Save the full sort for bulk changes, and prefer
  parallel-friendly merge variants when a full sort of a large set is truly
  required.

## Practical Example

A telemetry dashboard shows the five slowest endpoints, refreshed every
second. The weak shape re-sorts everything per refresh.

```zig
fn slowestFive(samples: []Sample, out: *[5]Sample) void {
    std.mem.sort(Sample, samples, {}, byLatencyDesc);
    @memcpy(out, samples[0..5]);
}
```

Sorting a hundred thousand samples produces a hundred thousand ordered rows so
the dashboard can read five. The full order is thrown away every second.

The first improvement asks only for the answer: a selection that places the
five largest in front without ordering the rest, which is `nth_element`
thinking. The maintained shape goes further because the query repeats:

```zig
const SlowestBoard = struct {
    rows: [6]Sample, // one spare beyond the displayed five
    len: usize,

    fn add(board: *SlowestBoard, sample: Sample) void {
        if (board.len == board.rows.len and
            sample.latency_ns <= board.rows[board.len - 1].latency_ns)
        {
            return; // common case: not slow enough to place
        }
        insertByLatency(board, sample);
    }
};
```

Each incoming sample does one comparison in the common case. The refresh reads
`board.rows[0..5]` with no sorting at all. The sort did not get faster; it got
deleted, which is Fabian's point about knowing why the order was wanted.

Verify the contract before celebrating: the maintained board must agree with
the full sort on the same input. A `zig test` that feeds both paths the same
samples and compares the five results is the correctness gate for this lesson.
