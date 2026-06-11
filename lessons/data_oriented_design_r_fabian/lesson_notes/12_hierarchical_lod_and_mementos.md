# Hierarchical LOD And Mementos

Sources:

- [Data-Oriented Design online book, "Hierarchical Level of Detail"](https://www.dataorienteddesign.com/dodbook/node6.html) (printed-book p97).
- [Data-Oriented Design online book, "Mementos"](https://www.dataorienteddesign.com/dodbook/node6.html#SECTION00620000000000000000) (printed-book p101).
- [Data-Oriented Design online book, "JIT mementos"](https://www.dataorienteddesign.com/dodbook/node6.html#SECTION00630000000000000000) (printed-book p103).
- [Data-Oriented Design online book, "Alternative axes"](https://www.dataorienteddesign.com/dodbook/node6.html#SECTION00640000000000000000) (printed-book p106).

Philosophy: Fabian extends existence-based processing to the number of rows
itself. Traditional level of detail swaps a cheap representation in for an
expensive one; hierarchical LOD changes how many entities exist. A distant
attack wave is one row. Only when it gets close does it pop out squadrons, and
squadrons pop out aircraft. "A murder of crows is a computational element, but
each crow is a lower level of detail sub-element of the collective."

How Fabian gets there: His base-defense example has ten thousand aircraft, but
the simulation never holds ten thousand aircraft rows. Waves project blips on
the radar; a wave in range pops a squadron entity and decrements its count; a
squadron in range pops aircraft; an aircraft that crashes replaces itself with
a cheap wreck row. Detail can collapse back upward under load. Mementos solve
the state problem this creates: when a detailed entity is demoted, a small
compressed struct keeps what must survive, so promotion later rebuilds a
consistent entity. JIT mementos go further: when nothing observed the entity,
its state can be generated from a seed, so even the memento need not be stored.

Take home: Let the set of live rows track what the program actually needs to
simulate now. Promote a coarse row into detailed rows at a boundary, demote
detailed rows back into a coarse row plus a small memento, and choose the
detail axis deliberately: distance is one axis, but time since last seen,
player attention, or load are equally valid.

## Main Lessons

- A collective row stands in for members that do not exist yet.

  ```zig
  const Convoy = struct {
      arrival_eta: f32,
      truck_count: u16,
  };

  const Truck = struct {
      position: Vec2,
      cargo: u32,
      fuel: f32,
  };
  ```

  A far-away convoy needs two fields, not `truck_count` copies of a full
  truck. The detailed rows are implicit in the collective row.

- Promotion is a boundary that creates rows.

  ```zig
  fn popTruck(convoy: *Convoy, trucks: *ArrayList(Truck)) !void {
      try trucks.append(spawnTruck(convoy.arrival_eta));
      convoy.truck_count -= 1;
  }
  ```

  The convoy shrinks as trucks become real. A convoy at zero deletes itself,
  because it now represents nothing.

- Demotion keeps a memento, not the whole entity.

  ```zig
  const TruckMemento = struct {
      cargo: u32,
      fuel_quarter: u2, // enough fidelity to rebuild a believable truck
  };
  ```

  The memento stores only what a returning observer could notice. Everything
  else is rebuilt from defaults at promotion time.

- A seed can replace a stored memento.
  If nobody has observed a truck yet, its cargo and wear can be generated from
  `hash(convoy_id, truck_index)`. The same seed gives the same truck every
  time, so unobserved variety costs no memory. Store a real memento only after
  the entity has been touched by something that must stay consistent.

- Distance is only one axis.
  Update frequency is another: fast reactions every tick, slow "hormonal"
  state every hundred ticks, mirroring Fabian's animal-brain example from the
  existential-processing chapter. Recency is another: entities the player has
  not seen for an hour can collapse harder than entities just out of view.

## Practical Example

A city traffic simulation slows down because every vehicle in the city is a
full row.

```zig
const Vehicle = struct {
    position: Vec2,
    velocity: Vec2,
    route: []const NodeId,
    route_index: u32,
    driver_mood: f32,
};

for (vehicles) |*vehicle| {
    try followRoute(vehicle, roads, dt);
}
```

Vehicles ten blocks from the camera run the same pathfinding as the vehicle in
front of the player. The row count, not the per-row cost, is the problem.

The hierarchical shape simulates flows far away and vehicles near.

```zig
const RoadFlow = struct {
    road_id: u32,
    vehicles_per_minute: f32,
    average_speed: f32,
};

// Near the camera: full vehicle rows, full per-row update.
for (live_vehicles.items) |*vehicle| {
    try followRoute(vehicle, roads, dt);
}

// Everywhere else: one row per road, arithmetic instead of simulation.
for (road_flows) |*flow| {
    flow.average_speed = relaxTowards(flow.average_speed, freeSpeed(flow), dt);
}
```

Crossing the boundary spawns and absorbs rows.

```zig
fn promoteVehicle(flow: *RoadFlow, live: *ArrayList(Vehicle), seed: u64) !void {
    try live.append(vehicleFromSeed(flow.road_id, seed));
    flow.vehicles_per_minute -= 1;
}

fn demoteVehicle(vehicle: Vehicle, flow: *RoadFlow) void {
    flow.vehicles_per_minute += 1;
    flow.average_speed = blend(flow.average_speed, vehicle.velocity.length());
}
```

The flow row absorbs a demoted vehicle as statistics. A promoted vehicle is
generated from a seed unless a memento exists for it, which only happens when
the player did something to that specific vehicle. This two-level split is not
a game trick invented here; production traffic simulators ship exactly this
architecture under the name hybrid mesoscopic/microscopic simulation, and
open-world games drive their pedestrian and traffic systems the same way.

The win is structural: the expensive loop's row count now tracks what the
player can perceive, not the size of the city. Ten thousand distant vehicles
cost a handful of flow rows; only the dozens near the camera cost full
simulation. And because the live-row count is a number the engine controls,
it becomes a tunable budget — under load, demote more aggressively — which is
the optimisation-lesson feedback loop applied to existence itself.
