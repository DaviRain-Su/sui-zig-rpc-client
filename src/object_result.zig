const std = @import("std");

pub const ObjectReadStatus = enum {
    found,
    deleted,
    not_exists,
    version_not_found,
    rpc_error,
};

pub const ObjectOwnerKind = enum {
    address_owner,
    object_owner,
    shared,
    immutable,
    unknown,
};

pub const OwnedObjectSummary = struct {
    status: ObjectReadStatus = .rpc_error,
    object_id: ?[]u8 = null,
    version: ?u64 = null,
    digest: ?[]u8 = null,
    type_name: ?[]u8 = null,
    owner_kind: ?ObjectOwnerKind = null,
    owner_value: ?[]u8 = null,
    shared_object_input_select_token: ?[]u8 = null,
    mutable_shared_object_input_select_token: ?[]u8 = null,
    imm_or_owned_object_input_select_token: ?[]u8 = null,
    receiving_object_input_select_token: ?[]u8 = null,
    previous_transaction: ?[]u8 = null,
    storage_rebate: ?u64 = null,
    error_code: ?[]u8 = null,

    pub fn deinit(self: *OwnedObjectSummary, allocator: std.mem.Allocator) void {
        if (self.object_id) |value| allocator.free(value);
        if (self.digest) |value| allocator.free(value);
        if (self.type_name) |value| allocator.free(value);
        if (self.owner_value) |value| allocator.free(value);
        if (self.shared_object_input_select_token) |value| allocator.free(value);
        if (self.mutable_shared_object_input_select_token) |value| allocator.free(value);
        if (self.imm_or_owned_object_input_select_token) |value| allocator.free(value);
        if (self.receiving_object_input_select_token) |value| allocator.free(value);
        if (self.previous_transaction) |value| allocator.free(value);
        if (self.error_code) |value| allocator.free(value);
    }

    pub fn clone(self: OwnedObjectSummary, allocator: std.mem.Allocator) !OwnedObjectSummary {
        return .{
            .status = self.status,
            .object_id = if (self.object_id) |value| try allocator.dupe(u8, value) else null,
            .version = self.version,
            .digest = if (self.digest) |value| try allocator.dupe(u8, value) else null,
            .type_name = if (self.type_name) |value| try allocator.dupe(u8, value) else null,
            .owner_kind = self.owner_kind,
            .owner_value = if (self.owner_value) |value| try allocator.dupe(u8, value) else null,
            .shared_object_input_select_token = if (self.shared_object_input_select_token) |value| try allocator.dupe(u8, value) else null,
            .mutable_shared_object_input_select_token = if (self.mutable_shared_object_input_select_token) |value| try allocator.dupe(u8, value) else null,
            .imm_or_owned_object_input_select_token = if (self.imm_or_owned_object_input_select_token) |value| try allocator.dupe(u8, value) else null,
            .receiving_object_input_select_token = if (self.receiving_object_input_select_token) |value| try allocator.dupe(u8, value) else null,
            .previous_transaction = if (self.previous_transaction) |value| try allocator.dupe(u8, value) else null,
            .storage_rebate = self.storage_rebate,
            .error_code = if (self.error_code) |value| try allocator.dupe(u8, value) else null,
        };
    }
};

const ParsedOwner = struct {
    kind: ?ObjectOwnerKind,
    owned_value: ?[]u8,
};

fn parseOptionalU64(value: ?std.json.Value) ?u64 {
    const current = value orelse return null;
    return switch (current) {
        .integer => |integer| if (integer >= 0) @intCast(integer) else null,
        .string => |text| std.fmt.parseInt(u64, text, 10) catch null,
        else => null,
    };
}

fn dupeOptionalStringField(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) !?[]u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return try allocator.dupe(u8, value.string);
}

fn extractRootResult(value: std.json.Value) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get("result") orelse value;
}

fn parseOwner(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !ParsedOwner {
    if (value != .object) return .{ .kind = null, .owned_value = null };

    if (value.object.get("AddressOwner")) |owner| {
        if (owner == .string) {
            return .{
                .kind = .address_owner,
                .owned_value = try allocator.dupe(u8, owner.string),
            };
        }
    }

    if (value.object.get("ObjectOwner")) |owner| {
        if (owner == .string) {
            return .{
                .kind = .object_owner,
                .owned_value = try allocator.dupe(u8, owner.string),
            };
        }
    }

    if (value.object.get("Shared")) |owner| {
        if (owner == .object) {
            if (parseOptionalU64(owner.object.get("initial_shared_version"))) |version| {
                return .{
                    .kind = .shared,
                    .owned_value = try std.fmt.allocPrint(allocator, "{d}", .{version}),
                };
            }
        }
        return .{ .kind = .shared, .owned_value = null };
    }

    if (value.object.get("Immutable")) |_| {
        return .{ .kind = .immutable, .owned_value = null };
    }

    return .{ .kind = .unknown, .owned_value = null };
}

fn statusFromErrorCode(code: ?[]const u8) ObjectReadStatus {
    const current = code orelse return .rpc_error;
    if (std.mem.eql(u8, current, "deleted")) return .deleted;
    if (std.mem.eql(u8, current, "notExists") or std.mem.eql(u8, current, "not_exists")) return .not_exists;
    if (std.mem.eql(u8, current, "versionNotFound") or std.mem.eql(u8, current, "version_not_found")) return .version_not_found;
    return .rpc_error;
}

pub fn extractObjectSummary(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !OwnedObjectSummary {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    if (result.object.get("data")) |data| {
        if (data != .object) return error.InvalidResponse;

        const owner: ParsedOwner = if (data.object.get("owner")) |owner_value|
            try parseOwner(allocator, owner_value)
        else
            .{ .kind = null, .owned_value = null };

        return .{
            .status = .found,
            .object_id = try dupeOptionalStringField(allocator, data.object, "objectId"),
            .version = parseOptionalU64(data.object.get("version")),
            .digest = try dupeOptionalStringField(allocator, data.object, "digest"),
            .type_name = try dupeOptionalStringField(allocator, data.object, "type"),
            .owner_kind = owner.kind,
            .owner_value = owner.owned_value,
            .previous_transaction = try dupeOptionalStringField(allocator, data.object, "previousTransaction"),
            .storage_rebate = parseOptionalU64(data.object.get("storageRebate")),
        };
    }

    if (result.object.get("error")) |err| {
        if (err != .object) return error.InvalidResponse;
        const code = try dupeOptionalStringField(allocator, err.object, "code");
        return .{
            .status = statusFromErrorCode(code),
            .object_id = try dupeOptionalStringField(allocator, err.object, "object_id"),
            .version = parseOptionalU64(err.object.get("version")),
            .digest = try dupeOptionalStringField(allocator, err.object, "digest"),
            .error_code = code,
        };
    }

    return error.InvalidResponse;
}

test "extractObjectSummary parses D2-style object envelopes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractObjectSummary(allocator,
        \\{"result":{"data":{"objectId":"0xobject","version":"7","digest":"digest-1","type":"0x2::coin::Coin<0x2::sui::SUI>","owner":{"AddressOwner":"0xowner"},"previousTransaction":"0xprev","storageRebate":"42"}}}
    );
    defer summary.deinit(allocator);

    try testing.expectEqual(ObjectReadStatus.found, summary.status);
    try testing.expectEqualStrings("0xobject", summary.object_id.?);
    try testing.expectEqual(@as(?u64, 7), summary.version);
    try testing.expectEqualStrings("digest-1", summary.digest.?);
    try testing.expectEqualStrings("0x2::coin::Coin<0x2::sui::SUI>", summary.type_name.?);
    try testing.expectEqual(ObjectOwnerKind.address_owner, summary.owner_kind.?);
    try testing.expectEqualStrings("0xowner", summary.owner_value.?);
    try testing.expectEqualStrings("0xprev", summary.previous_transaction.?);
    try testing.expectEqual(@as(?u64, 42), summary.storage_rebate);
}

test "extractObjectSummary parses deleted object responses" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractObjectSummary(allocator,
        \\{"result":{"error":{"code":"deleted","object_id":"0xdead","version":9,"digest":"deleted-digest"}}}
    );
    defer summary.deinit(allocator);

    try testing.expectEqual(ObjectReadStatus.deleted, summary.status);
    try testing.expectEqualStrings("0xdead", summary.object_id.?);
    try testing.expectEqual(@as(?u64, 9), summary.version);
    try testing.expectEqualStrings("deleted-digest", summary.digest.?);
    try testing.expectEqualStrings("deleted", summary.error_code.?);
}
