/// client/rpc_client/object_input.zig - Object input handling for Sui RPC Client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Object input kind
pub const ObjectInputKind = enum {
    /// Immutable or owned object
    imm_or_owned,
    /// Shared object
    shared,
    /// Receiving object
    receiving,
};

/// Immortal or owned object input
pub const ImmOrOwnedObjectInput = struct {
    /// Object ID
    object_id: []const u8,
    /// Object version
    version: u64,
    /// Object digest
    digest: []const u8,

    pub fn deinit(self: *ImmOrOwnedObjectInput, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        allocator.free(self.digest);
    }

    /// Build JSON representation
    pub fn buildJson(self: ImmOrOwnedObjectInput, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            "{{\"objectId\":\"{s}\",\"version\":{d},\"digest\":\"{s}\"}}",
            .{ self.object_id, self.version, self.digest },
        );
    }
};

/// Shared object input
pub const SharedObjectInput = struct {
    /// Object ID
    object_id: []const u8,
    /// Initial shared version
    initial_shared_version: u64,
    /// Whether mutable
    mutable: bool,

    pub fn deinit(self: *SharedObjectInput, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
    }

    /// Build JSON representation
    pub fn buildJson(self: SharedObjectInput, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            "{{\"objectId\":\"{s}\",\"initialSharedVersion\":{d},\"mutable\":{}}}",
            .{ self.object_id, self.initial_shared_version, self.mutable },
        );
    }
};

/// Receiving object input
pub const ReceivingObjectInput = struct {
    /// Object ID
    object_id: []const u8,
    /// Object version
    version: u64,
    /// Object digest
    digest: []const u8,

    pub fn deinit(self: *ReceivingObjectInput, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        allocator.free(self.digest);
    }

    /// Build JSON representation
    pub fn buildJson(self: ReceivingObjectInput, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            "{{\"objectId\":\"{s}\",\"version\":{d},\"digest\":\"{s}\"}}",
            .{ self.object_id, self.version, self.digest },
        );
    }
};

/// Object input union
pub const ObjectInput = union(ObjectInputKind) {
    imm_or_owned: ImmOrOwnedObjectInput,
    shared: SharedObjectInput,
    receiving: ReceivingObjectInput,

    pub fn deinit(self: *ObjectInput, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .imm_or_owned => |*io| io.deinit(allocator),
            .shared => |*s| s.deinit(allocator),
            .receiving => |*r| r.deinit(allocator),
        }
    }

    /// Build JSON representation
    pub fn buildJson(self: ObjectInput, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .imm_or_owned => |io| io.buildJson(allocator),
            .shared => |s| s.buildJson(allocator),
            .receiving => |r| r.buildJson(allocator),
        };
    }
};

/// Resolve immortal or owned object input
pub fn resolveImmOrOwnedObjectInputJson(
    client: *SuiRpcClient,
    object_id: []const u8,
) ![]const u8 {
    // Query object to get version and digest
    const params = try std.fmt.allocPrint(
        client.allocator,
        "[\"{s}\"]",
        .{object_id},
    );
    defer client.allocator.free(params);

    const response = try client.call("sui_getObject", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    const result = parsed.value.object.get("result") orelse
        return ClientError.InvalidResponse;
    const data = result.object.get("data") orelse
        return ClientError.InvalidResponse;

    const version_val = data.object.get("version") orelse
        return ClientError.InvalidResponse;
    const version: u64 = if (version_val == .integer)
        @intCast(version_val.integer)
    else
        try std.fmt.parseInt(u64, version_val.string, 10);

    const digest = data.object.get("digest") orelse
        return ClientError.InvalidResponse;

    const input = ImmOrOwnedObjectInput{
        .object_id = try client.allocator.dupe(u8, object_id),
        .version = version,
        .digest = try client.allocator.dupe(u8, digest.string),
    };
    defer input.deinit(client.allocator);

    return try input.buildJson(client.allocator);
}

/// Build immortal or owned object input JSON directly
pub fn buildImmOrOwnedObjectInputJson(
    allocator: std.mem.Allocator,
    object_id: []const u8,
    version: u64,
    digest: []const u8,
) ![]const u8 {
    const input = ImmOrOwnedObjectInput{
        .object_id = try allocator.dupe(u8, object_id),
        .version = version,
        .digest = try allocator.dupe(u8, digest),
    };
    defer input.deinit(allocator);

    return try input.buildJson(allocator);
}

/// Resolve receiving object input
pub fn resolveReceivingObjectInputJson(
    client: *SuiRpcClient,
    object_id: []const u8,
) ![]const u8 {
    // Same as imm_or_owned for resolution
    return try resolveImmOrOwnedObjectInputJson(client, object_id);
}

/// Build receiving object input JSON directly
pub fn buildReceivingObjectInputJson(
    allocator: std.mem.Allocator,
    object_id: []const u8,
    version: u64,
    digest: []const u8,
) ![]const u8 {
    const input = ReceivingObjectInput{
        .object_id = try allocator.dupe(u8, object_id),
        .version = version,
        .digest = try allocator.dupe(u8, digest),
    };
    defer input.deinit(allocator);

    return try input.buildJson(allocator);
}

/// Resolve shared object input
pub fn resolveSharedObjectInputJson(
    client: *SuiRpcClient,
    object_id: []const u8,
    mutable: bool,
) ![]const u8 {
    // Query object to get initial shared version
    const params = try std.fmt.allocPrint(
        client.allocator,
        "[\"{s}\"]",
        .{object_id},
    );
    defer client.allocator.free(params);

    const response = try client.call("sui_getObject", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    const result = parsed.value.object.get("result") orelse
        return ClientError.InvalidResponse;

    // For shared objects, we need the owner information
    const owner = result.object.get("owner") orelse
        return ClientError.InvalidResponse;

    const shared = owner.object.get("Shared") orelse
        return ClientError.InvalidResponse;

    const initial_version = shared.object.get("initial_shared_version") orelse
        return ClientError.InvalidResponse;

    const initial_shared_version: u64 = if (initial_version == .integer)
        @intCast(initial_version.integer)
    else
        try std.fmt.parseInt(u64, initial_version.string, 10);

    const input = SharedObjectInput{
        .object_id = try client.allocator.dupe(u8, object_id),
        .initial_shared_version = initial_shared_version,
        .mutable = mutable,
    };
    defer input.deinit(client.allocator);

    return try input.buildJson(client.allocator);
}

/// Build shared object input JSON directly
pub fn buildSharedObjectInputJson(
    allocator: std.mem.Allocator,
    object_id: []const u8,
    initial_shared_version: u64,
    mutable: bool,
) ![]const u8 {
    const input = SharedObjectInput{
        .object_id = try allocator.dupe(u8, object_id),
        .initial_shared_version = initial_shared_version,
        .mutable = mutable,
    };
    defer input.deinit(allocator);

    return try input.buildJson(allocator);
}

/// Gas data for transaction
pub const GasData = struct {
    /// Payment objects
    payment: []const ImmOrOwnedObjectInput,
    /// Owner address
    owner: []const u8,
    /// Gas price
    price: u64,
    /// Gas budget
    budget: u64,

    pub fn deinit(self: *GasData, allocator: std.mem.Allocator) void {
        for (self.payment) |*p| p.deinit(allocator);
        allocator.free(self.payment);
        allocator.free(self.owner);
    }

    /// Build JSON representation
    pub fn buildJson(self: GasData, allocator: std.mem.Allocator) ![]const u8 {
        var payment_json = std.ArrayList(u8).init(allocator);
        defer payment_json.deinit();

        try payment_json.append('[');
        for (self.payment, 0..) |p, i| {
            if (i > 0) try payment_json.append(',');
            const p_json = try p.buildJson(allocator);
            defer allocator.free(p_json);
            try payment_json.appendSlice(p_json);
        }
        try payment_json.append(']');

        return try std.fmt.allocPrint(
            allocator,
            "{{\"payment\":{s},\"owner\":\"{s}\",\"price\":{d},\"budget\":{d}}}",
            .{ payment_json.items, self.owner, self.price, self.budget },
        );
    }
};

/// Build gas data JSON
pub fn buildGasDataJson(
    allocator: std.mem.Allocator,
    payment: []const ImmOrOwnedObjectInput,
    owner: []const u8,
    price: u64,
    budget: u64,
) ![]const u8 {
    const gas_data = GasData{
        .payment = payment,
        .owner = try allocator.dupe(u8, owner),
        .price = price,
        .budget = budget,
    };
    defer gas_data.deinit(allocator);

    return try gas_data.buildJson(allocator);
}

/// Build gas data JSON with auto-resolved payment
pub fn buildGasDataJsonWithAutoPayment(
    client: *SuiRpcClient,
    owner: []const u8,
    price: u64,
    budget: u64,
) ![]const u8 {
    // Simplified - would actually query for gas coins
    const payment = try client.allocator.alloc(ImmOrOwnedObjectInput, 0);
    defer client.allocator.free(payment);

    return try buildGasDataJson(client.allocator, payment, owner, price, budget);
}

// ============================================================
// Tests
// ============================================================

test "ImmOrOwnedObjectInput lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var input = ImmOrOwnedObjectInput{
        .object_id = try allocator.dupe(u8, "0x123"),
        .version = 5,
        .digest = try allocator.dupe(u8, "abc123"),
    };
    defer input.deinit(allocator);

    try testing.expectEqualStrings("0x123", input.object_id);
    try testing.expectEqual(@as(u64, 5), input.version);
}

test "ImmOrOwnedObjectInput buildJson" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const input = ImmOrOwnedObjectInput{
        .object_id = "0x123",
        .version = 5,
        .digest = "abc",
    };

    const json = try input.buildJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "0x123"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "abc"));
}

test "SharedObjectInput lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var input = SharedObjectInput{
        .object_id = try allocator.dupe(u8, "0xshared"),
        .initial_shared_version = 1,
        .mutable = true,
    };
    defer input.deinit(allocator);

    try testing.expect(input.mutable);
}

test "SharedObjectInput buildJson" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const input = SharedObjectInput{
        .object_id = "0xshared",
        .initial_shared_version = 1,
        .mutable = true,
    };

    const json = try input.buildJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "initialSharedVersion"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "true"));
}

test "ReceivingObjectInput lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var input = ReceivingObjectInput{
        .object_id = try allocator.dupe(u8, "0xrecv"),
        .version = 10,
        .digest = try allocator.dupe(u8, "digest"),
    };
    defer input.deinit(allocator);

    try testing.expectEqual(@as(u64, 10), input.version);
}

test "ObjectInput union" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var input = ObjectInput{
        .imm_or_owned = .{
            .object_id = try allocator.dupe(u8, "0xobj"),
            .version = 1,
            .digest = try allocator.dupe(u8, "dig"),
        },
    };
    defer input.deinit(allocator);

    try testing.expect(input == .imm_or_owned);
}

test "ObjectInput buildJson" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const input = ObjectInput{
        .shared = .{
            .object_id = "0xshared",
            .initial_shared_version = 1,
            .mutable = false,
        },
    };

    const json = try input.buildJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "0xshared"));
}

test "GasData lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const payment = try allocator.alloc(ImmOrOwnedObjectInput, 1);
    payment[0] = .{
        .object_id = try allocator.dupe(u8, "0xgas"),
        .version = 1,
        .digest = try allocator.dupe(u8, "digest"),
    };

    var gas_data = GasData{
        .payment = payment,
        .owner = try allocator.dupe(u8, "0xowner"),
        .price = 1000,
        .budget = 5000000,
    };
    defer gas_data.deinit(allocator);

    try testing.expectEqual(@as(u64, 1000), gas_data.price);
}

test "GasData buildJson" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const payment = try allocator.alloc(ImmOrOwnedObjectInput, 0);

    const gas_data = GasData{
        .payment = payment,
        .owner = "0xowner",
        .price = 1000,
        .budget = 5000000,
    };

    const json = try gas_data.buildJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "0xowner"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "1000"));
}

test "buildImmOrOwnedObjectInputJson" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const json = try buildImmOrOwnedObjectInputJson(allocator, "0x123", 5, "abc");
    defer allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "objectId"));
    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "version"));
}

test "buildSharedObjectInputJson" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const json = try buildSharedObjectInputJson(allocator, "0xshared", 1, true);
    defer allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "initialSharedVersion"));
}

test "buildReceivingObjectInputJson" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    const json = try buildReceivingObjectInputJson(allocator, "0xrecv", 10, "digest");
    defer allocator.free(json);

    try testing.expect(std.mem.containsAtLeast(u8, json, 1, "0xrecv"));
}
