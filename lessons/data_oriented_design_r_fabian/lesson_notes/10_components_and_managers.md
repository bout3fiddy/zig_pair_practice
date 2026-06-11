# Components And Managers

Sources:

- [Data-Oriented Design online book, "Component Based Objects"](https://www.dataorienteddesign.com/dodbook/node5.html) (printed-book p83).
- [Data-Oriented Design online book, "Towards managers"](https://www.dataorienteddesign.com/dodbook/node5.html#SECTION00530000000000000000) (printed-book p91).
- [Data-Oriented Design online book, "There is no entity"](https://www.dataorienteddesign.com/dodbook/node5.html#SECTION00540000000000000000) (printed-book p94).

Philosophy: Fabian argues an object is nothing more than the sum of its parts.
A "Car" is not a class that owns physics, meshes, and input; it is a physics
row, some renderable rows, and a control row that happen to share an id. The
name is a tag applied afterwards, if it is needed at all.

How Fabian gets there: He contrasts compound objects, where components are
members of a root instance that still updates instance by instance, with
manager-driven systems, where each component type lives in its own array and a
manager updates the whole array in one pass. He cites the Unity "10,000
Update() calls" problem: per-instance dispatch pays a boundary crossing per
object, while managers update components in sync and open the door to
parallelism. The end state removes the entity class entirely: parallel sparse
arrays keyed by id, where creating a player is a handful of inserts.

Take home: Organize update code by component type, not by object instance. Let
each system walk its own table in one pass, decide system ordering once at the
manager level, and let an entity be only an id that connects rows across
tables.

## Main Lessons

- A root object that updates its parts hides N small passes inside one big one.

  ```zig
  for (machines) |*machine| {
      machine.motor.update(dt);
      machine.sensors.update(dt);
      machine.display.update(dt);
  }
  ```

  Each iteration touches three unrelated kinds of data, so no single pass is
  compact, and motor work interleaves with display work.

- A manager updates one component table in one pass.

  ```zig
  fn updateMotors(motors: []Motor, dt: f32) void {
      for (motors) |*motor| motor.rpm += motor.torque * dt;
  }

  updateMotors(plant.motors, dt);
  updateSensors(plant.sensors, plant.motors);
  updateDisplays(plant.displays, plant.sensors);
  ```

  Each pass reads one shape of data. The call order at the top is the only
  place that decides motors finish before sensors read them, which is also
  what makes it safe to run independent passes in parallel.

- The entity is an id, not a struct.

  ```zig
  const Plant = struct {
      motors: AutoArrayHashMap(u32, Motor),
      sensors: AutoArrayHashMap(u32, Sensor),
      displays: AutoArrayHashMap(u32, Display),
  };

  fn addPump(plant: *Plant, id: u32, torque: f32) !void {
      try plant.motors.put(id, .{ .torque = torque, .rpm = 0 });
      try plant.sensors.put(id, .{ .source = id });
  }
  ```

  A pump is a motor row and a sensor row sharing an id. A fan might be a motor
  row only. Nothing forces every id to exist in every table, and a new kind of
  machine is a new combination of inserts, not a new class.

- Components make existence-based processing natural.
  "Has a motor" is membership in the motor table. The motor pass already visits
  exactly the ids that have motors, so there is no `has_motor` flag and no
  branch per machine. This is the same rule as the existence-based processing
  lesson, applied at architecture scale.

- Composition replaces the inheritance diamond.
  When a designer wants a sensor that also displays, the answer is a row in
  both tables, not a `SensorDisplay` class that multiple-inherits and forces a
  hierarchy rebuild.

## Practical Example

A drone-fleet operations product simulates thousands of aircraft for mission
planning. Mid-project, a customer pays for camera payloads: a subset of drones
must capture a geotagged frame on a schedule. The instance-shaped change is
the one most codebases make — extend the class.

```zig
const Drone = struct {
    position: Vec3,
    velocity: Vec3,
    battery: f32,
    camera: ?Camera, // null for most of the fleet

    fn update(self: *Drone, dt: f32) void {
        self.position = self.position.add(self.velocity.scale(dt));
        self.battery -= dt * drain(self.velocity);
        if (self.camera) |*camera| camera.captureFrame(self.position);
    }
};
```

Three things degraded at once. Every drone now carries camera bytes through
the movement pass, widening the stride for a feature most rows do not have.
The camera question is asked per drone per update, which is the boolean
problem from the existence lesson wearing an optional. And the next feature,
and the one after, will land in the same struct and the same update, because
the class is where features go in this shape.

The component shape adds a table instead, and the table stores its join.

```zig
const CameraEntry = struct {
    drone_index: u32, // captured once, when the payload is attached
    camera: Camera,
};

const Fleet = struct {
    positions: []Vec3,
    velocities: []Vec3,
    batteries: []f32,
    cameras: ArrayList(CameraEntry),
};

fn updateMovement(fleet: *Fleet, dt: f32) void {
    for (fleet.positions, fleet.velocities) |*position, velocity| {
        position.* = position.add(velocity.scale(dt));
    }
}

fn captureFrames(fleet: *Fleet) void {
    for (fleet.cameras.items) |*entry| {
        entry.camera.captureFrame(fleet.positions[entry.drone_index]);
    }
}
```

Movement still walks two tight columns; its data and its loop did not change
when cameras shipped. The camera pass visits exactly the drones that have
cameras, with no per-drone question, because attaching a payload was an insert
and detaching is a remove — existence-based processing at architecture scale.
Note where the join cost went: `drone_index` was resolved once at the attach
boundary, so the per-frame pass pays a direct array read instead of a search.
The price is bookkeeping at the rare edge: if drones are removed by swap, the
camera rows pointing at the moved drone must be patched, which is a few lines
in one place rather than a branch in every frame.

The structural payoff is what Fabian calls update by type, not by instance.
`updateMovement` and `captureFrames` share no mutable state, so the manager
that calls them decides their order once — or runs them on different threads —
without any instance knowing. In the class shape that decision was unmakeable,
because each drone interleaved both jobs inside one `update`.

The deeper point is that nothing in the system is a Drone anymore. A drone is
a position row, a velocity row, a battery row, and maybe a camera row sharing
an index. When the customer later wants relay drones with no battery
simulation, or ground stations with cameras but no movement, both are new
combinations of inserts. No class hierarchy gets redesigned, because there is
no class to redesign — the entity was never anything more than the sum of its
rows.
