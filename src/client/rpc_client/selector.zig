/// client/rpc_client/selector.zig - Argument selection for Sui RPC Client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Selected argument request
pub const SelectedArgumentRequest = struct {
    /// Selection type
    selection_type: SelectionType,
    /// Object ID or address
    target: []const u8,
    /// Optional index for indexed selections
    index: ?u32 = null,
    /// Optional type filter
    type_filter: ?[]const u8 = null,

    pub fn deinit(self: *SelectedArgumentRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.target);
        if (self.type_filter) |tf| allocator.free(tf);
    }
};

/// Selection type
pub const SelectionType = enum {
    /// Select by object ID
    object_id,
    /// Select by object type
    object_type,
    /// Select by coin type
    coin_type,
    /// Select by address
    address,
    /// Select NFT by type
    nft_type,
    /// Select by dynamic field name
    dynamic_field_name,
};

/// Owned selected argument request (memory managed)
pub const OwnedSelectedArgumentRequest = struct {
    /// The request value
    value: SelectedArgumentRequest,
    /// Owned target string
    owned_target: ?[]u8 = null,
    /// Owned type filter
    owned_type_filter: ?[]u8 = null,

    pub fn deinit(self: *OwnedSelectedArgumentRequest, allocator: std.mem.Allocator) void {
        if (self.owned_target) |t| allocator.free(t);
        if (self.owned_type_filter) |tf| allocator.free(tf);
    }
};

/// Selected argument value
pub const SelectedArgumentValue = struct {
    /// The selected value (BCS encoded)
    value: []const u8,
    /// Type of the value
    value_type: []const u8,
    /// Source information
    source: SelectionSource,

    pub fn deinit(self: *SelectedArgumentValue, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
        allocator.free(self.value_type);
        self.source.deinit(allocator);
    }
};

/// Selection source
pub const SelectionSource = struct {
    /// Object ID if from object
    object_id: ?[]const u8 = null,
    /// Version if from object
    version: ?u64 = null,
    /// Digest if from object
    digest: ?[]const u8 = null,

    pub fn deinit(self: *SelectionSource, allocator: std.mem.Allocator) void {
        if (self.object_id) |id| allocator.free(id);
        if (self.digest) |d| allocator.free(d);
    }
};

/// Owned selected argument value
pub const OwnedSelectedArgumentValue = struct {
    /// The value
    value: SelectedArgumentValue,
    /// Owned value bytes
    owned_value: ?[]u8 = null,
    /// Owned type string
    owned_type: ?[]u8 = null,

    pub fn deinit(self: *OwnedSelectedArgumentValue, allocator: std.mem.Allocator) void {
        if (self.owned_value) |v| allocator.free(v);
        if (self.owned_type) |t| allocator.free(t);
        self.value.deinit(allocator);
    }
};

/// Collection of owned selected argument values
pub const OwnedSelectedArgumentValues = struct {
    values: std.ArrayListUnmanaged(OwnedSelectedArgumentValue) = .{},

    pub fn deinit(self: *OwnedSelectedArgumentValues, allocator: std.mem.Allocator) void {
        for (self.values.items) |*v| v.deinit(allocator);
        self.values.deinit(allocator);
    }

    pub fn appendOwned(
        self: *OwnedSelectedArgumentValues,
        allocator: std.mem.Allocator,
        value: OwnedSelectedArgumentValue,
    ) !void {
        try self.values.append(allocator, value);
    }
};

/// Parse selected argument request token
/// Token format: "type:target" or "type:target:index" or "type:target:type_filter"
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
    _ = default_owner;
    
    // Split token by ':'
    var parts = std.mem.split(u8, token, ":");
    
    const type_str = parts.next() orelse return error.InvalidTokenFormat;
    const target_str = parts.next() orelse return error.InvalidTokenFormat;
    
    // Parse selection type
    const selection_type = parseSelectionType(type_str) orelse return error.UnknownSelectionType;
    
    // Parse optional index or type filter
    var index: ?u32 = null;
    var type_filter: ?[]const u8 = null;
    
    if (parts.next()) |extra| {
        // Try to parse as index first
        if (std.fmt.parseInt(u32, extra, 10)) |idx| {
            index = idx;
        } else |_| {
            // Otherwise treat as type filter
            type_filter = try allocator.dupe(u8, extra);
        }
    }
    
    const target = try allocator.dupe(u8, target_str);
    errdefer allocator.free(target);
    
    return OwnedSelectedArgumentRequest{
        .value = SelectedArgumentRequest{
            .selection_type = selection_type,
            .target = target,
            .index = index,
            .type_filter = type_filter,
        },
        .owned_target = target,
        .owned_type_filter = type_filter,
    };
}

/// Parse selection type from string
fn parseSelectionType(type_str: []const u8) ?SelectionType {
    if (std.mem.eql(u8, type_str, "object")) return .object_id;
    if (std.mem.eql(u8, type_str, "type")) return .object_type;
    if (std.mem.eql(u8, type_str, "coin")) return .coin_type;
    if (std.mem.eql(u8, type_str, "address")) return .address;
    if (std.mem.eql(u8, type_str, "nft")) return .nft_type;
    if (std.mem.eql(u8, type_str, "field")) return .dynamic_field_name;
    return null;
}

/// Select argument value
pub fn selectArgumentValue(
    client: *SuiRpcClient,
    allocator: std.mem.Allocator,
    request: SelectedArgumentRequest,
) !?OwnedSelectedArgumentValue {
    return try selectArgumentValueWithDefaultOwner(client, allocator, request, null);
}

/// Select argument value with default owner
pub fn selectArgumentValueWithDefaultOwner(
    client: *SuiRpcClient,
    allocator: std.mem.Allocator,
    request: SelectedArgumentRequest,
    default_owner: ?[]const u8,
) !?OwnedSelectedArgumentValue {
    _ = client;
    _ = default_owner;
    
    // Simplified implementation - would actually query objects
    const value = try allocator.dupe(u8, "selected_value");
    errdefer allocator.free(value);
    
    const value_type = try allocator.dupe(u8, "address");
    errdefer allocator.free(value_type);
    
    const target_copy = try allocator.dupe(u8, request.target);
    
    return OwnedSelectedArgumentValue{
        .value = SelectedArgumentValue{
            .value = value,
            .value_type = value_type,
            .source = SelectionSource{
                .object_id = target_copy,
                .version = 1,
                .digest = null,
            },
        },
        .owned_value = value,
        .owned_type = value_type,
    };
}

/// Select argument value from token
pub fn selectArgumentValueFromToken(
    client: *SuiRpcClient,
    allocator: std.mem.Allocator,
    token: []const u8,
) !?OwnedSelectedArgumentValue {
    return try selectArgumentValueFromTokenWithDefaultOwner(client, allocator, token, null);
}

/// Select argument value from token with default owner
pub fn selectArgumentValueFromTokenWithDefaultOwner(
    client: *SuiRpcClient,
    allocator: std.mem.Allocator,
    token: []const u8,
    default_owner: ?[]const u8,
) !?OwnedSelectedArgumentValue {
    var request = try parseSelectedArgumentRequestTokenWithDefaultOwner(allocator, token, default_owner);
    defer request.deinit(allocator);
    
    return try selectArgumentValueWithDefaultOwner(client, allocator, request.value, default_owner);
}

/// Select argument values from multiple tokens
pub fn selectArgumentValuesFromTokens(
    client: *SuiRpcClient,
    allocator: std.mem.Allocator,
    tokens: []const []const u8,
) !OwnedSelectedArgumentValues {
    return try selectArgumentValuesFromTokensWithDefaultOwner(client, allocator, tokens, null);
}

/// Select argument values from multiple tokens with default owner
pub fn selectArgumentValuesFromTokensWithDefaultOwner(
    client: *SuiRpcClient,
    allocator: std.mem.Allocator,
    tokens: []const []const u8,
    default_owner: ?[]const u8,
) !OwnedSelectedArgumentValues {
    var values = OwnedSelectedArgumentValues{};
    errdefer values.deinit(allocator);
    
    for (tokens) |token| {
        const selected = try selectArgumentValueFromTokenWithDefaultOwner(
            client,
            allocator,
            token,
            default_owner,
        ) orelse return error.SelectionNotFound;
        try values.appendOwned(allocator, selected);
    }
    
    return values;
}

/// Select multiple argument values
pub fn selectArgumentValues(
    client: *SuiRpcClient,
    allocator: std.mem.Allocator,
    requests: []const SelectedArgumentRequest,
) !OwnedSelectedArgumentValues {
    var values = OwnedSelectedArgumentValues{};
    errdefer values.deinit(allocator);
    
    for (requests) |request| {
        const selected = try selectArgumentValue(client, allocator, request) orelse 
            return error.SelectionNotFound;
        try values.appendOwned(allocator, selected);
    }
    
    return values;
}

// ============================================================
// Tests
// ============================================================

test "parseSelectionType" {
    const testing = std.testing;
    
    try testing.expectEqual(SelectionType.object_id, parseSelectionType("object").?);
    try testing.expectEqual(SelectionType.coin_type, parseSelectionType("coin").?);
    try testing.expectEqual(SelectionType.address, parseSelectionType("address").?);
    try testing.expectEqual(null, parseSelectionType("unknown"));
}

test "SelectedArgumentRequest lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;
    
    var request = SelectedArgumentRequest{
        .selection_type = .object_id,
        .target = try allocator.dupe(u8, "0x123"),
        .index = 0,
        .type_filter = try allocator.dupe(u8, "0x2::sui::SUI"),
    };
    defer request.deinit(allocator);
    
    try testing.expectEqual(SelectionType.object_id, request.selection_type);
    try testing.expectEqualStrings("0x123", request.target);
}

test "parseSelectedArgumentRequestToken basic" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;
    
    var owned = try parseSelectedArgumentRequestToken(allocator, "object:0x123");
    defer owned.deinit(allocator);
    
    try testing.expectEqual(SelectionType.object_id, owned.value.selection_type);
    try testing.expectEqualStrings("0x123", owned.value.target);
}

test "parseSelectedArgumentRequestToken with index" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;
    
    var owned = try parseSelectedArgumentRequestToken(allocator, "coin:0x123:5");
    defer owned.deinit(allocator);
    
    try testing.expectEqual(SelectionType.coin_type, owned.value.selection_type);
    try testing.expectEqual(@as(?u32, 5), owned.value.index);
}

test "parseSelectedArgumentRequestToken with type filter" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;
    
    var owned = try parseSelectedArgumentRequestToken(allocator, "type:0x123:0x2::sui::SUI");
    defer owned.deinit(allocator);
    
    try testing.expectEqual(SelectionType.object_type, owned.value.selection_type);
    try testing.expectEqualStrings("0x2::sui::SUI", owned.value.type_filter.?);
}

test "parseSelectedArgumentRequestToken invalid format" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const result = parseSelectedArgumentRequestToken(allocator, "invalid");
    try testing.expectError(error.InvalidTokenFormat, result);
}

test "parseSelectedArgumentRequestToken unknown type" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const result = parseSelectedArgumentRequestToken(allocator, "unknown:0x123");
    try testing.expectError(error.UnknownSelectionType, result);
}

test "OwnedSelectedArgumentValues lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;
    
    var values = OwnedSelectedArgumentValues{};
    defer values.deinit(allocator);
    
    const value1 = OwnedSelectedArgumentValue{
        .value = SelectedArgumentValue{
            .value = try allocator.dupe(u8, "val1"),
            .value_type = try allocator.dupe(u8, "type1"),
            .source = SelectionSource{ .object_id = null, .version = null, .digest = null },
        },
        .owned_value = null,
        .owned_type = null,
    };
    
    try values.appendOwned(allocator, value1);
    try testing.expectEqual(@as(usize, 1), values.values.items.len);
}

test "SelectionSource lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;
    
    var source = SelectionSource{
        .object_id = try allocator.dupe(u8, "0x123"),
        .version = 1,
        .digest = try allocator.dupe(u8, "abc"),
    };
    defer source.deinit(allocator);
    
    try testing.expectEqualStrings("0x123", source.object_id.?);
}

test "SelectedArgumentValue lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;
    
    var value = SelectedArgumentValue{
        .value = try allocator.dupe(u8, "value_bytes"),
        .value_type = try allocator.dupe(u8, "address"),
        .source = SelectionSource{
            .object_id = try allocator.dupe(u8, "0x123"),
            .version = 1,
            .digest = null,
        },
    };
    defer value.deinit(allocator);
    
    try testing.expectEqualStrings("value_bytes", value.value);
}
