const std = @import("std");

pub const default_request_state_path = ".sui/sui_config/request_state.json";
pub var test_request_state_path_override: ?[]const u8 = null;

pub const OwnedRequestEntry = struct {
    id: []u8,
    kind: []u8,
    state: []u8,
    request_json: ?[]u8 = null,
    artifact_json: ?[]u8 = null,
    digest: ?[]u8 = null,
    correlation_id: ?[]u8 = null,
    created_at_ms: i64,
    updated_at_ms: i64,
    submit_count: u64 = 0,
    last_error: ?[]u8 = null,

    pub fn deinit(self: *OwnedRequestEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.kind);
        allocator.free(self.state);
        if (self.request_json) |value| allocator.free(value);
        if (self.artifact_json) |value| allocator.free(value);
        if (self.digest) |value| allocator.free(value);
        if (self.correlation_id) |value| allocator.free(value);
        if (self.last_error) |value| allocator.free(value);
    }
};

pub const OwnedRequestState = struct {
    entries: []OwnedRequestEntry,

    pub fn deinit(self: *OwnedRequestState, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
    }
};

fn emptyRequestState(allocator: std.mem.Allocator) !OwnedRequestState {
    return .{ .entries = try allocator.alloc(OwnedRequestEntry, 0) };
}

fn expandTildePath(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    if (path.len == 0 or std.mem.eql(u8, path, "~")) return null;
    if (!std.mem.startsWith(u8, path, "~/")) {
        return try allocator.dupe(u8, path);
    }

    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    const expanded = try std.fs.path.join(allocator, &.{ home_dir, path[2..] });
    defer allocator.free(expanded);
    return try allocator.dupe(u8, expanded);
}

fn defaultRequestStatePath(allocator: std.mem.Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_request_state_path });
}

pub fn resolveDefaultRequestStatePath(allocator: std.mem.Allocator) !?[]const u8 {
    if (test_request_state_path_override) |override_path| {
        if (override_path.len == 0) return null;
        return try allocator.dupe(u8, override_path);
    }

    const env_or_default_path = std.process.getEnvVarOwned(allocator, "SUI_REQUEST_STATE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try defaultRequestStatePath(allocator),
        else => return err,
    };
    if (env_or_default_path == null) return null;
    const path = env_or_default_path.?;
    defer allocator.free(path);
    if (path.len == 0) return null;

    return try expandTildePath(allocator, path);
}

fn readFileAtPathAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return try file.readToEndAlloc(allocator, max_bytes);
    }
    return try std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
}

fn ensureParentPath(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    if (std.fs.path.isAbsolute(parent)) {
        var root = try std.fs.openDirAbsolute("/", .{});
        defer root.close();
        try root.makePath(std.mem.trimLeft(u8, parent, "/"));
        return;
    }
    try std.fs.cwd().makePath(parent);
}

fn writeFileAtPath(path: []const u8, data: []const u8) !void {
    try ensureParentPath(path);
    if (std.fs.path.isAbsolute(path)) {
        var file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
        return;
    }
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn jsonOptionalStringDup(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8) !?[]u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCli,
    };
}

fn jsonRequiredStringDup(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8) ![]u8 {
    const value = object.get(key) orelse return error.InvalidCli;
    return switch (value) {
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCli,
    };
}

fn jsonRequiredI64(object: std.json.ObjectMap, key: []const u8) !i64 {
    const value = object.get(key) orelse return error.InvalidCli;
    return switch (value) {
        .integer => |number| number,
        else => error.InvalidCli,
    };
}

fn jsonOptionalU64(object: std.json.ObjectMap, key: []const u8) !?u64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .null => null,
        .integer => |number| {
            if (number < 0) return error.InvalidCli;
            return @intCast(number);
        },
        else => error.InvalidCli,
    };
}

pub fn loadDefaultRequestState(allocator: std.mem.Allocator) !OwnedRequestState {
    const state_path = try resolveDefaultRequestStatePath(allocator) orelse return try emptyRequestState(allocator);
    defer allocator.free(state_path);

    const contents = readFileAtPathAlloc(allocator, state_path, 4 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return try emptyRequestState(allocator),
        else => return err,
    };
    defer allocator.free(contents);

    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return try emptyRequestState(allocator);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return error.InvalidCli;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCli;

    const entries_value = parsed.value.object.get("entries") orelse return try emptyRequestState(allocator);
    if (entries_value != .array) return error.InvalidCli;

    const entries = try allocator.alloc(OwnedRequestEntry, entries_value.array.items.len);

    var initialized: usize = 0;
    errdefer {
        for (entries[0..initialized]) |*entry| entry.deinit(allocator);
        allocator.free(entries);
    }

    for (entries_value.array.items, 0..) |item, index| {
        if (item != .object) return error.InvalidCli;
        entries[index] = .{
            .id = try jsonRequiredStringDup(allocator, item.object, "id"),
            .kind = try jsonRequiredStringDup(allocator, item.object, "kind"),
            .state = try jsonRequiredStringDup(allocator, item.object, "state"),
            .request_json = try jsonOptionalStringDup(allocator, item.object, "request_json"),
            .artifact_json = try jsonOptionalStringDup(allocator, item.object, "artifact_json"),
            .digest = try jsonOptionalStringDup(allocator, item.object, "digest"),
            .correlation_id = try jsonOptionalStringDup(allocator, item.object, "correlation_id"),
            .created_at_ms = try jsonRequiredI64(item.object, "created_at_ms"),
            .updated_at_ms = try jsonRequiredI64(item.object, "updated_at_ms"),
            .submit_count = (try jsonOptionalU64(item.object, "submit_count")) orelse 0,
            .last_error = try jsonOptionalStringDup(allocator, item.object, "last_error"),
        };
        initialized += 1;
    }

    return .{ .entries = entries };
}

pub fn writeDefaultRequestState(
    allocator: std.mem.Allocator,
    state: *const OwnedRequestState,
) !void {
    const state_path = try resolveDefaultRequestStatePath(allocator) orelse return error.InvalidCli;
    defer allocator.free(state_path);

    var encoded = std.ArrayList(u8){};
    defer encoded.deinit(allocator);
    const writer = encoded.writer(allocator);

    try writer.writeAll("{\"entries\":[");
    for (state.entries, 0..) |entry, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writer.writeAll("\"id\":");
        try writer.print("{f}", .{std.json.fmt(entry.id, .{})});
        try writer.writeAll(",\"kind\":");
        try writer.print("{f}", .{std.json.fmt(entry.kind, .{})});
        try writer.writeAll(",\"state\":");
        try writer.print("{f}", .{std.json.fmt(entry.state, .{})});
        try writer.writeAll(",\"request_json\":");
        if (entry.request_json) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"artifact_json\":");
        if (entry.artifact_json) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"digest\":");
        if (entry.digest) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"correlation_id\":");
        if (entry.correlation_id) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"created_at_ms\":{d}", .{entry.created_at_ms});
        try writer.print(",\"updated_at_ms\":{d}", .{entry.updated_at_ms});
        try writer.print(",\"submit_count\":{d}", .{entry.submit_count});
        try writer.writeAll(",\"last_error\":");
        if (entry.last_error) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("}");
    }
    try writer.writeAll("]}");

    try writeFileAtPath(state_path, encoded.items);
}

test "request_state writes and reloads entries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const state_path = try std.fmt.allocPrint(allocator, "tmp_request_state_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(state_path);
    defer std.fs.cwd().deleteFile(state_path) catch {};

    const old_override = test_request_state_path_override;
    test_request_state_path_override = state_path;
    defer test_request_state_path_override = old_override;

    var entries = try allocator.alloc(OwnedRequestEntry, 1);
    entries[0] = .{
        .id = try allocator.dupe(u8, "job-1"),
        .kind = try allocator.dupe(u8, "schedule_job"),
        .state = try allocator.dupe(u8, "scheduled"),
        .request_json = try allocator.dupe(u8, "{\"sender\":\"0xabc\"}"),
        .artifact_json = try allocator.dupe(u8, "{\"artifact_kind\":\"schedule_job\"}"),
        .digest = null,
        .correlation_id = try allocator.dupe(u8, "req-1"),
        .created_at_ms = 100,
        .updated_at_ms = 200,
        .submit_count = 1,
        .last_error = null,
    };
    var state = OwnedRequestState{ .entries = entries };
    defer state.deinit(allocator);

    try writeDefaultRequestState(allocator, &state);

    var loaded = try loadDefaultRequestState(allocator);
    defer loaded.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), loaded.entries.len);
    try testing.expectEqualStrings("job-1", loaded.entries[0].id);
    try testing.expectEqualStrings("schedule_job", loaded.entries[0].kind);
    try testing.expectEqualStrings("scheduled", loaded.entries[0].state);
    try testing.expectEqualStrings("{\"sender\":\"0xabc\"}", loaded.entries[0].request_json.?);
    try testing.expectEqualStrings("req-1", loaded.entries[0].correlation_id.?);
    try testing.expectEqual(@as(i64, 100), loaded.entries[0].created_at_ms);
    try testing.expectEqual(@as(i64, 200), loaded.entries[0].updated_at_ms);
    try testing.expectEqual(@as(u64, 1), loaded.entries[0].submit_count);
}

test "request_state returns empty entries when the file is missing" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const state_path = try std.fmt.allocPrint(allocator, "tmp_request_state_missing_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(state_path);
    defer std.fs.cwd().deleteFile(state_path) catch {};

    const old_override = test_request_state_path_override;
    test_request_state_path_override = state_path;
    defer test_request_state_path_override = old_override;

    var loaded = try loadDefaultRequestState(allocator);
    defer loaded.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), loaded.entries.len);
}
