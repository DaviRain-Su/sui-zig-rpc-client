const std = @import("std");

pub const default_wallet_session_registry_path = ".sui/sui_config/wallet_sessions.json";
pub var test_wallet_session_registry_path_override: ?[]const u8 = null;

pub const OwnedWalletSessionEntry = struct {
    selector: []u8,
    label: ?[]u8 = null,
    wallet_selector: ?[]u8 = null,
    address: ?[]u8 = null,
    session_id: []u8,
    session_kind: ?[]u8 = null,
    state: []u8,
    policy_json: ?[]u8 = null,
    created_at_ms: i64,
    updated_at_ms: i64,
    expires_at_ms: ?i64 = null,

    pub fn deinit(self: *OwnedWalletSessionEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.selector);
        if (self.label) |value| allocator.free(value);
        if (self.wallet_selector) |value| allocator.free(value);
        if (self.address) |value| allocator.free(value);
        allocator.free(self.session_id);
        if (self.session_kind) |value| allocator.free(value);
        allocator.free(self.state);
        if (self.policy_json) |value| allocator.free(value);
    }
};

pub const OwnedWalletSessionRegistry = struct {
    entries: []OwnedWalletSessionEntry = &.{},

    pub fn deinit(self: *OwnedWalletSessionRegistry, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
    }
};

fn emptyWalletSessionRegistry(allocator: std.mem.Allocator) !OwnedWalletSessionRegistry {
    return .{
        .entries = try allocator.alloc(OwnedWalletSessionEntry, 0),
    };
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

fn defaultWalletSessionRegistryPath(allocator: std.mem.Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_wallet_session_registry_path });
}

pub fn resolveDefaultWalletSessionRegistryPath(allocator: std.mem.Allocator) !?[]const u8 {
    if (test_wallet_session_registry_path_override) |override_path| {
        if (override_path.len == 0) return null;
        return try allocator.dupe(u8, override_path);
    }

    const env_or_default_path = std.process.getEnvVarOwned(allocator, "SUI_WALLET_SESSIONS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try defaultWalletSessionRegistryPath(allocator),
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

fn jsonOptionalStringDup(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    field: []const u8,
) !?[]u8 {
    const value = object.get(field) orelse return null;
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        else => return error.InvalidCli,
    };
}

fn jsonRequiredStringDup(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    field: []const u8,
) ![]u8 {
    const value = object.get(field) orelse return error.InvalidCli;
    return switch (value) {
        .string => |text| if (text.len == 0) error.InvalidCli else try allocator.dupe(u8, text),
        else => error.InvalidCli,
    };
}

fn jsonRequiredI64(
    object: std.json.ObjectMap,
    field: []const u8,
) !i64 {
    const value = object.get(field) orelse return error.InvalidCli;
    return switch (value) {
        .integer => |number| number,
        else => error.InvalidCli,
    };
}

fn jsonOptionalI64(
    object: std.json.ObjectMap,
    field: []const u8,
) !?i64 {
    const value = object.get(field) orelse return null;
    return switch (value) {
        .null => null,
        .integer => |number| number,
        else => error.InvalidCli,
    };
}

fn jsonOptionalCompactValue(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    field: []const u8,
) !?[]u8 {
    const value = object.get(field) orelse return null;
    return switch (value) {
        .null => null,
        else => try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})}),
    };
}

pub fn sessionSelectorForId(
    allocator: std.mem.Allocator,
    id: []const u8,
) ![]u8 {
    return try std.fmt.allocPrint(allocator, "session:{s}", .{id});
}

pub fn loadDefaultWalletSessionRegistry(allocator: std.mem.Allocator) !OwnedWalletSessionRegistry {
    const registry_path = try resolveDefaultWalletSessionRegistryPath(allocator) orelse return try emptyWalletSessionRegistry(allocator);
    defer allocator.free(registry_path);

    const contents = readFileAtPathAlloc(allocator, registry_path, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return try emptyWalletSessionRegistry(allocator),
        else => return err,
    };
    defer allocator.free(contents);

    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return try emptyWalletSessionRegistry(allocator);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return error.InvalidCli;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCli;

    const entries_value = parsed.value.object.get("entries");
    if (entries_value != null and entries_value.? != .array) return error.InvalidCli;
    const entries_len = if (entries_value) |value| value.array.items.len else 0;

    const entries = try allocator.alloc(OwnedWalletSessionEntry, entries_len);
    var initialized: usize = 0;
    errdefer {
        for (entries[0..initialized]) |*entry| entry.deinit(allocator);
        allocator.free(entries);
    }

    if (entries_value) |value| {
        for (value.array.items, 0..) |entry, index| {
            if (entry != .object) return error.InvalidCli;
            entries[index] = .{
                .selector = try jsonRequiredStringDup(allocator, entry.object, "selector"),
                .label = try jsonOptionalStringDup(allocator, entry.object, "label"),
                .wallet_selector = try jsonOptionalStringDup(allocator, entry.object, "wallet_selector"),
                .address = try jsonOptionalStringDup(allocator, entry.object, "address"),
                .session_id = try jsonRequiredStringDup(allocator, entry.object, "session_id"),
                .session_kind = try jsonOptionalStringDup(allocator, entry.object, "session_kind"),
                .state = try jsonRequiredStringDup(allocator, entry.object, "state"),
                .policy_json = try jsonOptionalCompactValue(allocator, entry.object, "policy"),
                .created_at_ms = try jsonRequiredI64(entry.object, "created_at_ms"),
                .updated_at_ms = try jsonRequiredI64(entry.object, "updated_at_ms"),
                .expires_at_ms = try jsonOptionalI64(entry.object, "expires_at_ms"),
            };
            initialized += 1;
        }
    }

    return .{ .entries = entries };
}

pub fn writeDefaultWalletSessionRegistry(
    allocator: std.mem.Allocator,
    registry: *const OwnedWalletSessionRegistry,
) !void {
    const registry_path = try resolveDefaultWalletSessionRegistryPath(allocator) orelse return error.InvalidCli;
    defer allocator.free(registry_path);

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);

    try writer.writeAll("{\"entries\":[");
    for (registry.entries, 0..) |entry, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{\"selector\":");
        try writer.print("{f}", .{std.json.fmt(entry.selector, .{})});
        try writer.writeAll(",\"label\":");
        if (entry.label) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"wallet_selector\":");
        if (entry.wallet_selector) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"address\":");
        if (entry.address) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"session_id\":");
        try writer.print("{f}", .{std.json.fmt(entry.session_id, .{})});
        try writer.writeAll(",\"session_kind\":");
        if (entry.session_kind) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"state\":");
        try writer.print("{f}", .{std.json.fmt(entry.state, .{})});
        try writer.writeAll(",\"policy\":");
        if (entry.policy_json) |value| {
            try writer.writeAll(value);
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"created_at_ms\":{d}", .{entry.created_at_ms});
        try writer.print(",\"updated_at_ms\":{d}", .{entry.updated_at_ms});
        try writer.writeAll(",\"expires_at_ms\":");
        if (entry.expires_at_ms) |value| {
            try writer.print("{d}", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("}");
    }
    try writer.writeAll("]}");

    try writeFileAtPath(registry_path, output.items);
}

test "wallet_session_registry writes and reloads session entries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const registry_path = try std.fmt.allocPrint(allocator, "tmp_wallet_sessions_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(registry_path);
    defer std.fs.cwd().deleteFile(registry_path) catch {};

    const old_override = test_wallet_session_registry_path_override;
    test_wallet_session_registry_path_override = registry_path;
    defer test_wallet_session_registry_path_override = old_override;

    const entries = try allocator.alloc(OwnedWalletSessionEntry, 1);
    entries[0] = .{
        .selector = try allocator.dupe(u8, "session:swap"),
        .label = try allocator.dupe(u8, "swap"),
        .wallet_selector = try allocator.dupe(u8, "passkey:iphone"),
        .address = try allocator.dupe(u8, "0x111"),
        .session_id = try allocator.dupe(u8, "session-1"),
        .session_kind = try allocator.dupe(u8, "passkey"),
        .state = try allocator.dupe(u8, "active"),
        .policy_json = try allocator.dupe(u8, "{\"recipient_allowlist\":[\"0x222\"]}"),
        .created_at_ms = 100,
        .updated_at_ms = 101,
        .expires_at_ms = 200,
    };
    var registry = OwnedWalletSessionRegistry{
        .entries = entries,
    };
    defer registry.deinit(allocator);

    try writeDefaultWalletSessionRegistry(allocator, &registry);

    var loaded = try loadDefaultWalletSessionRegistry(allocator);
    defer loaded.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), loaded.entries.len);
    try testing.expectEqualStrings("session:swap", loaded.entries[0].selector);
    try testing.expectEqualStrings("swap", loaded.entries[0].label.?);
    try testing.expectEqualStrings("passkey:iphone", loaded.entries[0].wallet_selector.?);
    try testing.expectEqualStrings("0x111", loaded.entries[0].address.?);
    try testing.expectEqualStrings("session-1", loaded.entries[0].session_id);
    try testing.expectEqualStrings("passkey", loaded.entries[0].session_kind.?);
    try testing.expectEqualStrings("active", loaded.entries[0].state);
    try testing.expectEqualStrings("{\"recipient_allowlist\":[\"0x222\"]}", loaded.entries[0].policy_json.?);
    try testing.expectEqual(@as(i64, 200), loaded.entries[0].expires_at_ms.?);
}

test "wallet_session_registry returns empty entries when file is missing" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const registry_path = try std.fmt.allocPrint(allocator, "tmp_wallet_sessions_missing_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(registry_path);
    defer std.fs.cwd().deleteFile(registry_path) catch {};

    const old_override = test_wallet_session_registry_path_override;
    test_wallet_session_registry_path_override = registry_path;
    defer test_wallet_session_registry_path_override = old_override;

    var loaded = try loadDefaultWalletSessionRegistry(allocator);
    defer loaded.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), loaded.entries.len);
}
