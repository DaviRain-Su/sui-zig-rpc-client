/// client/rpc_client/move.zig - Move module methods for RPC client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Get normalized Move module
pub fn getNormalizedMoveModule(
    client: *SuiRpcClient,
    package_id: []const u8,
    module_name: []const u8,
) !NormalizedMoveModule {
    if (!utils.isValidAddress(package_id)) {
        return ClientError.InvalidResponse;
    }

    const params = try std.fmt.allocPrint(
        client.allocator,
        "[\"{s}\",\"{s}\"]",
        .{ package_id, module_name },
    );
    defer client.allocator.free(params);

    const response = try client.call("sui_getNormalizedMoveModule", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        return try parseNormalizedMoveModule(client.allocator, result);
    }

    return ClientError.InvalidResponse;
}

/// Normalized Move module
pub const NormalizedMoveModule = struct {
    file_format_version: u32,
    address: []const u8,
    name: []const u8,
    friends: []const []const u8,
    structs: []const NormalizedMoveStruct,
    exposed_functions: []const NormalizedMoveFunction,

    pub fn deinit(self: *NormalizedMoveModule, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
        allocator.free(self.name);
        for (self.friends) |f| allocator.free(f);
        allocator.free(self.friends);
        for (self.structs) |*s| s.deinit(allocator);
        allocator.free(self.structs);
        for (self.exposed_functions) |*f| f.deinit(allocator);
        allocator.free(self.exposed_functions);
    }
};

/// Normalized Move struct
pub const NormalizedMoveStruct = struct {
    name: []const u8,
    is_native: bool,
    abilities: []const []const u8,
    type_parameters: []const MoveStructTypeParameter,
    fields: []const MoveField,

    pub fn deinit(self: *NormalizedMoveStruct, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.abilities) |a| allocator.free(a);
        allocator.free(self.abilities);
        for (self.type_parameters) |*tp| tp.deinit(allocator);
        allocator.free(self.type_parameters);
        for (self.fields) |*f| f.deinit(allocator);
        allocator.free(self.fields);
    }
};

/// Move struct type parameter
pub const MoveStructTypeParameter = struct {
    constraints: []const []const u8,
    is_phantom: bool,

    pub fn deinit(self: *MoveStructTypeParameter, allocator: std.mem.Allocator) void {
        for (self.constraints) |c| allocator.free(c);
        allocator.free(self.constraints);
    }
};

/// Move field
pub const MoveField = struct {
    name: []const u8,
    type: MoveTypeSignature,

    pub fn deinit(self: *MoveField, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.type.deinit(allocator);
    }
};

/// Move type signature
pub const MoveTypeSignature = struct {
    type_tag: MoveTypeTag,
    content: ?[]const u8,

    pub fn deinit(self: *MoveTypeSignature, allocator: std.mem.Allocator) void {
        if (self.content) |c| allocator.free(c);
    }
};

/// Move type tag
pub const MoveTypeTag = enum {
    bool,
    u8,
    u16,
    u32,
    u64,
    u128,
    u256,
    address,
    signer,
    vector,
    structure,
    type_parameter,
    reference,
    mutable_reference,
};

/// Normalized Move function
pub const NormalizedMoveFunction = struct {
    name: []const u8,
    visibility: MoveVisibility,
    is_entry: bool,
    type_parameters: []const []const u8,
    parameters: []const MoveTypeSignature,
    return_arena: []const MoveTypeSignature,

    pub fn deinit(self: *NormalizedMoveFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.type_parameters) |tp| allocator.free(tp);
        allocator.free(self.type_parameters);
        for (self.parameters) |*p| p.deinit(allocator);
        allocator.free(self.parameters);
        for (self.return_arena) |*r| r.deinit(allocator);
        allocator.free(self.return_arena);
    }
};

/// Move visibility
pub const MoveVisibility = enum {
    private,
    public,
    friend,
};

/// Parse normalized Move module
fn parseNormalizedMoveModule(allocator: std.mem.Allocator, value: std.json.Value) !NormalizedMoveModule {
    const file_format_version = value.object.get("fileFormatVersion").?;
    const address = value.object.get("address").?;
    const name = value.object.get("name").?;

    var friends = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (friends.items) |f| allocator.free(f);
        friends.deinit();
    }

    if (value.object.get("friends")) |f| {
        if (f == .array) {
            for (f.array.items) |friend| {
                try friends.append(try allocator.dupe(u8, friend.string));
            }
        }
    }

    var structs = std.ArrayList(NormalizedMoveStruct).init(allocator);
    errdefer {
        for (structs.items) |*s| s.deinit(allocator);
        structs.deinit();
    }

    if (value.object.get("structs")) |s| {
        if (s == .object) {
            var it = s.object.iterator();
            while (it.next()) |entry| {
                var parsed = try parseNormalizedMoveStruct(allocator, entry.value_ptr.*);
                parsed.name = try allocator.dupe(u8, entry.key_ptr.*);
                try structs.append(parsed);
            }
        }
    }

    var exposed_functions = std.ArrayList(NormalizedMoveFunction).init(allocator);
    errdefer {
        for (exposed_functions.items) |*f| f.deinit(allocator);
        exposed_functions.deinit();
    }

    if (value.object.get("exposedFunctions")) |ef| {
        if (ef == .object) {
            var it = ef.object.iterator();
            while (it.next()) |entry| {
                var parsed = try parseNormalizedMoveFunction(allocator, entry.value_ptr.*);
                parsed.name = try allocator.dupe(u8, entry.key_ptr.*);
                try exposed_functions.append(parsed);
            }
        }
    }

    return NormalizedMoveModule{
        .file_format_version = @intCast(file_format_version.integer),
        .address = try allocator.dupe(u8, address.string),
        .name = try allocator.dupe(u8, name.string),
        .friends = try friends.toOwnedSlice(),
        .structs = try structs.toOwnedSlice(),
        .exposed_functions = try exposed_functions.toOwnedSlice(),
    };
}

/// Parse normalized Move struct
fn parseNormalizedMoveStruct(allocator: std.mem.Allocator, value: std.json.Value) !NormalizedMoveStruct {
    const is_native = value.object.get("isNative").?;

    var abilities = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (abilities.items) |a| allocator.free(a);
        abilities.deinit();
    }

    if (value.object.get("abilities")) |a| {
        if (a == .array) {
            for (a.array.items) |ability| {
                try abilities.append(try allocator.dupe(u8, ability.string));
            }
        }
    }

    var type_parameters = std.ArrayList(MoveStructTypeParameter).init(allocator);
    errdefer {
        for (type_parameters.items) |*tp| tp.deinit(allocator);
        type_parameters.deinit();
    }

    if (value.object.get("typeParameters")) |tp| {
        if (tp == .array) {
            for (tp.array.items) |param| {
                const parsed = try parseMoveStructTypeParameter(allocator, param);
                try type_parameters.append(parsed);
            }
        }
    }

    var fields = std.ArrayList(MoveField).init(allocator);
    errdefer {
        for (fields.items) |*f| f.deinit(allocator);
        fields.deinit();
    }

    if (value.object.get("fields")) |f| {
        if (f == .array) {
            for (f.array.items) |field| {
                const parsed = try parseMoveField(allocator, field);
                try fields.append(parsed);
            }
        }
    }

    return NormalizedMoveStruct{
        .name = undefined, // Will be set by caller
        .is_native = is_native.bool,
        .abilities = try abilities.toOwnedSlice(),
        .type_parameters = try type_parameters.toOwnedSlice(),
        .fields = try fields.toOwnedSlice(),
    };
}

/// Parse Move struct type parameter
fn parseMoveStructTypeParameter(allocator: std.mem.Allocator, value: std.json.Value) !MoveStructTypeParameter {
    var constraints = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (constraints.items) |c| allocator.free(c);
        constraints.deinit();
    }

    if (value.object.get("constraints")) |c| {
        if (c == .array) {
            for (c.array.items) |constraint| {
                try constraints.append(try allocator.dupe(u8, constraint.string));
            }
        }
    }

    const is_phantom = value.object.get("isPhantom").?;

    return MoveStructTypeParameter{
        .constraints = try constraints.toOwnedSlice(),
        .is_phantom = is_phantom.bool,
    };
}

/// Parse Move field
fn parseMoveField(allocator: std.mem.Allocator, value: std.json.Value) !MoveField {
    const name = value.object.get("name").?;
    const type_value = value.object.get("type").?;

    return MoveField{
        .name = try allocator.dupe(u8, name.string),
        .type = try parseMoveTypeSignature(allocator, type_value),
    };
}

/// Parse Move type signature
fn parseMoveTypeSignature(allocator: std.mem.Allocator, value: std.json.Value) !MoveTypeSignature {
    // Simplified parsing - full implementation would handle all type variants
    const content = try std.json.stringifyAlloc(allocator, value, .{});

    return MoveTypeSignature{
        .type_tag = .address, // Default
        .content = content,
    };
}

/// Parse normalized Move function
fn parseNormalizedMoveFunction(allocator: std.mem.Allocator, value: std.json.Value) !NormalizedMoveFunction {
    const visibility = value.object.get("visibility").?;
    const is_entry = value.object.get("isEntry").?;

    var type_parameters = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (type_parameters.items) |tp| allocator.free(tp);
        type_parameters.deinit();
    }

    if (value.object.get("typeParameters")) |tp| {
        if (tp == .array) {
            for (tp.array.items) |param| {
                try type_parameters.append(try allocator.dupe(u8, param.string));
            }
        }
    }

    var parameters = std.ArrayList(MoveTypeSignature).init(allocator);
    errdefer {
        for (parameters.items) |*p| p.deinit(allocator);
        parameters.deinit();
    }

    if (value.object.get("parameters")) |p| {
        if (p == .array) {
            for (p.array.items) |param| {
                const parsed = try parseMoveTypeSignature(allocator, param);
                try parameters.append(parsed);
            }
        }
    }

    var return_arena = std.ArrayList(MoveTypeSignature).init(allocator);
    errdefer {
        for (return_arena.items) |*r| r.deinit(allocator);
        return_arena.deinit();
    }

    if (value.object.get("return")) |r| {
        if (r == .array) {
            for (r.array.items) |ret| {
                const parsed = try parseMoveTypeSignature(allocator, ret);
                try return_arena.append(parsed);
            }
        }
    }

    return NormalizedMoveFunction{
        .name = undefined, // Will be set by caller
        .visibility = parseMoveVisibility(visibility.string),
        .is_entry = is_entry.bool,
        .type_parameters = try type_parameters.toOwnedSlice(),
        .parameters = try parameters.toOwnedSlice(),
        .return_arena = try return_arena.toOwnedSlice(),
    };
}

/// Parse Move visibility
fn parseMoveVisibility(str: []const u8) MoveVisibility {
    if (std.mem.eql(u8, str, "Public")) return .public;
    if (std.mem.eql(u8, str, "Friend")) return .friend;
    return .private;
}

// ============================================================
// Tests
// ============================================================

test "MoveVisibility parsing" {
    const testing = std.testing;

    try testing.expectEqual(MoveVisibility.public, parseMoveVisibility("Public"));
    try testing.expectEqual(MoveVisibility.friend, parseMoveVisibility("Friend"));
    try testing.expectEqual(MoveVisibility.private, parseMoveVisibility("Private"));
    try testing.expectEqual(MoveVisibility.private, parseMoveVisibility("Other"));
}

test "MoveStructTypeParameter structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const constraints = try allocator.alloc([]const u8, 1);
    constraints[0] = try allocator.dupe(u8, "Copy");

    var param = MoveStructTypeParameter{
        .constraints = constraints,
        .is_phantom = false,
    };
    defer param.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), param.constraints.len);
    try testing.expect(!param.is_phantom);
}

test "MoveField structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var field = MoveField{
        .name = try allocator.dupe(u8, "value"),
        .type = MoveTypeSignature{
            .type_tag = .u64,
            .content = try allocator.dupe(u8, "U64"),
        },
    };
    defer field.deinit(allocator);

    try testing.expectEqualStrings("value", field.name);
}

test "MoveTypeSignature deinit" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sig = MoveTypeSignature{
        .type_tag = .structure,
        .content = try allocator.dupe(u8, "{}"),
    };
    defer sig.deinit(allocator);

    try testing.expect(sig.content != null);
}

test "NormalizedMoveFunction structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = try allocator.alloc(MoveTypeSignature, 1);
    params[0] = MoveTypeSignature{
        .type_tag = .address,
        .content = null,
    };

    var func = NormalizedMoveFunction{
        .name = try allocator.dupe(u8, "transfer"),
        .visibility = .public,
        .is_entry = true,
        .type_parameters = &.{},
        .parameters = params,
        .return_arena = &.{},
    };
    defer func.deinit(allocator);

    try testing.expectEqualStrings("transfer", func.name);
    try testing.expect(func.is_entry);
}

test "NormalizedMoveStruct structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const fields = try allocator.alloc(MoveField, 1);
    fields[0] = MoveField{
        .name = try allocator.dupe(u8, "id"),
        .type = MoveTypeSignature{
            .type_tag = .address,
            .content = null,
        },
    };

    var struct_def = NormalizedMoveStruct{
        .name = try allocator.dupe(u8, "Object"),
        .is_native = false,
        .abilities = &.{},
        .type_parameters = &.{},
        .fields = fields,
    };
    defer struct_def.deinit(allocator);

    try testing.expectEqualStrings("Object", struct_def.name);
    try testing.expect(!struct_def.is_native);
}
