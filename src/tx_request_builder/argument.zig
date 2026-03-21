/// tx_request_builder/argument.zig - Argument handling for PTB
const std = @import("std");
const types = @import("types.zig");

const NestedResultSpec = types.NestedResultSpec;

/// Argument value types for PTB commands
pub const ArgumentValue = union(enum) {
    /// Gas coin reference
    gas,
    /// Input parameter index
    input: u16,
    /// Result of a previous command
    result: CommandResultHandle,
    /// Nested result (specific output of a command)
    output: CommandOutputHandle,
    /// Pure value (literal)
    pure: []const u8,
    /// Object reference
    object: ObjectReference,

    pub fn deinit(self: *ArgumentValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .pure => |p| allocator.free(p),
            else => {},
        }
    }
};

/// Object reference for arguments
pub const ObjectReference = struct {
    object_id: []const u8,
    version: u64,
    digest: []const u8,

    pub fn deinit(self: *ObjectReference, allocator: std.mem.Allocator) void {
        allocator.free(self.object_id);
        allocator.free(self.digest);
    }
};

/// Command result handle for referencing command outputs
pub const CommandResultHandle = struct {
    command_index: u16,

    pub fn asSpec(self: CommandResultHandle) PtbArgumentSpec {
        return .{ .result = self.command_index };
    }

    pub fn asValue(self: CommandResultHandle) ArgumentValue {
        return .{ .result = self };
    }

    pub fn output(self: CommandResultHandle, result_index: u16) CommandOutputHandle {
        return .{
            .command_index = self.command_index,
            .result_index = result_index,
        };
    }

    pub fn outputValue(self: CommandResultHandle, result_index: u16) ArgumentValue {
        return self.output(result_index).asValue();
    }
};

/// Command output handle for nested results
pub const CommandOutputHandle = struct {
    command_index: u16,
    result_index: u16,

    pub fn asSpec(self: CommandOutputHandle) PtbArgumentSpec {
        return .{
            .nested_result = .{
                .command_index = self.command_index,
                .result_index = self.result_index,
            },
        };
    }

    pub fn asValue(self: CommandOutputHandle) ArgumentValue {
        return .{ .output = self };
    }
};

/// PTB argument specification
pub const PtbArgumentSpec = union(enum) {
    /// Gas coin
    gas,
    /// Input parameter
    input: u16,
    /// Result reference
    result: u16,
    /// Nested result reference
    nested_result: NestedResultSpec,
    /// Pure value
    pure: []const u8,
    /// Object reference
    object: ObjectReference,

    pub fn deinit(self: *PtbArgumentSpec, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .pure => |p| allocator.free(p),
            .object => |*o| o.deinit(allocator),
            else => {},
        }
    }
};

/// Resolved argument value with metadata
pub const ResolvedArgumentValue = struct {
    value: ArgumentValue,
    type_tag: ?[]const u8 = null,
    owned_type: ?[]const u8 = null,

    pub fn deinit(self: *ResolvedArgumentValue, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
        if (self.type_tag) |t| allocator.free(t);
        if (self.owned_type) |t| allocator.free(t);
    }
};

/// Collection of owned argument values
pub const OwnedArgumentValues = struct {
    values: std.ArrayListUnmanaged(ArgumentValue) = .{},

    pub fn deinit(self: *OwnedArgumentValues, allocator: std.mem.Allocator) void {
        for (self.values.items) |*v| {
            v.deinit(allocator);
        }
        self.values.deinit(allocator);
    }
};

/// Collection of owned command result handles
pub const OwnedCommandResultHandles = struct {
    handles: std.ArrayListUnmanaged(CommandResultHandle) = .{},

    pub fn deinit(self: *OwnedCommandResultHandles, allocator: std.mem.Allocator) void {
        self.handles.deinit(allocator);
    }
};

/// Resolved PTB argument specification
pub const ResolvedPtbArgumentSpec = struct {
    spec: PtbArgumentSpec,
    owned_json: ?[]const u8 = null,

    pub fn deinit(self: *ResolvedPtbArgumentSpec, allocator: std.mem.Allocator) void {
        self.spec.deinit(allocator);
        if (self.owned_json) |j| allocator.free(j);
    }
};

/// Collection of resolved PTB argument specs
pub const ResolvedPtbArgumentSpecs = struct {
    items: std.ArrayListUnmanaged(PtbArgumentSpec) = .{},
    owned_json_items: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *ResolvedPtbArgumentSpecs, allocator: std.mem.Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit(allocator);
        for (self.owned_json_items.items) |item| {
            allocator.free(item);
        }
        self.owned_json_items.deinit(allocator);
    }
};

/// Argument vector value (for make_move_vec)
pub const ArgumentVectorValue = struct {
    items: []const ArgumentValue,
};

/// Argument option value
pub const ArgumentOptionValue = union(enum) {
    none,
    some: *const ArgumentValue,
};

// ============================================================
// Tests
// ============================================================

test "CommandResultHandle operations" {
    const testing = std.testing;

    const handle = CommandResultHandle{ .command_index = 5 };

    try testing.expectEqual(@as(u16, 5), handle.command_index);

    const spec = handle.asSpec();
    try testing.expectEqual(@as(u16, 5), spec.result);

    const output = handle.output(2);
    try testing.expectEqual(@as(u16, 5), output.command_index);
    try testing.expectEqual(@as(u16, 2), output.result_index);
}

test "CommandOutputHandle operations" {
    const testing = std.testing;

    const handle = CommandOutputHandle{
        .command_index = 3,
        .result_index = 1,
    };

    const spec = handle.asSpec();
    try testing.expectEqual(@as(u16, 3), spec.nested_result.command_index);
    try testing.expectEqual(@as(u16, 1), spec.nested_result.result_index);
}

test "ArgumentValue lifecycle" {
    const testing = std.testing;

    var value = ArgumentValue{
        .pure = try testing.allocator.dupe(u8, "test_value"),
    };
    defer value.deinit(testing.allocator);

    try testing.expectEqualStrings("test_value", value.pure);
}

test "ObjectReference lifecycle" {
    const testing = std.testing;

    var obj = ObjectReference{
        .object_id = try testing.allocator.dupe(u8, "0x123"),
        .version = 1,
        .digest = try testing.allocator.dupe(u8, "abc"),
    };
    defer obj.deinit(testing.allocator);

    try testing.expectEqualStrings("0x123", obj.object_id);
    try testing.expectEqual(@as(u64, 1), obj.version);
}

test "PtbArgumentSpec lifecycle" {
    const testing = std.testing;

    var spec = PtbArgumentSpec{
        .pure = try testing.allocator.dupe(u8, "value"),
    };
    defer spec.deinit(testing.allocator);

    try testing.expectEqualStrings("value", spec.pure);
}

test "ResolvedArgumentValue lifecycle" {
    const testing = std.testing;

    var resolved = ResolvedArgumentValue{
        .value = .{ .gas = {} },
        .type_tag = try testing.allocator.dupe(u8, "u64"),
    };
    defer resolved.deinit(testing.allocator);

    try testing.expectEqualStrings("u64", resolved.type_tag.?);
}

test "OwnedArgumentValues lifecycle" {
    const testing = std.testing;

    var owned = OwnedArgumentValues{};
    defer owned.deinit(testing.allocator);

    const value = ArgumentValue{ .gas = {} };
    try owned.values.append(testing.allocator, value);

    try testing.expectEqual(@as(usize, 1), owned.values.items.len);
}

test "OwnedCommandResultHandles lifecycle" {
    const testing = std.testing;

    var owned = OwnedCommandResultHandles{};
    defer owned.deinit(testing.allocator);

    const handle = CommandResultHandle{ .command_index = 0 };
    try owned.handles.append(testing.allocator, handle);

    try testing.expectEqual(@as(usize, 1), owned.handles.items.len);
}

test "ResolvedPtbArgumentSpec lifecycle" {
    const testing = std.testing;

    var resolved = ResolvedPtbArgumentSpec{
        .spec = .{ .input = 5 },
        .owned_json = try testing.allocator.dupe(u8, "{\"input\":5}"),
    };
    defer resolved.deinit(testing.allocator);

    try testing.expectEqual(@as(u16, 5), resolved.spec.input);
}

test "ResolvedPtbArgumentSpecs lifecycle" {
    const testing = std.testing;

    var specs = ResolvedPtbArgumentSpecs{};
    defer specs.deinit(testing.allocator);

    try specs.items.append(testing.allocator, .{ .gas = {} });
    const json = try testing.allocator.dupe(u8, "{}");
    try specs.owned_json_items.append(testing.allocator, json);

    try testing.expectEqual(@as(usize, 1), specs.items.items.len);
}

test "ArgumentOptionValue union" {
    const testing = std.testing;

    const none_value: ArgumentOptionValue = .none;
    try testing.expectEqual(ArgumentOptionValue.none, none_value);

    const some_value = ArgumentValue{ .gas = {} };
    const some: ArgumentOptionValue = .{ .some = &some_value };
    try testing.expect(some == .some);
}
