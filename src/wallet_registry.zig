const std = @import("std");

pub const default_wallet_registry_path = ".sui/sui_config/wallet_registry.json";
pub var test_wallet_registry_path_override: ?[]const u8 = null;

pub const OwnedExternalWalletEntry = struct {
    selector: []u8,
    label: ?[]u8 = null,
    address: []u8,
    network: ?[]u8 = null,
    capabilities_json: ?[]u8 = null,
    state: []u8,
    connected_at_ms: i64,
    updated_at_ms: i64,

    pub fn deinit(self: *OwnedExternalWalletEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.selector);
        if (self.label) |value| allocator.free(value);
        allocator.free(self.address);
        if (self.network) |value| allocator.free(value);
        if (self.capabilities_json) |value| allocator.free(value);
        allocator.free(self.state);
    }
};

pub const OwnedPasskeyCredentialEntry = struct {
    selector: []u8,
    label: ?[]u8 = null,
    address: []u8,
    credential_id: []u8,
    public_key: []u8,
    network: ?[]u8 = null,
    rp_id: ?[]u8 = null,
    device_name: ?[]u8 = null,
    user_name: ?[]u8 = null,
    state: []u8,
    registered_at_ms: i64,
    updated_at_ms: i64,

    pub fn deinit(self: *OwnedPasskeyCredentialEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.selector);
        if (self.label) |value| allocator.free(value);
        allocator.free(self.address);
        allocator.free(self.credential_id);
        allocator.free(self.public_key);
        if (self.network) |value| allocator.free(value);
        if (self.rp_id) |value| allocator.free(value);
        if (self.device_name) |value| allocator.free(value);
        if (self.user_name) |value| allocator.free(value);
        allocator.free(self.state);
    }
};

pub const OwnedWalletRegistry = struct {
    external_wallets: []OwnedExternalWalletEntry = &.{},
    passkey_credentials: []OwnedPasskeyCredentialEntry = &.{},

    pub fn deinit(self: *OwnedWalletRegistry, allocator: std.mem.Allocator) void {
        for (self.external_wallets) |*entry| entry.deinit(allocator);
        allocator.free(self.external_wallets);
        for (self.passkey_credentials) |*entry| entry.deinit(allocator);
        allocator.free(self.passkey_credentials);
    }
};

fn emptyWalletRegistry(allocator: std.mem.Allocator) !OwnedWalletRegistry {
    return .{
        .external_wallets = try allocator.alloc(OwnedExternalWalletEntry, 0),
        .passkey_credentials = try allocator.alloc(OwnedPasskeyCredentialEntry, 0),
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

fn defaultWalletRegistryPath(allocator: std.mem.Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_wallet_registry_path });
}

pub fn resolveDefaultWalletRegistryPath(allocator: std.mem.Allocator) !?[]const u8 {
    if (test_wallet_registry_path_override) |override_path| {
        if (override_path.len == 0) return null;
        return try allocator.dupe(u8, override_path);
    }

    const env_or_default_path = std.process.getEnvVarOwned(allocator, "SUI_WALLET_REGISTRY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try defaultWalletRegistryPath(allocator),
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

pub fn externalSelectorForId(
    allocator: std.mem.Allocator,
    id: []const u8,
) ![]u8 {
    return try std.fmt.allocPrint(allocator, "external:{s}", .{id});
}

pub fn passkeySelectorForId(
    allocator: std.mem.Allocator,
    id: []const u8,
) ![]u8 {
    return try std.fmt.allocPrint(allocator, "passkey:{s}", .{id});
}

pub fn loadDefaultWalletRegistry(allocator: std.mem.Allocator) !OwnedWalletRegistry {
    const registry_path = try resolveDefaultWalletRegistryPath(allocator) orelse return try emptyWalletRegistry(allocator);
    defer allocator.free(registry_path);

    const contents = readFileAtPathAlloc(allocator, registry_path, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return try emptyWalletRegistry(allocator),
        else => return err,
    };
    defer allocator.free(contents);

    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return try emptyWalletRegistry(allocator);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return error.InvalidCli;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCli;

    const external_value = parsed.value.object.get("external_wallets");
    if (external_value != null and external_value.? != .array) return error.InvalidCli;
    const passkey_value = parsed.value.object.get("passkey_credentials");
    if (passkey_value != null and passkey_value.? != .array) return error.InvalidCli;

    const external_len = if (external_value) |value| value.array.items.len else 0;
    const passkey_len = if (passkey_value) |value| value.array.items.len else 0;

    const external_entries = try allocator.alloc(OwnedExternalWalletEntry, external_len);
    errdefer allocator.free(external_entries);
    if (external_value) |value| {
        for (value.array.items, 0..) |entry, index| {
            if (entry != .object) return error.InvalidCli;
            external_entries[index] = .{
                .selector = try jsonRequiredStringDup(allocator, entry.object, "selector"),
                .label = try jsonOptionalStringDup(allocator, entry.object, "label"),
                .address = try jsonRequiredStringDup(allocator, entry.object, "address"),
                .network = try jsonOptionalStringDup(allocator, entry.object, "network"),
                .capabilities_json = try jsonOptionalCompactValue(allocator, entry.object, "capabilities"),
                .state = try jsonRequiredStringDup(allocator, entry.object, "state"),
                .connected_at_ms = try jsonRequiredI64(entry.object, "connected_at_ms"),
                .updated_at_ms = try jsonRequiredI64(entry.object, "updated_at_ms"),
            };
        }
    }

    const passkey_entries = try allocator.alloc(OwnedPasskeyCredentialEntry, passkey_len);
    errdefer allocator.free(passkey_entries);
    if (passkey_value) |value| {
        for (value.array.items, 0..) |entry, index| {
            if (entry != .object) return error.InvalidCli;
            passkey_entries[index] = .{
                .selector = try jsonRequiredStringDup(allocator, entry.object, "selector"),
                .label = try jsonOptionalStringDup(allocator, entry.object, "label"),
                .address = try jsonRequiredStringDup(allocator, entry.object, "address"),
                .credential_id = try jsonRequiredStringDup(allocator, entry.object, "credential_id"),
                .public_key = try jsonRequiredStringDup(allocator, entry.object, "public_key"),
                .network = try jsonOptionalStringDup(allocator, entry.object, "network"),
                .rp_id = try jsonOptionalStringDup(allocator, entry.object, "rp_id"),
                .device_name = try jsonOptionalStringDup(allocator, entry.object, "device_name"),
                .user_name = try jsonOptionalStringDup(allocator, entry.object, "user_name"),
                .state = try jsonRequiredStringDup(allocator, entry.object, "state"),
                .registered_at_ms = try jsonRequiredI64(entry.object, "registered_at_ms"),
                .updated_at_ms = try jsonRequiredI64(entry.object, "updated_at_ms"),
            };
        }
    }

    return .{
        .external_wallets = external_entries,
        .passkey_credentials = passkey_entries,
    };
}

pub fn writeDefaultWalletRegistry(
    allocator: std.mem.Allocator,
    registry: *const OwnedWalletRegistry,
) !void {
    const registry_path = try resolveDefaultWalletRegistryPath(allocator) orelse return error.InvalidCli;
    defer allocator.free(registry_path);

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);

    try writer.writeAll("{\"external_wallets\":[");
    for (registry.external_wallets, 0..) |entry, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{\"selector\":");
        try writer.print("{f}", .{std.json.fmt(entry.selector, .{})});
        try writer.writeAll(",\"label\":");
        if (entry.label) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"address\":");
        try writer.print("{f}", .{std.json.fmt(entry.address, .{})});
        try writer.writeAll(",\"network\":");
        if (entry.network) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"capabilities\":");
        if (entry.capabilities_json) |value| {
            try writer.writeAll(value);
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"state\":");
        try writer.print("{f}", .{std.json.fmt(entry.state, .{})});
        try writer.print(",\"connected_at_ms\":{d}", .{entry.connected_at_ms});
        try writer.print(",\"updated_at_ms\":{d}", .{entry.updated_at_ms});
        try writer.writeAll("}");
    }
    try writer.writeAll("],\"passkey_credentials\":[");
    for (registry.passkey_credentials, 0..) |entry, index| {
        if (index != 0) try writer.writeAll(",");
        try writer.writeAll("{\"selector\":");
        try writer.print("{f}", .{std.json.fmt(entry.selector, .{})});
        try writer.writeAll(",\"label\":");
        if (entry.label) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"address\":");
        try writer.print("{f}", .{std.json.fmt(entry.address, .{})});
        try writer.writeAll(",\"credential_id\":");
        try writer.print("{f}", .{std.json.fmt(entry.credential_id, .{})});
        try writer.writeAll(",\"public_key\":");
        try writer.print("{f}", .{std.json.fmt(entry.public_key, .{})});
        try writer.writeAll(",\"network\":");
        if (entry.network) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"rp_id\":");
        if (entry.rp_id) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"device_name\":");
        if (entry.device_name) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"user_name\":");
        if (entry.user_name) |value| {
            try writer.print("{f}", .{std.json.fmt(value, .{})});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"state\":");
        try writer.print("{f}", .{std.json.fmt(entry.state, .{})});
        try writer.print(",\"registered_at_ms\":{d}", .{entry.registered_at_ms});
        try writer.print(",\"updated_at_ms\":{d}", .{entry.updated_at_ms});
        try writer.writeAll("}");
    }
    try writer.writeAll("]}");

    try writeFileAtPath(registry_path, output.items);
}

test "wallet_registry writes and reloads external and passkey entries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const registry_path = try std.fmt.allocPrint(allocator, "tmp_wallet_registry_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(registry_path);
    defer std.fs.cwd().deleteFile(registry_path) catch {};

    const old_override = test_wallet_registry_path_override;
    test_wallet_registry_path_override = registry_path;
    defer test_wallet_registry_path_override = old_override;

    const external_entries = try allocator.alloc(OwnedExternalWalletEntry, 1);
    external_entries[0] = .{
        .selector = try allocator.dupe(u8, "external:browser"),
        .label = try allocator.dupe(u8, "browser"),
        .address = try allocator.dupe(u8, "0x111"),
        .network = try allocator.dupe(u8, "sui:mainnet"),
        .capabilities_json = try allocator.dupe(u8, "{\"sponsor\":true}"),
        .state = try allocator.dupe(u8, "connected"),
        .connected_at_ms = 100,
        .updated_at_ms = 101,
    };
    const passkey_entries = try allocator.alloc(OwnedPasskeyCredentialEntry, 1);
    passkey_entries[0] = .{
        .selector = try allocator.dupe(u8, "passkey:iphone"),
        .label = try allocator.dupe(u8, "iphone"),
        .address = try allocator.dupe(u8, "0x222"),
        .credential_id = try allocator.dupe(u8, "cred-1"),
        .public_key = try allocator.dupe(u8, "pub-1"),
        .network = try allocator.dupe(u8, "sui:mainnet"),
        .rp_id = try allocator.dupe(u8, "wallet.example"),
        .device_name = try allocator.dupe(u8, "iPhone"),
        .user_name = try allocator.dupe(u8, "alice"),
        .state = try allocator.dupe(u8, "active"),
        .registered_at_ms = 200,
        .updated_at_ms = 201,
    };
    var registry = OwnedWalletRegistry{
        .external_wallets = external_entries,
        .passkey_credentials = passkey_entries,
    };
    defer registry.deinit(allocator);

    try writeDefaultWalletRegistry(allocator, &registry);

    var loaded = try loadDefaultWalletRegistry(allocator);
    defer loaded.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), loaded.external_wallets.len);
    try testing.expectEqual(@as(usize, 1), loaded.passkey_credentials.len);
    try testing.expectEqualStrings("external:browser", loaded.external_wallets[0].selector);
    try testing.expectEqualStrings("{\"sponsor\":true}", loaded.external_wallets[0].capabilities_json.?);
    try testing.expectEqualStrings("passkey:iphone", loaded.passkey_credentials[0].selector);
    try testing.expectEqualStrings("sui:mainnet", loaded.passkey_credentials[0].network.?);
    try testing.expectEqualStrings("wallet.example", loaded.passkey_credentials[0].rp_id.?);
}

test "wallet_registry returns empty registry when the file is missing" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const registry_path = try std.fmt.allocPrint(allocator, "tmp_wallet_registry_missing_{d}.json", .{std.time.milliTimestamp()});
    defer allocator.free(registry_path);
    defer std.fs.cwd().deleteFile(registry_path) catch {};

    const old_override = test_wallet_registry_path_override;
    test_wallet_registry_path_override = registry_path;
    defer test_wallet_registry_path_override = old_override;

    var loaded = try loadDefaultWalletRegistry(allocator);
    defer loaded.deinit(allocator);
    try testing.expectEqual(@as(usize, 0), loaded.external_wallets.len);
    try testing.expectEqual(@as(usize, 0), loaded.passkey_credentials.len);
}
