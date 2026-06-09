# Reducing Memory Dependency

Source: [Data-Oriented Design online book, "Reducing memory dependency"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001020000000000000000) (printed-book p164).

Philosophy: Fabian's memory-dependency lesson is that repeated work stalls when
each memory read must finish before the program knows the next address to read.
The bad case is not "the compiler knows where the next read is"; it is "the next
address is stored inside the object we are still waiting to load".

How Fabian gets there: He points at linked lists, tree-shaped maps or sets, and
systems that connect objects through many pointers. The lesson is not that every
lookup is bad; it is that a long chain of "load this object before you can find
the next object" gives the machine little room to get ahead.

Take home: Reduce dependent hops in repeated work. Prefer contiguous storage,
wide nodes, direct indexes, or saved positions when the program needs to visit
many related values.

## Main Lessons

- Avoid "go here, then go there, then go somewhere else" in loops that run many
  times.
  A pointer chain makes the CPU wait for one memory load before it knows the
  address of the next load.

  ```zig
  const value = rows[index].score;
  ```

  Notice that the code uses one array and one index. It does not follow a
  pointer to another object before finding `score`.

- Save positions into arrays when you can.
  Then the repeated loop can jump straight to the result it needs.

  ```zig
  const result_index = plan.result_indices[i];
  sum += results[result_index].score;
  ```

  Notice that `result_indices` stores the result position. The next line uses
  that position to read `results` directly.


- If a loop reads the same field from many rows, consider storing that field
  together.
  This can be easier for the CPU than reading full rows with many unused fields.

  ```zig
  var total: f64 = 0;
  for (scores) |score| {
      // The loop walks one plain score list.
      total += score;
  }
  ```

  Notice that the loop reads the score list directly. A struct with only
  `values: []const f64` would add a name, but it would not keep any related
  fields together. Use a wrapper only when there is more context that must
  travel with the values, such as indexes or matching keys.

## Practical Example

Here is a pattern where the current row stores the address of the next row.

```zig
const ScoreNode = struct {
    score: f64,
    next: ?*const ScoreNode,
};

var node = first;
while (node) |current| {
    sum += current.score;
    node = current.next;
}
```

The compiler output below is generated machine code. It makes the dependency
visible.

```asm
ldr     d1, [x0]      ; load current.score
fadd    d0, d0, d1    ; add the score
ldr     x0, [x0, #8]  ; load current.next
cbnz    x0, LBB11_2   ; repeat only after next is known
```

The loop cannot know the next address until it has loaded the current node. If
the nodes are scattered in memory, that gives the machine little room to get
ahead.

A better approach stores the values in a list when the job is to visit all of
them.

```zig
for (scores) |score| {
    sum += score;
}
```

The generated stream version reuses a shared sum loop that walks adjacent `f64`
values.

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent scores
ldp     q5, q6, [x9], #64   ; load four more and advance
fadd    d0, d0, d1          ; add loaded score lanes
fadd    d0, d0, d3
```

The list loop still reads memory, but the next address is the next slot in the
array. It does not wait for each loaded row to reveal a `next` pointer.

An index still has one dependent load: load the saved position, then read the
target row. The larger dependency problem is a longer pointer chain in which
each loaded object reveals the next object to load.
