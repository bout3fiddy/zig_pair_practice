const MetricRow = extern struct {
    metric: f64,
    weight: f64,
    group_id: u32,
    pad: u32,
};

const NestedMetrics = extern struct {
    metric: f64,
    weight: f64,
    group_id: u32,
    pad: u32,
};

const VerboseRecord = extern struct {
    record_id: u64,
    input_row: u64,
    metrics: *const NestedMetrics,
    debug_id: u64,
};

const RangeRow = extern struct {
    start: u32,
    count: u32,
};

const ResultValue = extern struct {
    numerator: f64,
    denominator: f64,
};

const KeyPayload = extern struct {
    time: f64,
    payload_a: f64,
    payload_b: f64,
    payload_c: f64,
};

const FullModel = extern struct {
    values: [*]const f64,
    len: usize,
    payloads: [*]const KeyPayload,
    debug_epoch: u64,
};

const JobInput = extern struct {
    base_value: f64,
    scale: f64,
};

const LookupData = extern struct {
    multiplier: f64,
    bias: f64,
};

const PreparedJob = extern struct {
    value: f64,
    offset: f64,
};

const OutputList = extern struct {
    items: [*]f64,
    len: usize,
    capacity: usize,
};

const AllocatorLike = extern struct {
    alloc: *const fn (usize) callconv(.c) [*]f64,
    free: *const fn ([*]f64) callconv(.c) void,
};

noinline fn prepareInputForCodegen(scene: *const JobInput, assets: *const LookupData) PreparedJob {
    return .{
        .value = scene.base_value * assets.multiplier,
        .offset = scene.scale + assets.bias,
    };
}

noinline fn runPreparedForCodegen(prepared: *const PreparedJob) f64 {
    return prepared.value + prepared.offset;
}

export fn sumMetricRows(rows_ptr: [*]const MetricRow, len: usize) f64 {
    const rows = rows_ptr[0..len];
    var total: f64 = 0.0;
    for (rows) |row| {
        total += row.metric;
    }
    return total;
}

export fn sumMetricRowsVerboseRecord(rows_ptr: [*]const VerboseRecord, len: usize) f64 {
    const rows = rows_ptr[0..len];
    var total: f64 = 0.0;
    for (rows) |row| {
        total += row.metrics.metric;
    }
    return total;
}

export fn sumMetricColumn(values_ptr: [*]const f64, len: usize) f64 {
    const values = values_ptr[0..len];
    var total: f64 = 0.0;
    for (values) |value| {
        total += value;
    }
    return total;
}

export fn prepareEveryProduct(scene: *const JobInput, assets: *const LookupData, product_count: usize) f64 {
    var total: f64 = 0.0;
    for (0..product_count) |_| {
        const prepared = prepareInputForCodegen(scene, assets);
        total += runPreparedForCodegen(&prepared);
    }
    return total;
}

export fn runAlreadyPreparedProducts(prepared: *const PreparedJob, product_count: usize) f64 {
    var total: f64 = 0.0;
    for (0..product_count) |_| {
        total += runPreparedForCodegen(prepared);
    }
    return total;
}

export fn fillOutputValues(rows_ptr: [*]const MetricRow, out_ptr: [*]f64, len: usize, scale: f64) void {
    const rows = rows_ptr[0..len];
    const out = out_ptr[0..len];
    for (rows, out) |row, *dst| {
        dst.* = @mulAdd(f64, row.metric, row.weight, scale);
    }
}

export fn appendOutputValuesChecked(
    rows_ptr: [*]const MetricRow,
    out_list: *OutputList,
    len: usize,
    scale: f64,
) usize {
    const rows = rows_ptr[0..len];
    for (rows) |row| {
        if (out_list.len >= out_list.capacity) return out_list.len;
        out_list.items[out_list.len] = @mulAdd(f64, row.metric, row.weight, scale);
        out_list.len += 1;
    }
    return out_list.len;
}

export fn fillRatio(
    numerator_ptr: [*]const f64,
    denominator_ptr: [*]const f64,
    out_ptr: [*]f64,
    len: usize,
) void {
    const numerator = numerator_ptr[0..len];
    const denominator = denominator_ptr[0..len];
    const out = out_ptr[0..len];
    for (numerator, denominator, out) |l, e, *dst| {
        dst.* = if (e != 0.0) l / e else 0.0;
    }
}

export fn fillRatioAllocateLike(
    allocator: *const AllocatorLike,
    numerator_ptr: [*]const f64,
    denominator_ptr: [*]const f64,
    len: usize,
) f64 {
    const out_ptr = allocator.alloc(len);
    const numerator = numerator_ptr[0..len];
    const denominator = denominator_ptr[0..len];
    const out = out_ptr[0..len];

    for (numerator, denominator, out) |l, e, *dst| {
        dst.* = if (e != 0.0) l / e else 0.0;
    }

    const first = if (len != 0) out[0] else 0.0;
    allocator.free(out_ptr);

    return first;
}

export fn fillRatioNoAlias(
    noalias numerator_ptr: [*]const f64,
    noalias denominator_ptr: [*]const f64,
    noalias out_ptr: [*]f64,
    len: usize,
) void {
    const numerator = numerator_ptr[0..len];
    const denominator = denominator_ptr[0..len];
    const out = out_ptr[0..len];
    for (numerator, denominator, out) |l, e, *dst| {
        dst.* = if (e != 0.0) l / e else 0.0;
    }
}

export fn integrateIndexed(
    rows_ptr: [*]const RangeRow,
    sample_indices_ptr: [*]const u32,
    results_ptr: [*]const ResultValue,
    out_ptr: [*]f64,
    row_len: usize,
) void {
    const rows = rows_ptr[0..row_len];
    const out = out_ptr[0..row_len];
    for (rows, out) |row, *dst| {
        var integrated: f64 = 0.0;
        var k: usize = @intCast(row.start);
        const end = k + @as(usize, @intCast(row.count));
        while (k < end) : (k += 1) {
            const result_index: usize = @intCast(sample_indices_ptr[k]);
            integrated += results_ptr[result_index].numerator;
        }
        dst.* = integrated;
    }
}

export fn integrateLinearSearch(
    rows_ptr: [*]const RangeRow,
    sample_values_ptr: [*]const f64,
    result_values_ptr: [*]const f64,
    results_ptr: [*]const ResultValue,
    out_ptr: [*]f64,
    row_len: usize,
    result_len: usize,
) void {
    const rows = rows_ptr[0..row_len];
    const out = out_ptr[0..row_len];
    for (rows, out) |row, *dst| {
        var integrated: f64 = 0.0;
        var k: usize = @intCast(row.start);
        const end = k + @as(usize, @intCast(row.count));
        while (k < end) : (k += 1) {
            const id = sample_values_ptr[k];
            var result_index: usize = 0;
            while (result_index < result_len) : (result_index += 1) {
                if (result_values_ptr[result_index] == id) break;
            }
            integrated += results_ptr[result_index].numerator;
        }
        dst.* = integrated;
    }
}

export fn lowerBound(values_ptr: [*]const f64, len: usize, needle: f64) usize {
    const values = values_ptr[0..len];
    var low: usize = 0;
    var high: usize = values.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (values[mid] < needle) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

export fn lowerBoundInModel(model: *const FullModel, needle: f64) usize {
    const values = model.values[0..model.len];
    var low: usize = 0;
    var high: usize = values.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (values[mid] < needle) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

export fn lookupPayloadLinear(payloads_ptr: [*]const KeyPayload, len: usize, needle: f64) KeyPayload {
    const payloads = payloads_ptr[0..len];
    for (payloads) |payload| {
        if (payload.time >= needle) return payload;
    }
    return payloads[len - 1];
}

export fn refreshDirty(values_ptr: [*]const f64, out_ptr: [*]f64, dirty_len: usize) void {
    const values = values_ptr[0..dirty_len];
    const out = out_ptr[0..dirty_len];
    for (values, out) |value, *dst| {
        dst.* = value * 2.0 + 1.0;
    }
}

export fn refreshScanAllFlags(values_ptr: [*]const f64, flags_ptr: [*]const u8, out_ptr: [*]f64, len: usize) void {
    const values = values_ptr[0..len];
    const flags = flags_ptr[0..len];
    const out = out_ptr[0..len];
    for (values, flags, out) |value, flag, *dst| {
        if (flag != 0) {
            dst.* = value * 2.0 + 1.0;
        }
    }
}

export fn ensureOptionalStorage(states_count: usize, capacity: usize) usize {
    if (states_count == 0) {
        return 0;
    }
    if (capacity >= states_count) {
        return capacity;
    }
    return states_count;
}

export fn prefixStarts(counts_ptr: [*]const u32, starts_ptr: [*]u32, len: usize) void {
    if (len == 0) return;

    const counts = counts_ptr[0..len];
    const starts = starts_ptr[0..len];
    starts[0] = 0;

    var i: usize = 1;
    while (i < len) : (i += 1) {
        starts[i] = starts[i - 1] + counts[i - 1];
    }
}

export fn startByResummingCounts(counts_ptr: [*]const u32, index: usize) u32 {
    var start: u32 = 0;
    var i: usize = 0;
    while (i < index) : (i += 1) {
        start += counts_ptr[i];
    }
    return start;
}

export fn workerSum(values_ptr: [*]const f64, start: usize, end: usize) f64 {
    var local: f64 = 0.0;
    var i = start;
    while (i < end) : (i += 1) {
        local += values_ptr[i];
    }
    return local;
}

export fn workerWriteEveryItem(values_ptr: [*]const f64, partial_sum: *f64, start: usize, end: usize) f64 {
    partial_sum.* = 0.0;
    var i = start;
    while (i < end) : (i += 1) {
        partial_sum.* += values_ptr[i];
    }
    return partial_sum.*;
}

export fn sumSelected(flags_ptr: [*]const u8, values_ptr: [*]const i32, len: usize) i32 {
    const flags = flags_ptr[0..len];
    const values = values_ptr[0..len];
    var selected_total: i32 = 0;
    for (flags, values) |flag, value| {
        if (flag != 0) {
            selected_total += value;
        }
    }
    return selected_total;
}

export fn sumGroupedValues(values_ptr: [*]const i32, len: usize) i32 {
    const values = values_ptr[0..len];
    var selected_total: i32 = 0;
    for (values) |value| {
        selected_total += value;
    }
    return selected_total;
}

export fn sum(values_ptr: [*]const f64, len: usize) f64 {
    const values = values_ptr[0..len];
    var total: f64 = 0.0;
    for (values) |value| {
        total += value;
    }
    return total;
}
