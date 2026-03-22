/// client/rpc_client/types_ext.zig - Extended type system for Sui RPC Client
const std = @import("std");

/// BCS serializer
pub const BcsSerializer = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) BcsSerializer {
        return .{ .buffer = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *BcsSerializer) void {
        self.buffer.deinit();
    }

    /// Serialize a u8
    pub fn writeU8(self: *BcsSerializer, value: u8) !void {
        try self.buffer.append(value);
    }

    /// Serialize a u16 (little endian)
    pub fn writeU16(self: *BcsSerializer, value: u16) !void {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }

    /// Serialize a u32 (little endian)
    pub fn writeU32(self: *BcsSerializer, value: u32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }

    /// Serialize a u64 (little endian)
    pub fn writeU64(self: *BcsSerializer, value: u64) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }

    /// Serialize a u128 (little endian)
    pub fn writeU128(self: *BcsSerializer, value: u128) !void {
        var bytes: [16]u8 = undefined;
        std.mem.writeInt(u128, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }

    /// Serialize a u256 (little endian)
    pub fn writeU256(self: *BcsSerializer, value: u256) !void {
        var bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &bytes, value, .little);
        try self.buffer.appendSlice(&bytes);
    }

    /// Serialize a bool
    pub fn writeBool(self: *BcsSerializer, value: bool) !void {
        try self.buffer.append(if (value) 1 else 0);
    }

    /// Serialize bytes with length prefix (ULEB128)
    pub fn writeBytes(self: *BcsSerializer, bytes: []const u8) !void {
        try self.writeUleb128(@intCast(bytes.len));
        try self.buffer.appendSlice(bytes);
    }

    /// Write ULEB128 encoded length
    pub fn writeUleb128(self: *BcsSerializer, value: u64) !void {
        var v = value;
        while (v >= 0x80) {
            try self.buffer.append(@intCast((v & 0x7f) | 0x80));
            v >>= 7;
        }
        try self.buffer.append(@intCast(v));
    }

    /// Get the serialized bytes
    pub fn getBytes(self: *const BcsSerializer) []const u8 {
        return self.buffer.items;
    }

    /// Reset the serializer
    pub fn reset(self: *BcsSerializer) void {
        self.buffer.clearRetainingCapacity();
    }
};

/// Move type tag (extended)
pub const MoveTypeTag = union(enum) {
    bool,
    u8,
    u16,
    u32,
    u64,
    u128,
    u256,
    address,
    signer,
    vector: *MoveTypeTag,
    structure: MoveStructTag,
    type_parameter: u16,

    pub fn deinit(self: *MoveTypeTag, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .vector => |v| {
                v.deinit(allocator);
                allocator.destroy(v);
            },
            .structure => |*s| s.deinit(allocator),
            else => {},
        }
    }

    /// Serialize to BCS
    pub fn serialize(self: MoveTypeTag, serializer: *BcsSerializer) !void {
        switch (self) {
            .bool => try serializer.writeU8(0),
            .u8 => try serializer.writeU8(1),
            .u16 => try serializer.writeU8(2),
            .u32 => try serializer.writeU8(3),
            .u64 => try serializer.writeU8(4),
            .u128 => try serializer.writeU8(5),
            .u256 => try serializer.writeU8(6),
            .address => try serializer.writeU8(7),
            .signer => try serializer.writeU8(8),
            .vector => |v| {
                try serializer.writeU8(9);
                try v.serialize(serializer);
            },
            .structure => |s| {
                try serializer.writeU8(10);
                try s.serialize(serializer);
            },
            .type_parameter => |p| {
                try serializer.writeU8(11);
                try serializer.writeU16(p);
            },
        }
    }
};

/// Move struct tag
pub const MoveStructTag = struct {
    address: [32]u8,
    module: []const u8,
    name: []const u8,
    type_args: []const MoveTypeTag,

    pub fn deinit(self: *MoveStructTag, allocator: std.mem.Allocator) void {
        allocator.free(self.module);
        allocator.free(self.name);
        for (self.type_args) |*ta| {
            ta.deinit(allocator);
        }
        allocator.free(self.type_args);
    }

    /// Serialize to BCS
    pub fn serialize(self: MoveStructTag, serializer: *BcsSerializer) !void {
        try serializer.buffer.appendSlice(&self.address);
        try serializer.writeBytes(self.module);
        try serializer.writeBytes(self.name);
        try serializer.writeUleb128(@intCast(self.type_args.len));
        for (self.type_args) |ta| {
            try ta.serialize(serializer);
        }
    }
};

/// Sui address (32 bytes)
pub const SuiAddress = [32]u8;

/// Object ID
pub const ObjectID = [32]u8;

/// Object reference
pub const ObjectRef = struct {
    object_id: ObjectID,
    version: u64,
    digest: [32]u8,

    /// Serialize to BCS
    pub fn serialize(self: ObjectRef, serializer: *BcsSerializer) !void {
        try serializer.buffer.appendSlice(&self.object_id);
        try serializer.writeU64(self.version);
        try serializer.buffer.appendSlice(&self.digest);
    }
};

/// Transaction argument
pub const TransactionArgument = union(enum) {
    /// Pure value (BCS bytes)
    pure: []const u8,
    /// Object reference (immortal/owned)
    object_ref: ObjectRef,
    /// Shared object reference
    shared_object_ref: SharedObjectRef,
    /// Receiving object reference
    receiving_object_ref: ObjectRef,

    pub fn deinit(self: *TransactionArgument, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .pure => |p| allocator.free(p),
            else => {},
        }
    }

    /// Serialize to BCS
    pub fn serialize(self: TransactionArgument, serializer: *BcsSerializer) !void {
        switch (self) {
            .pure => |p| {
                try serializer.writeU8(0);
                try serializer.writeBytes(p);
            },
            .object_ref => |r| {
                try serializer.writeU8(1);
                try r.serialize(serializer);
            },
            .shared_object_ref => |r| {
                try serializer.writeU8(2);
                try r.serialize(serializer);
            },
            .receiving_object_ref => |r| {
                try serializer.writeU8(3);
                try r.serialize(serializer);
            },
        }
    }
};

/// Shared object reference
pub const SharedObjectRef = struct {
    object_id: ObjectID,
    initial_shared_version: u64,
    mutable: bool,

    /// Serialize to BCS
    pub fn serialize(self: SharedObjectRef, serializer: *BcsSerializer) !void {
        try serializer.buffer.appendSlice(&self.object_id);
        try serializer.writeU64(self.initial_shared_version);
        try serializer.writeBool(self.mutable);
    }
};

/// Call argument
pub const CallArgument = union(enum) {
    /// Pure value
    pure: []const u8,
    /// Object argument
    object: ObjectArg,

    pub fn deinit(self: *CallArgument, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .pure => |p| allocator.free(p),
            .object => |*o| o.deinit(allocator),
        }
    }
};

/// Object argument
pub const ObjectArg = union(enum) {
    immortal: ObjectRef,
    shared: SharedObjectRef,
    receiving: ObjectRef,

    pub fn deinit(self: *ObjectArg, allocator: std.mem.Allocator) void {
        _ = allocator;
        _ = self;
    }
};

/// Programmable move call
pub const ProgrammableMoveCall = struct {
    /// Package address
    package: SuiAddress,
    /// Module name
    module: []const u8,
    /// Function name
    function: []const u8,
    /// Type arguments
    type_arguments: []const MoveTypeTag,
    /// Arguments
    arguments: []const TransactionArgument,

    pub fn deinit(self: *ProgrammableMoveCall, allocator: std.mem.Allocator) void {
        allocator.free(self.module);
        allocator.free(self.function);
        for (self.type_arguments) |*ta| {
            ta.deinit(allocator);
        }
        allocator.free(self.type_arguments);
        for (self.arguments) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.arguments);
    }

    /// Serialize to BCS
    pub fn serialize(self: ProgrammableMoveCall, serializer: *BcsSerializer) !void {
        try serializer.buffer.appendSlice(&self.package);
        try serializer.writeBytes(self.module);
        try serializer.writeBytes(self.function);
        try serializer.writeUleb128(@intCast(self.type_arguments.len));
        for (self.type_arguments) |ta| {
            try ta.serialize(serializer);
        }
        try serializer.writeUleb128(@intCast(self.arguments.len));
        for (self.arguments) |arg| {
            try arg.serialize(serializer);
        }
    }
};

/// Programmable transaction command
pub const Command = union(enum) {
    move_call: ProgrammableMoveCall,
    transfer_objects: struct {
        objects: []const TransactionArgument,
        address: TransactionArgument,
    },
    split_coins: struct {
        coin: TransactionArgument,
        amounts: []const TransactionArgument,
    },
    merge_coins: struct {
        destination: TransactionArgument,
        sources: []const TransactionArgument,
    },
    publish: struct {
        modules: []const []const u8,
        dependencies: []const SuiAddress,
    },
    make_move_vec: struct {
        type: ?MoveTypeTag,
        elements: []const TransactionArgument,
    },
    upgrade: struct {
        modules: []const []const u8,
        dependencies: []const SuiAddress,
        package: SuiAddress,
        ticket: TransactionArgument,
    },

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .move_call => |*mc| mc.deinit(allocator),
            .transfer_objects => |tr| {
                for (tr.objects) |*o| o.deinit(allocator);
                allocator.free(tr.objects);
                tr.address.deinit(allocator);
            },
            .split_coins => |sc| {
                sc.coin.deinit(allocator);
                for (sc.amounts) |*a| a.deinit(allocator);
                allocator.free(sc.amounts);
            },
            .merge_coins => |mc| {
                mc.destination.deinit(allocator);
                for (mc.sources) |*s| s.deinit(allocator);
                allocator.free(mc.sources);
            },
            .publish => |p| {
                for (p.modules) |m| allocator.free(m);
                allocator.free(p.modules);
                allocator.free(p.dependencies);
            },
            .make_move_vec => |mv| {
                if (mv.type) |*t| t.deinit(allocator);
                for (mv.elements) |*e| e.deinit(allocator);
                allocator.free(mv.elements);
            },
            .upgrade => |u| {
                for (u.modules) |m| allocator.free(m);
                allocator.free(u.modules);
                allocator.free(u.dependencies);
                u.ticket.deinit(allocator);
            },
        }
    }
};

/// Programmable transaction
pub const ProgrammableTransaction = struct {
    /// Inputs
    inputs: []const CallArgument,
    /// Commands
    commands: []const Command,

    pub fn deinit(self: *ProgrammableTransaction, allocator: std.mem.Allocator) void {
        for (self.inputs) |*input| {
            input.deinit(allocator);
        }
        allocator.free(self.inputs);
        for (self.commands) |*cmd| {
            cmd.deinit(allocator);
        }
        allocator.free(self.commands);
    }

    /// Serialize to BCS
    pub fn serialize(self: ProgrammableTransaction, serializer: *BcsSerializer) !void {
        try serializer.writeUleb128(@intCast(self.inputs.len));
        for (self.inputs) |input| {
            switch (input) {
                .pure => |p| {
                    try serializer.writeU8(0);
                    try serializer.writeBytes(p);
                },
                .object => |o| {
                    try serializer.writeU8(1);
                    switch (o) {
                        .immortal => |r| {
                            try serializer.writeU8(0);
                            try r.serialize(serializer);
                        },
                        .shared => |r| {
                            try serializer.writeU8(1);
                            try r.serialize(serializer);
                        },
                        .receiving => |r| {
                            try serializer.writeU8(2);
                            try r.serialize(serializer);
                        },
                    }
                },
            }
        }
        try serializer.writeUleb128(@intCast(self.commands.len));
        // Command serialization would go here
    }
};

// ============================================================
// Tests
// ============================================================

test "BcsSerializer basic types" {
    const testing = std.testing;
    var serializer = BcsSerializer.init(testing.allocator);
    defer serializer.deinit();

    try serializer.writeU8(42);
    try serializer.writeU16(1000);
    try serializer.writeU32(100000);
    try serializer.writeU64(10000000000);
    try serializer.writeBool(true);

    const bytes = serializer.getBytes();
    try testing.expect(bytes.len > 0);
}

test "BcsSerializer writeBytes" {
    const testing = std.testing;
    var serializer = BcsSerializer.init(testing.allocator);
    defer serializer.deinit();

    try serializer.writeBytes("hello");

    const bytes = serializer.getBytes();
    try testing.expect(bytes.len == 6); // 1 byte length + 5 bytes data
}

test "MoveTypeTag serialization" {
    const testing = std.testing;
    var serializer = BcsSerializer.init(testing.allocator);
    defer serializer.deinit();

    const tag = MoveTypeTag{ .u64 = {} };
    try tag.serialize(&serializer);

    const bytes = serializer.getBytes();
    try testing.expectEqual(@as(u8, 4), bytes[0]);
}

test "ObjectRef serialization" {
    const testing = std.testing;
    var serializer = BcsSerializer.init(testing.allocator);
    defer serializer.deinit();

    const obj_ref = ObjectRef{
        .object_id = [_]u8{1} ** 32,
        .version = 5,
        .digest = [_]u8{2} ** 32,
    };
    try obj_ref.serialize(&serializer);

    const bytes = serializer.getBytes();
    try testing.expectEqual(@as(usize, 72), bytes.len); // 32 + 8 + 32
}

test "SharedObjectRef serialization" {
    const testing = std.testing;
    var serializer = BcsSerializer.init(testing.allocator);
    defer serializer.deinit();

    const shared = SharedObjectRef{
        .object_id = [_]u8{1} ** 32,
        .initial_shared_version = 1,
        .mutable = true,
    };
    try shared.serialize(&serializer);

    const bytes = serializer.getBytes();
    try testing.expect(bytes.len > 0);
}

test "SuiAddress type" {
    const testing = std.testing;
    const addr: SuiAddress = [_]u8{0} ** 32;
    try testing.expectEqual(@as(usize, 32), addr.len);
}

test "ObjectID type" {
    const testing = std.testing;
    const id: ObjectID = [_]u8{1} ** 32;
    try testing.expectEqual(@as(usize, 32), id.len);
}

test "TransactionArgument pure" {
    const testing = std.testing;
    var serializer = BcsSerializer.init(testing.allocator);
    defer serializer.deinit();

    const arg = TransactionArgument{ .pure = "test" };
    try arg.serialize(&serializer);

    const bytes = serializer.getBytes();
    try testing.expectEqual(@as(u8, 0), bytes[0]);
}

test "MoveStructTag lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var tag = MoveStructTag{
        .address = [_]u8{0} ** 32,
        .module = try allocator.dupe(u8, "sui"),
        .name = try allocator.dupe(u8, "SUI"),
        .type_args = try allocator.alloc(MoveTypeTag, 0),
    };
    defer tag.deinit(allocator);

    try testing.expectEqualStrings("sui", tag.module);
}

test "ProgrammableMoveCall lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var call = ProgrammableMoveCall{
        .package = [_]u8{0} ** 32,
        .module = try allocator.dupe(u8, "coin"),
        .function = try allocator.dupe(u8, "transfer"),
        .type_arguments = try allocator.alloc(MoveTypeTag, 0),
        .arguments = try allocator.alloc(TransactionArgument, 0),
    };
    defer call.deinit(allocator);

    try testing.expectEqualStrings("coin", call.module);
}

test "Command transfer_objects" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var cmd = Command{
        .transfer_objects = .{
            .objects = try allocator.alloc(TransactionArgument, 1),
            .address = .{ .pure = "addr" },
        },
    };
    cmd.transfer_objects.objects[0] = .{ .pure = "obj" };
    defer cmd.deinit(allocator);

    try testing.expect(cmd == .transfer_objects);
}
