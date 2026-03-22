/// client/rpc_client/selector.zig - Argument selection for Sui RPC Client
/// Compatible with legacy API format: select:{...} or sel:{...}
const std = @import("std");
const client_core = @import("client_core.zig");

const SuiRpcClient = client_core.SuiRpcClient;

/// Object input kind
pub const ObjectInputKind = enum {
    imm_or_owned,
    receiving,
    shared,
};

/// Object preset kind
pub const ObjectPresetKind = enum {
    clock,
    system,
    random,
    deny_list,
    bridge,
    deep_treasury,
};

/// Selected argument request (union of all selection types)
pub const SelectedArgumentRequest = union(enum) {
    object_preset: struct {
        preset: ObjectPresetKind,
    },
    object_input: struct {
        object_id: []const u8,
        input_kind: ObjectInputKind,
        mutable: bool = false,
        version: ?u64 = null,
        digest: ?[]const u8 = null,
        initial_shared_version: ?u64 = null,
    },
    gas_coin: struct {
        owner: []const u8,
        min_balance: u64,
    },
    coin_with_min_balance: struct {
        owner: []const u8,
        min_balance: u64,
    },
    owned_object: struct {
        owner: []const u8,
    },
    owned_object_struct_type: struct {
        owner: []const u8,
        struct_type: []const u8,
    },
    owned_object_object_id: struct {
        owner: []const u8,
        object_id: []const u8,
    },
    owned_object_module: struct {
        owner: []const u8,
        package: []const u8,
        module: []const u8,
    },

    pub fn deinit(self: *SelectedArgumentRequest, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .object_preset => {},
            .object_input => |*o| {
                allocator.free(o.object_id);
                if (o.digest) |d| allocator.free(d);
            },
            .gas_coin => |*g| allocator.free(g.owner),
            .coin_with_min_balance => |*c| allocator.free(c.owner),
            .owned_object => |*o| allocator.free(o.owner),
            .owned_object_struct_type => |*o| {
                allocator.free(o.owner);
                allocator.free(o.struct_type);
            },
            .owned_object_object_id => |*o| {
                allocator.free(o.owner);
                allocator.free(o.object_id);
            },
            .owned_object_module => |*o| {
                allocator.free(o.owner);
                allocator.free(o.package);
                allocator.free(o.module);
            },
        }
    }
};

/// Owned selected argument request (memory managed)
pub const OwnedSelectedArgumentRequest = struct {
    /// The request value
    value: SelectedArgumentRequest,

    pub fn deinit(self: *OwnedSelectedArgumentRequest, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
    }
};

/// Parse selected argument request token
/// Token format: "select:{...}" or "sel:{...}" where {...} is JSON
pub fn parseSelectedArgumentRequestToken(
    allocator: std.mem.Allocator,
    token: []const u8,
) !OwnedSelectedArgumentRequest {
    return try parseSelectedArgumentRequestTokenWithDefaultOwner(allocator, token, null);
}

/// Parse selected argument request token with default owner
pub fn parseSelectedArgumentRequestTokenWithDefaultOwner(
    allocator: std.mem.Allocator,
    token: []const u8,
    default_owner: ?[]const u8,
) !OwnedSelectedArgumentRequest {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    const json_text = if (std.mem.startsWith(u8, trimmed, "select:"))
        trimmed["select:".len..]
    else if (std.mem.startsWith(u8, trimmed, "sel:"))
        trimmed["sel:".len..]
    else
        return error.InvalidCli;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCli;

    const object = parsed.value.object;
    const kind = object.get("kind") orelse return error.InvalidCli;
    if (kind != .string) return error.InvalidCli;
    const kind_str = kind.string;

    // object_preset
    if (std.mem.eql(u8, kind_str, "object_preset") or
        std.mem.eql(u8, kind_str, "well_known_object") or
        std.mem.eql(u8, kind_str, "system_object"))
    {
        const preset_name = getStringField(object, "name") orelse
            getStringField(object, "preset") orelse
            return error.InvalidCli;
        return OwnedSelectedArgumentRequest{
            .value = .{
                .object_preset = .{
                    .preset = try parseObjectPresetKind(preset_name),
                },
            },
        };
    }

    // gas_coin
    if (std.mem.eql(u8, kind_str, "gas_coin")) {
        const owner = try resolveOwner(allocator, object, default_owner);
        const min_balance = getU64Field(object, "minBalance") orelse return error.InvalidCli;
        return OwnedSelectedArgumentRequest{
            .value = .{
                .gas_coin = .{
                    .owner = owner,
                    .min_balance = min_balance,
                },
            },
        };
    }

    // owned_object_struct_type
    if (std.mem.eql(u8, kind_str, "owned_object_struct_type")) {
        const owner = try resolveOwner(allocator, object, default_owner);
        const struct_type = getStringField(object, "structType") orelse return error.InvalidCli;
        return OwnedSelectedArgumentRequest{
            .value = .{
                .owned_object_struct_type = .{
                    .owner = owner,
                    .struct_type = try allocator.dupe(u8, struct_type),
                },
            },
        };
    }

    // owned_object_object_id
    if (std.mem.eql(u8, kind_str, "owned_object_object_id")) {
        const owner = try resolveOwner(allocator, object, default_owner);
        const object_id = getStringField(object, "objectId") orelse return error.InvalidCli;
        return OwnedSelectedArgumentRequest{
            .value = .{
                .owned_object_object_id = .{
                    .owner = owner,
                    .object_id = try allocator.dupe(u8, object_id),
                },
            },
        };
    }

    // owned_object_module
    if (std.mem.eql(u8, kind_str, "owned_object_module")) {
        const owner = try resolveOwner(allocator, object, default_owner);
        const package = getStringField(object, "package") orelse return error.InvalidCli;
        const module = getStringField(object, "module") orelse return error.InvalidCli;
        return OwnedSelectedArgumentRequest{
            .value = .{
                .owned_object_module = .{
                    .owner = owner,
                    .package = try allocator.dupe(u8, package),
                    .module = try allocator.dupe(u8, module),
                },
            },
        };
    }

    // owned_object
    if (std.mem.eql(u8, kind_str, "owned_object")) {
        const owner = try resolveOwner(allocator, object, default_owner);
        return OwnedSelectedArgumentRequest{
            .value = .{
                .owned_object = .{
                    .owner = owner,
                },
            },
        };
    }

    // coin_with_min_balance
    if (std.mem.eql(u8, kind_str, "coin_with_min_balance")) {
        const owner = try resolveOwner(allocator, object, default_owner);
        const min_balance = getU64Field(object, "minBalance") orelse return error.InvalidCli;
        return OwnedSelectedArgumentRequest{
            .value = .{
                .coin_with_min_balance = .{
                    .owner = owner,
                    .min_balance = min_balance,
                },
            },
        };
    }

    // object_input (simplified)
    if (std.mem.eql(u8, kind_str, "object_input") or std.mem.eql(u8, kind_str, "ptb_object")) {
        const object_id = getStringField(object, "objectId") orelse return error.InvalidCli;
        const input_kind = parseObjectInputKind(getStringField(object, "inputKind") orelse "imm_or_owned") catch .imm_or_owned;
        return OwnedSelectedArgumentRequest{
            .value = .{
                .object_input = .{
                    .object_id = try allocator.dupe(u8, object_id),
                    .input_kind = input_kind,
                },
            },
        };
    }

    return error.InvalidCli;
}

// Helper functions

fn getStringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn getU64Field(object: std.json.ObjectMap, key: []const u8) ?u64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| if (f >= 0) @intFromFloat(f) else null,
        .string => std.fmt.parseInt(u64, value.string, 10) catch null,
        else => null,
    };
}

fn resolveOwner(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    default_owner: ?[]const u8,
) ![]const u8 {
    if (getStringField(object, "owner")) |owner| {
        return try allocator.dupe(u8, owner);
    }
    if (default_owner) |owner| {
        return try allocator.dupe(u8, owner);
    }
    return error.InvalidCli;
}

fn parseObjectInputKind(kind_str: []const u8) !ObjectInputKind {
    if (std.mem.eql(u8, kind_str, "imm_or_owned")) return .imm_or_owned;
    if (std.mem.eql(u8, kind_str, "receiving")) return .receiving;
    if (std.mem.eql(u8, kind_str, "shared")) return .shared;
    return error.InvalidCli;
}

fn parseObjectPresetKind(preset_str: []const u8) !ObjectPresetKind {
    if (std.mem.eql(u8, preset_str, "clock")) return .clock;
    if (std.mem.eql(u8, preset_str, "system")) return .system;
    if (std.mem.eql(u8, preset_str, "random")) return .random;
    if (std.mem.eql(u8, preset_str, "deny_list")) return .deny_list;
    if (std.mem.eql(u8, preset_str, "bridge")) return .bridge;
    if (std.mem.eql(u8, preset_str, "deep_treasury")) return .deep_treasury;
    return error.InvalidCli;
}

/// Select argument value (placeholder)
pub fn selectArgumentValue(
    allocator: std.mem.Allocator,
    client: *SuiRpcClient,
    request: SelectedArgumentRequest,
) ![]const u8 {
    _ = allocator;
    _ = client;
    _ = request;
    return error.NotImplemented;
}

// ============================================================
// Tests
// ============================================================

test "parseSelectedArgumentRequestToken parses object_preset" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const token = "select:{\"kind\":\"object_preset\",\"preset\":\"clock\"}";
    var result = try parseSelectedArgumentRequestToken(allocator, token);
    defer result.deinit(allocator);

    try testing.expect(result.value == .object_preset);
    try testing.expectEqual(ObjectPresetKind.clock, result.value.object_preset.preset);
}

test "parseSelectedArgumentRequestToken parses gas_coin" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const token = "select:{\"kind\":\"gas_coin\",\"owner\":\"0x123\",\"minBalance\":1000}";
    var result = try parseSelectedArgumentRequestToken(allocator, token);
    defer result.deinit(allocator);

    try testing.expect(result.value == .gas_coin);
    try testing.expectEqualStrings("0x123", result.value.gas_coin.owner);
    try testing.expectEqual(@as(u64, 1000), result.value.gas_coin.min_balance);
}

test "parseSelectedArgumentRequestToken parses owned_object_struct_type" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const token = "select:{\"kind\":\"owned_object_struct_type\",\"owner\":\"0xowner\",\"structType\":\"0x2::example::Thing\"}";
    var result = try parseSelectedArgumentRequestToken(allocator, token);
    defer result.deinit(allocator);

    try testing.expect(result.value == .owned_object_struct_type);
    try testing.expectEqualStrings("0xowner", result.value.owned_object_struct_type.owner);
    try testing.expectEqualStrings("0x2::example::Thing", result.value.owned_object_struct_type.struct_type);
}

test "parseSelectedArgumentRequestToken parses sel: prefix" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const token = "sel:{\"kind\":\"object_preset\",\"preset\":\"system\"}";
    var result = try parseSelectedArgumentRequestToken(allocator, token);
    defer result.deinit(allocator);

    try testing.expect(result.value == .object_preset);
    try testing.expectEqual(ObjectPresetKind.system, result.value.object_preset.preset);
}

test "parseSelectedArgumentRequestToken rejects invalid format" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const token = "invalid:{\"kind\":\"object_preset\"}";
    const result = parseSelectedArgumentRequestToken(allocator, token);
    try testing.expectError(error.InvalidCli, result);
}

test "parseSelectedArgumentRequestTokenWithDefaultOwner uses default owner" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const token = "select:{\"kind\":\"gas_coin\",\"minBalance\":1000}";
    var result = try parseSelectedArgumentRequestTokenWithDefaultOwner(allocator, token, "0xdefault");
    defer result.deinit(allocator);

    try testing.expect(result.value == .gas_coin);
    try testing.expectEqualStrings("0xdefault", result.value.gas_coin.owner);
}

test "ObjectInputKind parsing" {
    const testing = std.testing;
    try testing.expectEqual(ObjectInputKind.imm_or_owned, try parseObjectInputKind("imm_or_owned"));
    try testing.expectEqual(ObjectInputKind.receiving, try parseObjectInputKind("receiving"));
    try testing.expectEqual(ObjectInputKind.shared, try parseObjectInputKind("shared"));
    try testing.expectError(error.InvalidCli, parseObjectInputKind("invalid"));
}

test "ObjectPresetKind parsing" {
    const testing = std.testing;
    try testing.expectEqual(ObjectPresetKind.clock, try parseObjectPresetKind("clock"));
    try testing.expectEqual(ObjectPresetKind.system, try parseObjectPresetKind("system"));
    try testing.expectEqual(ObjectPresetKind.random, try parseObjectPresetKind("random"));
    try testing.expectError(error.InvalidCli, parseObjectPresetKind("invalid"));
}
