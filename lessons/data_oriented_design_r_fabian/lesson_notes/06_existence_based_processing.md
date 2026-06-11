# Existence-Based Processing

Sources:

- [Data-Oriented Design online book, "Don't use booleans"](https://www.dataorienteddesign.com/dodbook/node4.html#SECTION00450000000000000000) (printed-book p68).
- [Data-Oriented Design online book, "Don't use enums quite as much"](https://www.dataorienteddesign.com/dodbook/node4.html#SECTION00460000000000000000) (printed-book p73).
- [Data-Oriented Design online book, "Dynamic runtime polymorphism"](https://www.dataorienteddesign.com/dodbook/node4.html#SECTION00480000000000000000) (printed-book p76).
- [Data-Oriented Design online book, "Event handling"](https://www.dataorienteddesign.com/dodbook/node4.html#SECTION00490000000000000000) (printed-book p79).

Philosophy: Fabian treats a boolean field as wasted information. A row's
existence in a table already encodes one bit; storing `is_hurt` on every entity
and testing it every update is paying twice for the same fact. "An entity has an
implicit boolean hidden in the row existing in the table."

How Fabian gets there: He starts with health regeneration. The naive update
loads every entity, computes `isDead`, `isHurt`, and `regenCanStart`, and
usually does nothing, because regeneration is not the common case. Moving the
damage fields into a separate damage table means the update visits only damaged
entities; healing to full or dying removes the row. He then extends the idea:
any enum can be emulated with one table per enumerable value, where setting the
state is an insert or a migration between tables; moving rows between tables
also gives dynamic runtime polymorphism without a type field or virtual call;
and a subscription table turns event registration into an insert and
unsubscription into a delete.

Take home: Encode "is in this state" as membership in that state's table when
the state controls whether work runs. The hot loop then receives only rows it
will actually process, and entering or leaving the state is an insert, delete,
or migration done at a boundary, not a flag checked per row.

## Main Lessons

- A flag plus a check per row pays for the uncommon case on every row.

  ```zig
  const Channel = struct {
      level: f32,
      decaying: bool,
  };

  for (channels) |*channel| {
      if (channel.decaying) channel.level *= 0.95;
  }
  ```

  Most channels are steady. Every update still loads and tests every row.

- Membership in a table replaces the flag.

  ```zig
  // decaying_levels holds one row per channel currently decaying.
  for (decaying_levels.items) |*entry| {
      entry.level *= 0.95;
  }
  ```

  Being in `decaying_levels` is the boolean. Reaching the floor removes the
  row, which also ends the per-update cost.

- An enum that selects behavior can become one table per state.

  ```zig
  // Instead of: state: enum { queued, running, finished }
  try runQueued(queued_jobs, running_jobs);
  try advanceRunning(running_jobs, finished_jobs);
  ```

  Setting the state is a migration between tables. Each transform already
  knows the state of every row it sees, so the switch disappears from the
  per-row path.

- Changing which table a row lives in is runtime polymorphism.
  A vehicle that loses its wheels moves from the `driving` table to the
  `sliding` table. The sliding transform runs sliding rules. No type field is
  consulted per row, and the row can change behavior at runtime in a way a
  fixed class cannot.

- Registration is also existence.

  ```zig
  // Pressing the action key consults only the rows registered right now.
  for (action_handlers.items) |handler| {
      try fireAction(handler, state);
  }
  ```

  Subscribing is an insert; unsubscribing is a delete. Out-of-range doors are
  not asked about every key press because they have no row.

- Keep enums that do not steer per-row control flow.
  Fabian keeps enums for keybindings, colors, function results such as
  collision responses, and names for small finite sets. The table treatment is
  for enums that decide whether or which work runs. It also costs less when the
  state changes rarely; a state that flips every row every update would spend
  its savings on table churn.

## Practical Example

A mirror daemon keeps tens of thousands of package downloads in flight while
syncing a registry. Failed transfers retry with exponential backoff, and
completed transfers need their summary flushed to the index once. The weak
shape, which is how a first version of such a daemon usually looks, keeps both
questions as fields on every transfer and asks them every tick.

```zig
const Transfer = struct {
    bytes_done: u64,
    retry_at: u64, // 0 when not waiting to retry
    needs_flush: bool,
};

for (transfers) |*transfer| {
    if (transfer.retry_at != 0 and now >= transfer.retry_at) {
        transfer.retry_at = 0;
        try retry(transfer);
    }
    if (transfer.needs_flush) {
        try flushSummary(transfer);
        transfer.needs_flush = false;
    }
}
```

On a healthy mirror almost nothing is retrying and almost nothing is finishing
in any given tick, yet the loop loads every transfer and asks both questions
fifty times a second. The machine-level cost is the per-row flag load and
branch shown in the conditional-work lesson, where the local benchmark measured
the same contrast at `34.94x`. Worse, the tick cost grows with mirror size,
not with the amount of work due.

The first existence move stores the conditions as rows. A transfer that fails
inserts itself into a retry table; a transfer that completes inserts itself
into a flush table; the tick processes only rows that exist.

```zig
for (flush_ids.items) |id| {
    try flushSummary(&active[id]);
}
flush_ids.clearRetainingCapacity();
```

The flush list empties itself by being consumed: doing the work deletes the
work. Nothing resets a `needs_flush` flag, because the fact lived in the
table, not on the transfer.

The retry side has a second, sharper move in it. Even as a table, retries
would still need `now >= retry_at` per row. Fabian's regeneration example
points at the fix: attributes linked to time belong in a list sorted by the
time they should be acted upon. Keep the retry table sorted with the earliest
due retry at the end, and pop until the front of time is reached.

```zig
const RetryRow = struct {
    transfer_id: u32,
    retry_at: u64,
};

// retry_queue is kept sorted descending by retry_at, so the earliest
// due row sits at the end and pop() removes it without shifting.
while (retry_queue.getLastOrNull()) |row| {
    if (row.retry_at > now) break;
    _ = retry_queue.pop();
    try retry(&active[row.transfer_id]);
}
```

Count the comparisons. The flag version asks the time question once per
transfer per tick. The sorted queue asks it once per due retry, plus one final
comparison to stop. A tick where nothing is due costs one comparison no matter
whether the daemon tracks one hundred transfers or one million. The sort order
did the branching: data order replaced control flow, which is the existential
claim in its strongest form. This is not an exotic structure, either; it is
the same shape event loops use for timers, rediscovered from "don't ask
questions the table can answer."

The cost moved, it did not vanish: inserts, deletes, and migrations are now
real work at the state-change boundary, the sorted insert costs more than
setting a flag, and asking "what state is this row in?" from outside requires
checking tables. Fabian's claim is that those reads are rarely needed in a
transform-shaped program, because each transform already runs against the
table that defines the state.
