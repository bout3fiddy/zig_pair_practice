const std = @import("std");

const Record = struct {
    metric: f64,
    weight: f64,
    group_id: u32,
    pad: u32,
};

const ResultWithId = struct {
    id: u32,
    numerator: f64,
};

const RangeRow = struct {
    start: u32,
    count: u32,
};

const allocator = std.heap.page_allocator;

pub fn main() !void {
    try benchRows();
    try benchRatio();
    try benchIndexes();
    try benchDirty();
    try benchBranches();
    try benchWorkerLocal();
    try benchPrefixStarts();
}

fn benchRows() !void {
    const n = 262_144;
    const iterations = 800;

    const rows = try allocator.alloc(Record, n);
    defer allocator.free(rows);
    const metric = try allocator.alloc(f64, n);
    defer allocator.free(metric);

    for (rows, metric, 0..) |*row, *metric_value, i| {
        const value = @as(f64, @floatFromInt((i % 97) + 1)) * 0.001;
        row.* = .{
            .metric = value,
            .weight = 0.9,
            .group_id = @intCast(i % 11),
            .pad = 0,
        };
        metric_value.* = value;
    }

    var timer = try std.time.Timer.start();
    var checksum_aos: f64 = 0.0;
    for (0..iterations) |_| {
        checksum_aos += sumAoS(rows);
        std.mem.doNotOptimizeAway(checksum_aos);
    }
    const aos_ns = timer.read();

    timer.reset();
    var checksum_column: f64 = 0.0;
    for (0..iterations) |_| {
        checksum_column += sumColumn(metric);
        std.mem.doNotOptimizeAway(checksum_column);
    }
    const column_ns = timer.read();

    printBench("sum_metric_aos", n, iterations, aos_ns, checksum_aos);
    printBench("sum_metric_column", n, iterations, column_ns, checksum_column);
    printRatio("sum_metric_column_vs_aos", aos_ns, column_ns);
}

fn benchRatio() !void {
    const n = 131_072;
    const iterations = 300;

    const numerator = try allocator.alloc(f64, n);
    defer allocator.free(numerator);
    const denominator = try allocator.alloc(f64, n);
    defer allocator.free(denominator);
    const out = try allocator.alloc(f64, n);
    defer allocator.free(out);

    for (numerator, denominator, 0..) |*l, *e, i| {
        l.* = @as(f64, @floatFromInt((i % 113) + 1));
        e.* = if (i % 257 == 0) 0.0 else @as(f64, @floatFromInt((i % 89) + 1));
    }

    var timer = try std.time.Timer.start();
    var checksum_into: f64 = 0.0;
    for (0..iterations) |_| {
        fillRatioInto(numerator, denominator, out);
        checksum_into += checksum(out);
        std.mem.doNotOptimizeAway(checksum_into);
    }
    const into_ns = timer.read();

    timer.reset();
    var checksum_alloc: f64 = 0.0;
    for (0..iterations) |_| {
        const allocated = try fillRatioAllocated(numerator, denominator);
        checksum_alloc += checksum(allocated);
        allocator.free(allocated);
        std.mem.doNotOptimizeAway(checksum_alloc);
    }
    const alloc_ns = timer.read();

    printBench("fill_ratio_caller_output", n, iterations, into_ns, checksum_into);
    printBench("fill_ratio_allocate_output", n, iterations, alloc_ns, checksum_alloc);
    printRatio("caller_output_vs_allocate_output", alloc_ns, into_ns);
}

fn benchIndexes() !void {
    const row_count = 512;
    const samples_per_row = 4;
    const result_count = 4096;
    const iterations = 30;

    const rows = try allocator.alloc(RangeRow, row_count);
    defer allocator.free(rows);
    const sample_indices = try allocator.alloc(u32, row_count * samples_per_row);
    defer allocator.free(sample_indices);
    const target_ids = try allocator.alloc(u32, row_count * samples_per_row);
    defer allocator.free(target_ids);
    const results = try allocator.alloc(ResultWithId, result_count);
    defer allocator.free(results);
    const out = try allocator.alloc(f64, row_count);
    defer allocator.free(out);

    for (results, 0..) |*result, i| {
        result.* = .{ .id = @intCast(i), .numerator = @as(f64, @floatFromInt((i % 101) + 1)) };
    }

    for (rows, 0..) |*row, row_index| {
        const start = row_index * samples_per_row;
        row.* = .{ .start = @intCast(start), .count = samples_per_row };
        for (0..samples_per_row) |j| {
            const result_index = (row_index * 17 + j * 131) % result_count;
            sample_indices[start + j] = @intCast(result_index);
            target_ids[start + j] = @intCast(result_index);
        }
    }

    var timer = try std.time.Timer.start();
    var checksum_prepared: f64 = 0.0;
    for (0..iterations) |_| {
        integratePrepared(rows, sample_indices, results, out);
        checksum_prepared += checksum(out);
        std.mem.doNotOptimizeAway(checksum_prepared);
    }
    const prepared_ns = timer.read();

    timer.reset();
    var checksum_search: f64 = 0.0;
    for (0..iterations) |_| {
        integrateSearch(rows, target_ids, results, out);
        checksum_search += checksum(out);
        std.mem.doNotOptimizeAway(checksum_search);
    }
    const search_ns = timer.read();

    printBench("integrate_prepared_indexes", row_count, iterations, prepared_ns, checksum_prepared);
    printBench("integrate_linear_search", row_count, iterations, search_ns, checksum_search);
    printRatio("prepared_indexes_vs_linear_search", search_ns, prepared_ns);
}

fn benchDirty() !void {
    const n = 262_144;
    const iterations = 500;

    const values = try allocator.alloc(f64, n);
    defer allocator.free(values);
    const dirty_flags = try allocator.alloc(bool, n);
    defer allocator.free(dirty_flags);
    const dirty_indices = try allocator.alloc(u32, n);
    defer allocator.free(dirty_indices);
    const out = try allocator.alloc(f64, n);
    defer allocator.free(out);

    var dirty_count: usize = 0;
    for (values, dirty_flags, 0..) |*id, *dirty, i| {
        id.* = 750.0 + @as(f64, @floatFromInt(i)) * 0.001;
        dirty.* = i % 16 == 0;
        if (dirty.*) {
            dirty_indices[dirty_count] = @intCast(i);
            dirty_count += 1;
        }
    }

    var timer = try std.time.Timer.start();
    var checksum_scan: f64 = 0.0;
    for (0..iterations) |_| {
        refreshScanAll(values, dirty_flags, out);
        checksum_scan += checksumDirtyPositions(out, dirty_indices[0..dirty_count]);
        std.mem.doNotOptimizeAway(checksum_scan);
    }
    const scan_ns = timer.read();

    timer.reset();
    var checksum_list: f64 = 0.0;
    for (0..iterations) |_| {
        refreshDirtyList(values, dirty_indices[0..dirty_count], out);
        checksum_list += checksum(out[0..dirty_count]);
        std.mem.doNotOptimizeAway(checksum_list);
    }
    const list_ns = timer.read();

    printBench("refresh_scan_all_flags", n, iterations, scan_ns, checksum_scan);
    printBench("refresh_dirty_index_list", dirty_count, iterations, list_ns, checksum_list);
    printRatio("dirty_index_list_vs_scan_all", scan_ns, list_ns);
}

fn benchBranches() !void {
    const n = 262_144;
    const iterations = 1000;

    const flags = try allocator.alloc(u8, n);
    defer allocator.free(flags);
    const values = try allocator.alloc(i32, n);
    defer allocator.free(values);
    const grouped = try allocator.alloc(i32, n);
    defer allocator.free(grouped);

    var grouped_count: usize = 0;
    for (flags, values, 0..) |*flag, *value, i| {
        const keep = ((i * 1103515245 + 12345) >> 8) & 1;
        flag.* = @intCast(keep);
        value.* = @intCast((i % 127) + 1);
        if (keep != 0) {
            grouped[grouped_count] = value.*;
            grouped_count += 1;
        }
    }

    var timer = try std.time.Timer.start();
    var checksum_branchy: i64 = 0;
    for (0..iterations) |_| {
        checksum_branchy += sumSelected(flags, values);
        std.mem.doNotOptimizeAway(checksum_branchy);
    }
    const branchy_ns = timer.read();

    timer.reset();
    var checksum_grouped: i64 = 0;
    for (0..iterations) |_| {
        checksum_grouped += sumI32(grouped[0..grouped_count]);
        std.mem.doNotOptimizeAway(checksum_grouped);
    }
    const grouped_ns = timer.read();

    timer.reset();
    var checksum_group_each_time: i64 = 0;
    for (0..iterations) |_| {
        const selected = collectSelected(flags, values, grouped);
        checksum_group_each_time += sumI32(selected);
        std.mem.doNotOptimizeAway(checksum_group_each_time);
    }
    const group_each_time_ns = timer.read();

    printBenchInt("sum_selected_branchy", n, iterations, branchy_ns, checksum_branchy);
    printBenchInt("sum_grouped_values", grouped_count, iterations, grouped_ns, checksum_grouped);
    printRatio("grouped_values_vs_branchy", branchy_ns, grouped_ns);
    printBenchInt("group_then_sum_values", n, iterations, group_each_time_ns, checksum_group_each_time);
    printRatio("group_then_sum_vs_branchy", branchy_ns, group_each_time_ns);
}

fn benchWorkerLocal() !void {
    const n = 262_144;
    const iterations = 1000;

    const values = try allocator.alloc(f64, n);
    defer allocator.free(values);

    for (values, 0..) |*value, i| {
        value.* = @as(f64, @floatFromInt((i % 127) + 1));
    }

    var timer = try std.time.Timer.start();
    var checksum_local: f64 = 0.0;
    for (0..iterations) |_| {
        checksum_local += workerLocalSum(values);
        std.mem.doNotOptimizeAway(checksum_local);
    }
    const local_ns = timer.read();

    timer.reset();
    var shared_slot: f64 = 0.0;
    var checksum_shared: f64 = 0.0;
    for (0..iterations) |_| {
        shared_slot = 0.0;
        workerWriteEveryItem(values, &shared_slot);
        checksum_shared += shared_slot;
        std.mem.doNotOptimizeAway(checksum_shared);
    }
    const shared_ns = timer.read();

    printBench("worker_local_sum", n, iterations, local_ns, checksum_local);
    printBench("worker_write_every_item", n, iterations, shared_ns, checksum_shared);
    printRatio("worker_local_vs_write_every_item", shared_ns, local_ns);
}

fn benchPrefixStarts() !void {
    const set_count = 16_384;
    const query_count = 262_144;
    const iterations = 30;

    const counts = try allocator.alloc(u32, set_count);
    defer allocator.free(counts);
    const starts = try allocator.alloc(u32, set_count);
    defer allocator.free(starts);
    const queries = try allocator.alloc(u32, query_count);
    defer allocator.free(queries);

    for (counts, 0..) |*count, i| {
        count.* = @intCast((i % 7) + 1);
    }
    prefixStarts(counts, starts);
    for (queries, 0..) |*query, i| {
        query.* = @intCast((i * 37) % set_count);
    }

    var timer = try std.time.Timer.start();
    var checksum_prepared: u64 = 0;
    for (0..iterations) |_| {
        checksum_prepared += queryPreparedStarts(starts, queries);
        std.mem.doNotOptimizeAway(checksum_prepared);
    }
    const prepared_ns = timer.read();

    timer.reset();
    var checksum_scan: u64 = 0;
    for (0..iterations) |_| {
        checksum_scan += queryByResummingCounts(counts, queries);
        std.mem.doNotOptimizeAway(checksum_scan);
    }
    const scan_ns = timer.read();

    printBenchInt("query_prepared_starts", query_count, iterations, prepared_ns, @intCast(checksum_prepared));
    printBenchInt("query_resum_counts", query_count, iterations, scan_ns, @intCast(checksum_scan));
    printRatio("prepared_starts_vs_resum_counts", scan_ns, prepared_ns);
}

fn sumAoS(rows: []const Record) f64 {
    var total: f64 = 0.0;
    for (rows) |row| total += row.metric;
    return total;
}

fn sumColumn(values: []const f64) f64 {
    var total: f64 = 0.0;
    for (values) |value| total += value;
    return total;
}

fn fillRatioInto(numerator: []const f64, denominator: []const f64, out: []f64) void {
    for (numerator, denominator, out) |l, e, *dst| {
        dst.* = if (e != 0.0) l / e else 0.0;
    }
}

fn fillRatioAllocated(numerator: []const f64, denominator: []const f64) ![]f64 {
    const out = try allocator.alloc(f64, numerator.len);
    fillRatioInto(numerator, denominator, out);
    return out;
}

fn integratePrepared(
    rows: []const RangeRow,
    sample_indices: []const u32,
    results: []const ResultWithId,
    out: []f64,
) void {
    for (rows, out) |row, *dst| {
        var sum: f64 = 0.0;
        const start: usize = @intCast(row.start);
        const end = start + row.count;
        var k = start;
        while (k < end) : (k += 1) {
            const result_index: usize = @intCast(sample_indices[k]);
            sum += results[result_index].numerator;
        }
        dst.* = sum;
    }
}

fn integrateSearch(rows: []const RangeRow, target_ids: []const u32, results: []const ResultWithId, out: []f64) void {
    for (rows, out) |row, *dst| {
        var sum: f64 = 0.0;
        const start: usize = @intCast(row.start);
        const end = start + row.count;
        var k = start;
        while (k < end) : (k += 1) {
            sum += findValueById(results, target_ids[k]);
        }
        dst.* = sum;
    }
}

fn findValueById(results: []const ResultWithId, id: u32) f64 {
    for (results) |result| {
        if (result.id == id) return result.numerator;
    }
    return 0.0;
}

fn refreshScanAll(values: []const f64, dirty_flags: []const bool, out: []f64) void {
    for (values, dirty_flags, out) |id, dirty, *dst| {
        if (dirty) dst.* = id * 2.0 + 1.0;
    }
}

fn refreshDirtyList(values: []const f64, dirty_indices: []const u32, out: []f64) void {
    for (dirty_indices, 0..) |index, out_index| {
        const id_index: usize = @intCast(index);
        out[out_index] = values[id_index] * 2.0 + 1.0;
    }
}

fn sumSelected(flags: []const u8, values: []const i32) i32 {
    var total: i32 = 0;
    for (flags, values) |flag, value| {
        if (flag != 0) total += value;
    }
    return total;
}

fn collectSelected(flags: []const u8, values: []const i32, out: []i32) []const i32 {
    var written: usize = 0;
    for (flags, values) |flag, value| {
        if (flag == 0) continue;
        out[written] = value;
        written += 1;
    }
    return out[0..written];
}

fn sumI32(values: []const i32) i32 {
    var total: i32 = 0;
    for (values) |value| total += value;
    return total;
}

fn workerLocalSum(values: []const f64) f64 {
    var total: f64 = 0.0;
    for (values) |value| total += value;
    return total;
}

fn workerWriteEveryItem(values: []const f64, shared_slot: *volatile f64) void {
    for (values) |value| {
        shared_slot.* = shared_slot.* + value;
    }
}

fn prefixStarts(counts: []const u32, starts: []u32) void {
    starts[0] = 0;
    var i: usize = 1;
    while (i < counts.len) : (i += 1) {
        starts[i] = starts[i - 1] + counts[i - 1];
    }
}

fn queryPreparedStarts(starts: []const u32, queries: []const u32) u64 {
    var total: u64 = 0;
    for (queries) |query| {
        total += starts[@intCast(query)];
    }
    return total;
}

fn queryByResummingCounts(counts: []const u32, queries: []const u32) u64 {
    var total: u64 = 0;
    for (queries) |query| {
        var start: u64 = 0;
        var i: usize = 0;
        const end: usize = @intCast(query);
        while (i < end) : (i += 1) {
            start += counts[i];
        }
        total += start;
    }
    return total;
}

fn checksum(values: []const f64) f64 {
    var total: f64 = 0.0;
    for (values) |value| total += value;
    return total;
}

fn checksumDirtyPositions(values: []const f64, dirty_indices: []const u32) f64 {
    var total: f64 = 0.0;
    for (dirty_indices) |index| {
        total += values[@intCast(index)];
    }
    return total;
}

fn printBench(name: []const u8, items: usize, iterations: usize, elapsed_ns: u64, check: f64) void {
    const ns_per_item = @as(f64, @floatFromInt(elapsed_ns)) /
        (@as(f64, @floatFromInt(items)) * @as(f64, @floatFromInt(iterations)));
    std.debug.print(
        "bench {s} items={} iterations={} elapsed_ns={} ns_per_item={d:.3} checksum={d:.3}\n",
        .{ name, items, iterations, elapsed_ns, ns_per_item, check },
    );
}

fn printBenchInt(name: []const u8, items: usize, iterations: usize, elapsed_ns: u64, check: i64) void {
    const ns_per_item = @as(f64, @floatFromInt(elapsed_ns)) /
        (@as(f64, @floatFromInt(items)) * @as(f64, @floatFromInt(iterations)));
    std.debug.print(
        "bench {s} items={} iterations={} elapsed_ns={} ns_per_item={d:.3} checksum={}\n",
        .{ name, items, iterations, elapsed_ns, ns_per_item, check },
    );
}

fn printRatio(name: []const u8, slow_ns: u64, fast_ns: u64) void {
    const ratio = @as(f64, @floatFromInt(slow_ns)) / @as(f64, @floatFromInt(fast_ns));
    std.debug.print("ratio {s} {d:.2}x\n", .{ name, ratio });
}
