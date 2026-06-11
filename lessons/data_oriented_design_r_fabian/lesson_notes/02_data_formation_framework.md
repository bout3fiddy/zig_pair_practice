# Data Formation And Frameworks

Sources:

- [Data-Oriented Design online book, "How is data formed?"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00250000000000000000) (printed-book p18).
- [Data-Oriented Design online book, "The framework"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00260000000000000000) (printed-book p21).
- [Data-Oriented Design online book, "Normalising your data"](https://www.dataorienteddesign.com/dodbook/node3.html#SECTION00330000000000000000) (printed-book p32).

Philosophy: Fabian treats game data as something that keeps changing under
tools, hardware, assets, and design. Object wrappers make the first version easy
to use, but they freeze assumptions and make schema migration painful. A game is
better treated as computations over data.

How Fabian gets there: He surveys asset formats and game-logic data that keep
changing, then points to simulation, high-volume data analysis, and databases as
models for handling complex state. The database comparison matters because it
names validity, transactions, staged commits, idempotent functions, and table
design as ways to keep important state changes controlled.

Take home: Keep source/editor formats, prepared runtime schemas, state updates,
and output records distinct. Build explicit formation, migration, and
validation steps instead of letting a class preserve the first design shape.

## Main Lessons

- The input file is allowed to be messy. The repeated-run data should not be.
  A file can contain names, paths, comments, defaults, and many choices. The
  repeated calculation should receive clean arrays and small structs.

- Do parsing and setup before the repeated run.
  If the same prepared input is used many times, the repeated part should not
  parse files or rebuild tables each time.

  ```zig
  const PreparedItem = struct {
      amount: f64,
      rate: f64,
      group_index: usize,
  };

  fn totalContribution(items: []const PreparedItem, group_weight: []const f64) f64 {
      var total: f64 = 0;
      for (items) |item| {
          total += item.amount * item.rate * group_weight[item.group_index];
      }
      return total;
  }
  ```

  `totalContribution` receives the values it reads. It does not parse names or
  rediscover `group_index`.

- Important state changes should be named.
  A reader should be able to see where input becomes prepared data, where
  prepared data is validated, where state changes, and where output rows are
  written.

- Give each big data change its own function.
  The function names should say which data shape is being built or changed.

- Normalise the prepared data before optimising it.
  Fabian works a whole game-level file into normal-form tables: every fact is
  stored once, optional fields become their own smaller tables instead of
  nullable columns, and repeated groups become rows. The payoff he names is
  change-tolerance. A new feature becomes a new table or column, not a new
  member threaded through every constructor, and old executables can often
  still read newer data. Denormalise later only where a measured hot loop
  earns it, like the prepared group row in the data-shape lesson.

## Practical Example

A renderer supports live material hot-reload: artists save in the editor, the
running engine picks up the change. Over two tool versions the save format
changed shape. Here is the pattern where raw tool input and state changes are
hidden behind one object call.

```zig
pub fn updateMaterials(
    state: *RenderState,
    events: []const MaterialEvent,
    allocator: Allocator,
) !void {
    for (events) |event| {
        try state.applyMaterialEvent(event, allocator);
    }
}
```

The reader cannot see where names are resolved, where invalid events are
rejected, where runtime rows change, or where render bins are rebuilt. It has
a worse property than unreadability, though: if the seventh event in a batch
is invalid, six material rows have already mutated and the `try` aborts the
loop. The engine is now rendering half a save. There is no place to put a
validity check, because formation, validation, and commitment happen inside
one another.

A better approach makes the formation steps visible.

```zig
const RawMaterialV1 = struct {
    shader_name: []const u8,
    texture_path: []const u8,
    blend_text: []const u8,
};

const RawMaterialV2 = struct {
    shader_id_text: []const u8,
    texture_slot: u16,
    alpha_enabled: bool,
};

const PreparedMaterial = struct {
    shader_index: u16,
    texture_index: u16,
    is_alpha: bool,
};
```

Both raw formats can become the same runtime row.

```zig
fn prepareFromNames(
    raw: []const RawMaterialV1,
    shader_names: []const []const u8,
    texture_paths: []const []const u8,
    out: []PreparedMaterial,
) void {
    for (raw, out) |mat, *dst| {
        dst.* = .{
            .shader_index = findIndex(shader_names, mat.shader_name),
            .texture_index = findIndex(texture_paths, mat.texture_path),
            .is_alpha = parseBlendMode(mat.blend_text) == .alpha,
        };
    }
}

fn prepareFromIds(raw: []const RawMaterialV2, out: []PreparedMaterial) void {
    for (raw, out) |mat, *dst| {
        dst.* = .{
            .shader_index = parseSmallId(mat.shader_id_text),
            .texture_index = mat.texture_slot,
            .is_alpha = mat.alpha_enabled,
        };
    }
}
```

The framework step can then name the state changes.

```zig
pub fn updateMaterials(
    state: *RenderState,
    events: []const MaterialEvent,
    storage: *RunStorage,
) !void {
    const changes = try buildMaterialChanges(events, storage.material_changes);
    try validateMaterialChanges(changes, state.materials);
    applyMaterialChanges(state.materials, changes);
    rebuildRenderBins(state.materials, storage.render_bins);
    writeMaterialAuditRows(events, changes, storage.audit_rows);
}
```

The tool format can change without forcing repeated render code to carry names,
paths, or parser rules. The important state changes are also visible: events
become changes, changes are validated, material state is updated, render bins
are rebuilt, and audit rows are written.

This is the part of Fabian's framework argument that goes beyond tidiness: the
staged shape is a transaction. `buildMaterialChanges` produces a proposal that
touches nothing; `validateMaterialChanges` can reject the whole batch against
current state before a single row moves; only then does
`applyMaterialChanges` commit. A bad save from the editor now fails atomically
with a message, instead of leaving the engine half-reloaded — and no rollback
code was written, because nothing was mutated until the batch had already
passed. Databases earned this property with normalised tables, staged commits,
and idempotent operations; the lesson is that prepared-data pipelines get it
the same way, by making formation a phase instead of a side effect.
