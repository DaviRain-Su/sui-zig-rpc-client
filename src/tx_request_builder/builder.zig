/// tx_request_builder/builder.zig - Transaction building logic
const std = @import("std");
const types = @import("types.zig");
const argument = @import("argument.zig");

const ProgrammaticArtifactKind = types.ProgrammaticArtifactKind;
const CommandRequestConfig = types.CommandRequestConfig;
const ArgumentValue = argument.ArgumentValue;
const PtbArgumentSpec = argument.PtbArgumentSpec;

/// Transaction instruction
pub const TransactionInstruction = struct {
    /// Instruction kind
    kind: InstructionKind,
    /// Arguments
    arguments: []const PtbArgumentSpec,
    /// Type arguments (for move_call)
    type_arguments: []const []const u8 = &.{},

    pub fn deinit(self: *TransactionInstruction, allocator: std.mem.Allocator) void {
        for (self.arguments) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.arguments);
        for (self.type_arguments) |ta| {
            allocator.free(ta);
        }
        allocator.free(self.type_arguments);
    }
};

/// Instruction kind
pub const InstructionKind = union(enum) {
    /// Move call
    move_call: MoveCallInstruction,
    /// Transfer objects
    transfer_objects: TransferObjectsInstruction,
    /// Split coins
    split_coins: SplitCoinsInstruction,
    /// Merge coins
    merge_coins: MergeCoinsInstruction,
    /// Publish package
    publish: PublishInstruction,
    /// Upgrade package
    upgrade: UpgradeInstruction,
    /// Make Move vector
    make_move_vec: MakeMoveVecInstruction,

    pub fn deinit(self: *InstructionKind, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .move_call => |*m| m.deinit(allocator),
            else => {},
        }
    }
};

/// Move call instruction
pub const MoveCallInstruction = struct {
    /// Package address
    package: []const u8,
    /// Module name
    module: []const u8,
    /// Function name
    function: []const u8,

    pub fn deinit(self: *MoveCallInstruction, allocator: std.mem.Allocator) void {
        allocator.free(self.package);
        allocator.free(self.module);
        allocator.free(self.function);
    }
};

/// Transfer objects instruction
pub const TransferObjectsInstruction = struct {
    /// Objects to transfer
    objects: []const PtbArgumentSpec,
    /// Recipient address
    recipient: PtbArgumentSpec,

    pub fn deinit(self: *TransferObjectsInstruction, allocator: std.mem.Allocator) void {
        for (self.objects) |*o| o.deinit(allocator);
        allocator.free(self.objects);
        self.recipient.deinit(allocator);
    }
};

/// Split coins instruction
pub const SplitCoinsInstruction = struct {
    /// Coin to split
    coin: PtbArgumentSpec,
    /// Amounts to split into
    amounts: []const PtbArgumentSpec,

    pub fn deinit(self: *SplitCoinsInstruction, allocator: std.mem.Allocator) void {
        self.coin.deinit(allocator);
        for (self.amounts) |*a| a.deinit(allocator);
        allocator.free(self.amounts);
    }
};

/// Merge coins instruction
pub const MergeCoinsInstruction = struct {
    /// Destination coin
    destination: PtbArgumentSpec,
    /// Source coins to merge
    sources: []const PtbArgumentSpec,

    pub fn deinit(self: *MergeCoinsInstruction, allocator: std.mem.Allocator) void {
        self.destination.deinit(allocator);
        for (self.sources) |*s| s.deinit(allocator);
        allocator.free(self.sources);
    }
};

/// Publish instruction
pub const PublishInstruction = struct {
    /// Package bytes
    package_bytes: []const u8,
    /// Dependencies
    dependencies: []const []const u8,

    pub fn deinit(self: *PublishInstruction, allocator: std.mem.Allocator) void {
        allocator.free(self.package_bytes);
        for (self.dependencies) |d| allocator.free(d);
        allocator.free(self.dependencies);
    }
};

/// Upgrade instruction
pub const UpgradeInstruction = struct {
    /// Package bytes
    package_bytes: []const u8,
    /// Dependencies
    dependencies: []const []const u8,
    /// Package to upgrade
    package_id: []const u8,
    /// Upgrade ticket
    upgrade_ticket: PtbArgumentSpec,

    pub fn deinit(self: *UpgradeInstruction, allocator: std.mem.Allocator) void {
        allocator.free(self.package_bytes);
        for (self.dependencies) |d| allocator.free(d);
        allocator.free(self.dependencies);
        allocator.free(self.package_id);
        self.upgrade_ticket.deinit(allocator);
    }
};

/// Make Move vector instruction
pub const MakeMoveVecInstruction = struct {
    /// Element type
    element_type: []const u8,
    /// Elements
    elements: []const PtbArgumentSpec,

    pub fn deinit(self: *MakeMoveVecInstruction, allocator: std.mem.Allocator) void {
        allocator.free(self.element_type);
        for (self.elements) |*e| e.deinit(allocator);
        allocator.free(self.elements);
    }
};

/// Transaction block
pub const TransactionBlock = struct {
    /// Instructions
    instructions: []const TransactionInstruction,
    /// Sender (optional)
    sender: ?[]const u8 = null,
    /// Gas budget
    gas_budget: ?u64 = null,
    /// Gas price
    gas_price: ?u64 = null,

    pub fn deinit(self: *TransactionBlock, allocator: std.mem.Allocator) void {
        for (self.instructions) |*i| i.deinit(allocator);
        allocator.free(self.instructions);
        if (self.sender) |s| allocator.free(s);
    }
};

/// Build transaction block from command source
pub fn buildTransactionBlockFromCommandSource(
    allocator: std.mem.Allocator,
    config: CommandRequestConfig,
) !TransactionBlock {
    // Parse command type and build appropriate instruction
    const instruction = try buildInstructionFromConfig(allocator, config);

    const instructions = try allocator.alloc(TransactionInstruction, 1);
    instructions[0] = instruction;

    return TransactionBlock{
        .instructions = instructions,
        .gas_budget = null,
    };
}

/// Build instruction from config
fn buildInstructionFromConfig(
    allocator: std.mem.Allocator,
    config: CommandRequestConfig,
) !TransactionInstruction {
    if (std.mem.eql(u8, config.command_type, "move_call")) {
        return try buildMoveCallInstruction(allocator, config);
    } else if (std.mem.eql(u8, config.command_type, "transfer")) {
        return try buildTransferInstruction(allocator, config);
    } else {
        return error.UnsupportedCommandType;
    }
}

/// Build Move call instruction
fn buildMoveCallInstruction(
    allocator: std.mem.Allocator,
    config: CommandRequestConfig,
) !TransactionInstruction {
    // Extract package, module, function from parameters
    const package_val = config.parameters.object.get("package") orelse
        return error.MissingPackage;
    const module_val = config.parameters.object.get("module") orelse
        return error.MissingModule;
    const function_val = config.parameters.object.get("function") orelse
        return error.MissingFunction;

    const package_str = try allocator.dupe(u8, package_val.string);
    errdefer allocator.free(package_str);

    const module_str = try allocator.dupe(u8, module_val.string);
    errdefer allocator.free(module_str);

    const function_str = try allocator.dupe(u8, function_val.string);
    errdefer allocator.free(function_str);

    const move_call = MoveCallInstruction{
        .package = package_str,
        .module = module_str,
        .function = function_str,
    };

    // Parse arguments
    var arguments_list = std.ArrayList(PtbArgumentSpec).init(allocator);
    errdefer {
        for (arguments_list.items) |*a| a.deinit(allocator);
        arguments_list.deinit();
    }

    if (config.parameters.object.get("arguments")) |args| {
        if (args == .array) {
            for (args.array.items) |arg| {
                const spec = try parseArgumentSpec(allocator, arg);
                try arguments_list.append(spec);
            }
        }
    }

    // Parse type arguments
    var type_args_list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (type_args_list.items) |ta| allocator.free(ta);
        type_args_list.deinit();
    }

    if (config.parameters.object.get("type_arguments")) |type_args| {
        if (type_args == .array) {
            for (type_args.array.items) |ta| {
                const type_str = try allocator.dupe(u8, ta.string);
                try type_args_list.append(type_str);
            }
        }
    }

    return TransactionInstruction{
        .kind = .{ .move_call = move_call },
        .arguments = try arguments_list.toOwnedSlice(),
        .type_arguments = try type_args_list.toOwnedSlice(),
    };
}

/// Build transfer instruction
///
/// NOTE: This function is not yet fully implemented. The current implementation
/// only supports basic Move call instructions. Full transfer instruction support
/// would require:
///
/// 1. Parsing recipient address from config.parameters
/// 2. Parsing objects to transfer (object IDs or GasCoin)
/// 3. Creating TransferObjectsInstruction with proper arguments
/// 4. Handling different transfer scenarios (SUI, objects, batch)
///
/// For now, use move_call instructions with 0x2::sui::transfer for transfers.
fn buildTransferInstruction(
    allocator: std.mem.Allocator,
    config: CommandRequestConfig,
) !TransactionInstruction {
    _ = allocator;
    _ = config;
    // TODO: Implement full transfer instruction building
    // This requires parsing recipient and objects from parameters
    return error.NotImplemented;
}

/// Parse argument specification from JSON
fn parseArgumentSpec(allocator: std.mem.Allocator, value: std.json.Value) !PtbArgumentSpec {
    if (value == .integer) {
        return .{ .input = @intCast(value.integer) };
    } else if (value == .string) {
        const str = try allocator.dupe(u8, value.string);
        return .{ .pure = str };
    } else if (value == .object) {
        // Handle object references, results, etc.
        if (value.object.get("gas")) |_| {
            return .gas;
        }
    }
    return .{ .gas = {} };
}

/// Build artifact from transaction block
pub fn buildArtifact(
    allocator: std.mem.Allocator,
    block: TransactionBlock,
    kind: ProgrammaticArtifactKind,
) ![]u8 {
    return switch (kind) {
        .transaction_block => try buildTransactionBlockBytes(allocator, block),
        else => error.UnsupportedArtifactKind,
    };
}

/// Build transaction block bytes (simplified)
fn buildTransactionBlockBytes(allocator: std.mem.Allocator, block: TransactionBlock) ![]u8 {
    _ = block;
    // Simplified - would actually serialize to BCS
    return try allocator.dupe(u8, "transaction_block_bytes");
}

// ============================================================
// Tests
// ============================================================

test "TransactionInstruction lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try allocator.alloc(PtbArgumentSpec, 1);
    args[0] = .{ .gas = {} };

    var instruction = TransactionInstruction{
        .kind = .{ .make_move_vec = .{
            .element_type = try allocator.dupe(u8, "u64"),
            .elements = args,
        } },
        .arguments = &.{},
    };
    defer instruction.deinit(allocator);

    try testing.expectEqual(InstructionKind.make_move_vec, instruction.kind);
}

test "MoveCallInstruction lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var move_call = MoveCallInstruction{
        .package = try allocator.dupe(u8, "0x2"),
        .module = try allocator.dupe(u8, "sui"),
        .function = try allocator.dupe(u8, "transfer"),
    };
    defer move_call.deinit(allocator);

    try testing.expectEqualStrings("0x2", move_call.package);
    try testing.expectEqualStrings("sui", move_call.module);
}

test "TransactionBlock lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const instructions = try allocator.alloc(TransactionInstruction, 1);
    instructions[0] = TransactionInstruction{
        .kind = .{ .make_move_vec = .{
            .element_type = try allocator.dupe(u8, "u64"),
            .elements = &.{},
        } },
        .arguments = &.{},
    };

    var block = TransactionBlock{
        .instructions = instructions,
        .sender = try allocator.dupe(u8, "0x123"),
        .gas_budget = 1000000,
    };
    defer block.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), block.instructions.len);
    try testing.expectEqual(@as(?u64, 1000000), block.gas_budget);
}

test "buildTransactionBlockFromCommandSource with move_call" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("package", .{ .string = "0x2" });
    try params.put("module", .{ .string = "sui" });
    try params.put("function", .{ .string = "transfer" });

    const config = CommandRequestConfig{
        .command_type = try allocator.dupe(u8, "move_call"),
        .parameters = .{ .object = params },
    };
    defer config.deinit(allocator);

    var block = try buildTransactionBlockFromCommandSource(allocator, config);
    defer block.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), block.instructions.len);
}

test "buildArtifact transaction_block" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const instructions = try allocator.alloc(TransactionInstruction, 0);

    const block = TransactionBlock{
        .instructions = instructions,
    };
    defer allocator.free(instructions);

    const artifact = try buildArtifact(allocator, block, .transaction_block);
    defer allocator.free(artifact);

    try testing.expectEqualStrings("transaction_block_bytes", artifact);
}

test "parseArgumentSpec with integer" {
    const testing = std.testing;

    const spec = try parseArgumentSpec(testing.allocator, .{ .integer = 5 });
    defer spec.deinit(testing.allocator);

    try testing.expectEqual(@as(u16, 5), spec.input);
}

test "parseArgumentSpec with string" {
    const testing = std.testing;

    const spec = try parseArgumentSpec(testing.allocator, .{ .string = "value" });
    defer spec.deinit(testing.allocator);

    try testing.expectEqualStrings("value", spec.pure);
}

test "parseArgumentSpec with gas" {
    const testing = std.testing;

    var obj = std.json.ObjectMap.init(testing.allocator);
    defer obj.deinit();
    try obj.put("gas", .{ .bool = true });

    const spec = try parseArgumentSpec(testing.allocator, .{ .object = obj });
    // Note: gas object is consumed by parseArgumentSpec

    try testing.expectEqual(PtbArgumentSpec.gas, spec);
}

test "InstructionKind deinit" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var kind = InstructionKind{
        .move_call = .{
            .package = try allocator.dupe(u8, "0x2"),
            .module = try allocator.dupe(u8, "sui"),
            .function = try allocator.dupe(u8, "transfer"),
        },
    };
    defer kind.deinit(allocator);

    try testing.expectEqualStrings("0x2", kind.move_call.package);
}

test "SplitCoinsInstruction lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const amounts = try allocator.alloc(PtbArgumentSpec, 2);
    amounts[0] = .{ .input = 0 };
    amounts[1] = .{ .input = 1 };

    var split = SplitCoinsInstruction{
        .coin = .{ .gas = {} },
        .amounts = amounts,
    };
    defer split.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), split.amounts.len);
}

test "MergeCoinsInstruction lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sources = try allocator.alloc(PtbArgumentSpec, 2);
    sources[0] = .{ .input = 0 };
    sources[1] = .{ .input = 1 };

    var merge = MergeCoinsInstruction{
        .destination = .{ .gas = {} },
        .sources = sources,
    };
    defer merge.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), merge.sources.len);
}
