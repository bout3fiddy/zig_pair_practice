# Debugging And Testing Transforms

Sources:

- [Data-Oriented Design online book, "Cosmic hierarchies"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001110000000000000000) (printed-book p180).
- [Data-Oriented Design online book, "Debugging"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001120000000000000000) (printed-book p180).
- [Data-Oriented Design online book, "Unit testing"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001150000000000000000) (printed-book p187).
- [Data-Oriented Design online book, "Refactoring"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001160000000000000000) (printed-book p188).

Philosophy: Fabian claims the data-oriented shape is easier to keep correct,
not only faster. A program made of stateful tables and stateless transforms
gives bugs fewer places to hide: existence in a table implies processability,
inputs stay inspectable, and a transform can be tested with nothing but an
input table, an output table, and a comparison.

How Fabian gets there: He names the prime causes of bugs as unexpected side
effects and missed corner cases, then attacks the carriers. Lifetimes: null
dereferences come from one object owning another's lifetime; when existence is
a row, deleting an entity means deleting its rows, and there is no half-dead
pointer to trip over. Pointers: a nullable pointer smuggles in a boolean,
which is the same information-duplication problem as the boolean lesson.
Bad state: reassigning a variable destroys history, so single-assignment
transforms that keep their inputs around let you replay how a state was
reached; an idempotent transform produces the same output every run. Cosmic
hierarchies: forcing every table to hang off one universal EntityID recreates
the cosmic base class in data.

Take home: Keep transforms one-way: read from one table, write another, avoid
overwriting the evidence. Prefer indexes into live tables over nullable
pointers. Test each transform with a literal input table and expected output
table. Treat refactoring as reordering transforms rather than reshaping data.

## Main Lessons

- A nullable pointer carries a hidden boolean; a row does not.

  ```zig
  // Weak: every reader must remember the null question.
  current_target: ?*Enemy,

  // Better: a row in the targeting table is the "has target" fact,
  // and it cannot outlive the enemy row it indexes.
  const TargetRow = struct { hunter_id: u32, enemy_index: u32 };
  ```

  Deleting an enemy means removing its rows from the tables it belongs to.
  That is a findable bookkeeping bug, not a crash three frames later.

- Reassignment destroys the history a debugger needs.

  ```zig
  // Weak: by the return, nobody knows which rule failed.
  var valid = true;
  if (ducks > 10) valid = false;
  valid = (ducks & 1) == 0; // also silently overwrites the first rule
  if (ducks < 0) valid = false;
  return valid;
  ```

  ```zig
  // Better: one assignment per fact; each can be read, asserted, and
  // breakpointed.
  const not_too_many = ducks <= 10;
  const is_even = (ducks & 1) == 0;
  const not_negative = ducks >= 0;
  return not_too_many and is_even and not_negative;
  ```

  The weak version also contains a real bug the shape invited: the second rule
  overwrites the first instead of combining with it.

- Keep inputs around; one-way transforms make reruns cheap.

  ```zig
  fillSettlements(trades, rates, settlements);
  std.debug.assert(settlementsBalance(settlements));
  ```

  When the assert fires, `trades` and `rates` still hold the exact input. The
  transform can be rerun under a debugger with no state reconstruction,
  because running it twice writes the same `settlements`.

- A transform test is a table in, a table out, and a comparison.

  ```zig
  test "late fees apply only past the grace period" {
      const invoices = [_]Invoice{
          .{ .days_overdue = 0, .amount = 100 },
          .{ .days_overdue = 31, .amount = 100 },
      };
      var fees: [2]f64 = undefined;
      fillLateFees(&invoices, &fees);
      try std.testing.expectEqualSlices(f64, &.{ 0.0, 1.5 }, &fees);
  }
  ```

  No fixture object, no setup graph. The test data is also documentation of
  the transform's contract, and the same tables guard later refactors.

- Do not let one EntityID become cosmic.
  Normalised data produces several entity kinds: a mesh id, a room id, a door
  id. Piling them into one universal id works but is not a necessary step, and
  it quietly rebuilds the base-class-of-everything. Let tables relate where
  the domain relates them.

- Refactoring becomes reordering.
  When behavior lives in transforms over normalised tables, most refactors
  swap transform order or split a transform, not reshape data. When a schema
  must change, a written once, used many times migration function is the
  data-formation lesson applied to your own program.

## Practical Example

A billing pipeline intermittently produces a wrong statement total, noticed
days later. In the object shape, the evidence is gone.

```zig
pub fn process(account: *Account) !void {
    account.applyPayments(); // mutates balances in place
    account.applyLateFees(); // reads and overwrites the same fields
    account.total = account.computeTotal();
}
```

Each step overwrites what the previous step read. Reproducing the bug requires
rebuilding an account in the exact pre-bug state, which is the state nobody
recorded.

The transform shape leaves an audit trail by construction.

```zig
pub fn process(storage: *BillingStorage) !void {
    fillPaidBalances(storage.opening, storage.payments, storage.paid);
    fillFeeAdjusted(storage.paid, storage.fee_rules, storage.adjusted);
    fillStatementTotals(storage.adjusted, storage.totals);
}
```

When a total looks wrong, every intermediate table still exists: `opening`,
`payments`, `paid`, `adjusted`. The broken step is found by checking which
boundary the bad number first appears at, and each `fill` function reruns
idempotently on the same inputs. Each step also has the table-in, table-out
shape that the unit test above needs, so the corner case that caused the bug
becomes one more row in a test table — which is this workspace's regression
rule stated in Fabian's terms.
