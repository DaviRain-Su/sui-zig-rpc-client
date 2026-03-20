const std = @import("std");

pub const default_wallet_state_path = ".sui/sui_config/wallet_state.json";
pub var test_wallet_state_path_override: ?[]const u8 = null;

pub const OwnedWalletState = struct {
    active_selector: ?[]u8 = null,

    pub fn deinit(self: *OwnedWalletState, allocator: std.mem.Allocator) void {
        if (self.active_selector) |value| allocator.free(value);
    }
};

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

fn defaultWalletStatePath(allocator: std.mem.Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_wallet_state_path });
}

pub fn resolveDefaultWalletStatePath(allocator: std.mem.Allocator) !?[]const u8 {
    if (test_wallet_state_path_override) |override_path| {
        if (override_path.len == 0) return null;
        return try allocator.dupe(u8, override_path);
    }

    const env_or_default_path = std.process.getEnvVarOwned(allocator, "SUI_WALLET_STATE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try defaultWalletStatePath(allocator),
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

pub fn loadDefaultWalletState(allocator: std.mem.Allocator) !OwnedWalletState {
    const state_path = try resolveDefaultWalletStatePath(allocator) orelse return .{};
    defer allocator.free(state_path);

    const contents = readFileAtPathAlloc(allocator, state_path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(contents);

    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return .{};

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return error.InvalidCli;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCli;

    if (parsed.value.object.get("activeSelector")) |value| {
        if (value == .string and value.string.len > 0) {
            return .{ .active_selector = try allocator.dupe(u8, value.string) };
        }
        if (value != .null) return error.InvalidCli;
    }

    return .{};
}

pub fn resolveActiveSelector(allocator: std.mem.Allocator) !?[]u8 {
    var state = try loadDefaultWalletState(allocator);
    errdefer state.deinit(allocator);
    return state.active_selector;
}

pub fn writeDefaultWalletState(
    allocator: std.mem.Allocator,
    active_selector: ?[]const u8,
) !void {
    const state_path = try resolveDefaultWalletStatePath(allocator) orelse return error.InvalidCli;
    defer allocator.free(state_path);

    var encoded = std.ArrayList(u8){};
    defer encoded.deinit(allocator);
    try encoded.writer(allocator).print(
        "{f}",
        .{std.json.fmt(.{ .activeSelector = active_selector }, .{})},
    );
    try writeFileAtPath(state_path, encoded.items);
}

test "wallet_state writes and reloads the active selector" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const state_path = try std.fmt.allocPrint(allocator, "tmp_wallet_state_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(state_path);
    defer std.fs.cwd().deleteFile(state_path) catch {};

    const old_override = test_wallet_state_path_override;
    test_wallet_state_path_override = state_path;
    defer test_wallet_state_path_override = old_override;

    try writeDefaultWalletState(allocator, "main");

    const selector = try resolveActiveSelector(allocator);
    try testing.expect(selector != null);
    defer allocator.free(selector.?);
    try testing.expectEqualStrings("main", selector.?);
}

test "wallet_state returns null when the file is missing" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const state_path = try std.fmt.allocPrint(allocator, "tmp_wallet_state_missing_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(state_path);
    defer std.fs.cwd().deleteFile(state_path) catch {};

    const old_override = test_wallet_state_path_override;
    test_wallet_state_path_override = state_path;
    defer test_wallet_state_path_override = old_override;

    const selector = try resolveActiveSelector(allocator);
    try testing.expect(selector == null);
}
