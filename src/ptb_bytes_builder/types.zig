/// ptb_bytes_builder/types.zig - Core types for PTB byte building
const std = @import("std");

/// Sui address (32 bytes)
pub const Address = [32]u8;

/// Object digest (32 bytes)
pub const ObjectDigest = [32]u8;

/// Object reference
pub const ObjectRef = struct {
    object_id: Address,
    version: u64,
    digest: ObjectDigest,
};

/// Shared object reference
pub const SharedObjectRef = struct {
    object_id: Address,
    initial_shared_version: u64,
    mutable: bool,
};

/// Object argument for commands
pub const ObjectArg = union(enum) {
    /// Immortal object (shared or immutable)
    immortal: SharedObjectRef,
    /// Owned object
    receiving: ObjectRef,
};

/// Call argument for commands
pub const CallArg = union(enum) {
    /// Pure value (BCS encoded)
    pure: []const u8,
    /// Object argument
    object: ObjectArg,
};

/// Nested result reference
pub const NestedResult = struct {
    command_index: u16,
    result_index: u16,
};

/// Command argument
pub const Argument = union(enum) {
    /// Gas coin
    gas,
    /// Input parameter
    input: u16,
    /// Result of previous command
    result: u16,
    /// Nested result
    nested_result: NestedResult,
};

/// Struct tag for type specification
pub const StructTag = struct {
    address: Address,
    module: []const u8,
    name: []const u8,
    type_params: []const TypeTag,

    pub fn deinit(self: *StructTag, allocator: std.mem.Allocator) void {
        allocator.free(self.module);
        allocator.free(self.name);
        for (self.type_params) |*tp| tp.deinit(allocator);
        allocator.free(self.type_params);
    }
};

/// Type tag for type specification
pub const TypeTag = union(enum) {
    bool,
    u8,
    u16,
    u32,
    u64,
    u128,
    u256,
    address,
    signer,
    vector: *TypeTag,
    struct_tag: StructTag,
    type_param: u16,

    pub fn deinit(self: *TypeTag, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .vector => |v| {
                v.deinit(allocator);
                allocator.destroy(v);
            },
            .struct_tag => |*s| s.deinit(allocator),
            else => {},
        }
    }
};

/// Move call command
pub const MoveCallCommand = struct {
    package: Address,
    module: []const u8,
    function: []const u8,
    type_arguments: []const TypeTag,
    arguments: []const Argument,

    pub fn deinit(self: *MoveCallCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.module);
        allocator.free(self.function);
        for (self.type_arguments) |*ta| ta.deinit(allocator);
        allocator.free(self.type_arguments);
        allocator.free(self.arguments);
    }
};

/// Transfer objects command
pub const TransferObjectsCommand = struct {
    objects: []const Argument,
    address: Argument,

    pub fn deinit(self: *TransferObjectsCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.objects);
    }
};

/// Split coins command
pub const SplitCoinsCommand = struct {
    coin: Argument,
    amounts: []const Argument,

    pub fn deinit(self: *SplitCoinsCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.amounts);
    }
};

/// Merge coins command
pub const MergeCoinsCommand = struct {
    destination: Argument,
    sources: []const Argument,

    pub fn deinit(self: *MergeCoinsCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.sources);
    }
};

/// Publish command
pub const PublishCommand = struct {
    modules: []const []const u8,
    dependencies: []const Address,

    pub fn deinit(self: *PublishCommand, allocator: std.mem.Allocator) void {
        for (self.modules) |m| allocator.free(m);
        allocator.free(self.modules);
        allocator.free(self.dependencies);
    }
};

/// Make Move vector command
pub const MakeMoveVecCommand = struct {
    type: ?TypeTag,
    elements: []const Argument,

    pub fn deinit(self: *MakeMoveVecCommand, allocator: std.mem.Allocator) void {
        if (self.type) |*t| t.deinit(allocator);
        allocator.free(self.elements);
    }
};

/// Upgrade command
pub const UpgradeCommand = struct {
    modules: []const []const u8,
    dependencies: []const Address,
    package: Address,
    ticket: Argument,

    pub fn deinit(self: *UpgradeCommand, allocator: std.mem.Allocator) void {
        for (self.modules) |m| allocator.free(m);
        allocator.free(self.modules);
        allocator.free(self.dependencies);
    }
};

/// Command union
pub const Command = union(enum) {
    move_call: MoveCallCommand,
    transfer_objects: TransferObjectsCommand,
    split_coins: SplitCoinsCommand,
    merge_coins: MergeCoinsCommand,
    publish: PublishCommand,
    make_move_vec: MakeMoveVecCommand,
    upgrade: UpgradeCommand,

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .move_call => |*m| m.deinit(allocator),
            .transfer_objects => |*t| t.deinit(allocator),
            .split_coins => |*s| s.deinit(allocator),
            .merge_coins => |*m| m.deinit(allocator),
            .publish => |*p| p.deinit(allocator),
            .make_move_vec => |*m| m.deinit(allocator),
            .upgrade => |*u| u.deinit(allocator),
        }
    }
};

/// Programmable transaction
pub const ProgrammableTransaction = struct {
    inputs: []const CallArg,
    commands: []const Command,

    pub fn deinit(self: *ProgrammableTransaction, allocator: std.mem.Allocator) void {
        for (self.inputs) |*input| {
            switch (input.*) {
                .pure => |p| allocator.free(p),
                else => {},
            }
        }
        allocator.free(self.inputs);
        for (self.commands) |*cmd| cmd.deinit(allocator);
        allocator.free(self.commands);
    }
};

/// Gas data
pub const GasData = struct {
    payment: []const ObjectRef,
    owner: Address,
    price: u64,
    budget: u64,

    pub fn deinit(self: *GasData, allocator: std.mem.Allocator) void {
        allocator.free(self.payment);
    }
};

/// Transaction expiration
pub const TransactionExpiration = union(enum) {
    none,
    epoch: u64,
};

/// Transaction data V1
pub const TransactionDataV1 = struct {
    kind: ProgrammableTransaction,
    sender: Address,
    gas_data: GasData,
    expiration: TransactionExpiration,

    pub fn deinit(self: *TransactionDataV1, allocator: std.mem.Allocator) void {
        self.kind.deinit(allocator);
        self.gas_data.deinit(allocator);
    }
};

// ============================================================
// Tests
// ============================================================

test "Address type" {
    const testing = std.testing;
    const addr: Address = [_]u8{0} ** 32;
    try testing.expectEqual(@as(usize, 32), addr.len);
}

test "ObjectRef structure" {
    const testing = std.testing;
    const obj_ref = ObjectRef{
        .object_id = [_]u8{1} ** 32,
        .version = 1,
        .digest = [_]u8{2} ** 32,
    };
    try testing.expectEqual(@as(u64, 1), obj_ref.version);
}

test "Argument union" {
    const testing = std.testing;
    const arg = Argument{ .gas = {} };
    try testing.expect(arg == .gas);
}

test "TypeTag lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tag = TypeTag{ .u64 = {} };
    defer tag.deinit(allocator);

    try testing.expect(tag == .u64);
}

test "StructTag lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tag = StructTag{
        .address = [_]u8{0} ** 32,
        .module = try allocator.dupe(u8, "sui"),
        .name = try allocator.dupe(u8, "SUI"),
        .type_params = try allocator.alloc(TypeTag, 0),
    };
    defer tag.deinit(allocator);

    try testing.expectEqualStrings("sui", tag.module);
}

test "MoveCallCommand lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cmd = MoveCallCommand{
        .package = [_]u8{0} ** 32,
        .module = try allocator.dupe(u8, "coin"),
        .function = try allocator.dupe(u8, "transfer"),
        .type_arguments = try allocator.alloc(TypeTag, 0),
        .arguments = try allocator.alloc(Argument, 0),
    };
    defer cmd.deinit(allocator);

    try testing.expectEqualStrings("coin", cmd.module);
}

test "Command union lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cmd = Command{
        .transfer_objects = .{
            .objects = try allocator.alloc(Argument, 1),
            .address = .{ .gas = {} },
        },
    };
    cmd.transfer_objects.objects[0] = .{ .gas = {} };
    defer cmd.deinit(allocator);

    try testing.expect(cmd == .transfer_objects);
}

test "ProgrammableTransaction lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pt = ProgrammableTransaction{
        .inputs = try allocator.alloc(CallArg, 0),
        .commands = try allocator.alloc(Command, 0),
    };
    defer pt.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), pt.inputs.len);
}

test "GasData lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gas = GasData{
        .payment = try allocator.alloc(ObjectRef, 1),
        .owner = [_]u8{0} ** 32,
        .price = 1000,
        .budget = 1000000,
    };
    defer gas.deinit(allocator);

    try testing.expectEqual(@as(u64, 1000), gas.price);
}

test "TransactionDataV1 lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tx = TransactionDataV1{
        .kind = .{
            .inputs = try allocator.alloc(CallArg, 0),
            .commands = try allocator.alloc(Command, 0),
        },
        .sender = [_]u8{0} ** 32,
        .gas_data = .{
            .payment = try allocator.alloc(ObjectRef, 0),
            .owner = [_]u8{0} ** 32,
            .price = 1000,
            .budget = 1000000,
        },
        .expiration = .{ .epoch = 100 },
    };
    defer tx.deinit(allocator);

    try testing.expect(tx.expiration == .epoch);
}

test "NestedResult structure" {
    const testing = std.testing;
    const nested = NestedResult{
        .command_index = 5,
        .result_index = 2,
    };
    try testing.expectEqual(@as(u16, 5), nested.command_index);
    try testing.expectEqual(@as(u16, 2), nested.result_index);
}

test "SharedObjectRef structure" {
    const testing = std.testing;
    const shared = SharedObjectRef{
        .object_id = [_]u8{1} ** 32,
        .initial_shared_version = 1,
        .mutable = true,
    };
    try testing.expect(shared.mutable);
}
