const std = @import("std");

pub const Address = [32]u8;
pub const ObjectDigest = [32]u8;

pub const ObjectRef = struct {
    object_id: Address,
    version: u64,
    digest: ObjectDigest,
};

pub const SharedObjectRef = struct {
    object_id: Address,
    initial_shared_version: u64,
    mutable: bool,
};

pub const ObjectArg = union(enum) {
    imm_or_owned_object: ObjectRef,
    shared_object: SharedObjectRef,
    receiving: ObjectRef,
};

pub const CallArg = union(enum) {
    pure: []const u8,
    object: ObjectArg,
};

pub const NestedResult = struct {
    command_index: u16,
    result_index: u16,
};

pub const Argument = union(enum) {
    gas_coin,
    input: u16,
    result: u16,
    nested_result: NestedResult,
};

pub const StructTag = struct {
    address: Address,
    module: []const u8,
    name: []const u8,
    type_params: []const TypeTag = &.{},
};

pub const TypeTag = union(enum) {
    bool,
    u8,
    u64,
    u128,
    address,
    signer,
    vector: *const TypeTag,
    struct_: StructTag,
    u16,
    u32,
    u256,
};

pub const MoveCallCommand = struct {
    package: Address,
    module: []const u8,
    function_name: []const u8,
    type_arguments: []const TypeTag = &.{},
    arguments: []const Argument = &.{},
};

pub const TransferObjectsCommand = struct {
    objects: []const Argument,
    address: Argument,
};

pub const SplitCoinsCommand = struct {
    coin: Argument,
    amounts: []const Argument,
};

pub const MergeCoinsCommand = struct {
    destination: Argument,
    sources: []const Argument,
};

pub const PublishCommand = struct {
    modules: []const []const u8,
    dependencies: []const Address,
};

pub const MakeMoveVecCommand = struct {
    type_: ?*const TypeTag = null,
    elements: []const Argument,
};

pub const UpgradeCommand = struct {
    modules: []const []const u8,
    dependencies: []const Address,
    package: Address,
    ticket: Argument,
};

pub const Command = union(enum) {
    move_call: MoveCallCommand,
    transfer_objects: TransferObjectsCommand,
    split_coins: SplitCoinsCommand,
    merge_coins: MergeCoinsCommand,
    publish: PublishCommand,
    make_move_vec: MakeMoveVecCommand,
    upgrade: UpgradeCommand,
};

pub const ProgrammableTransaction = struct {
    inputs: []const CallArg = &.{},
    commands: []const Command = &.{},
};

pub const GasData = struct {
    payment: []const ObjectRef,
    owner: Address,
    price: u64,
    budget: u64,
};

pub const TransactionExpiration = union(enum) {
    none,
    epoch: u64,
};

pub const TransactionDataV1 = struct {
    programmable_transaction: ProgrammableTransaction,
    sender: Address,
    gas_data: GasData,
    expiration: TransactionExpiration = .none,
};

fn appendVariantIndex(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: usize,
) !void {
    var remaining = value;
    while (true) {
        var byte: u8 = @intCast(remaining & 0x7f);
        remaining >>= 7;
        if (remaining != 0) byte |= 0x80;
        try out.append(allocator, byte);
        if (remaining == 0) return;
    }
}

fn appendBool(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: bool,
) !void {
    try out.append(allocator, if (value) 1 else 0);
}

fn appendU16(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u16,
) !void {
    var buffer: [2]u8 = undefined;
    std.mem.writeInt(u16, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn appendU32(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u32,
) !void {
    var buffer: [4]u8 = undefined;
    std.mem.writeInt(u32, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn appendU64(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u64,
) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn appendU128(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u128,
) !void {
    var buffer: [16]u8 = undefined;
    std.mem.writeInt(u128, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn appendU256(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u256,
) !void {
    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn appendBytes(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) !void {
    try appendVariantIndex(out, allocator, value.len);
    try out.appendSlice(allocator, value);
}

fn appendString(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) !void {
    try appendBytes(out, allocator, value);
}

fn appendAddress(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: Address,
) !void {
    try out.appendSlice(allocator, &value);
}

fn appendDigest(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: ObjectDigest,
) !void {
    // Sui keeps Digest BCS-compatible with a historical length prefix.
    try appendVariantIndex(out, allocator, 32);
    try out.appendSlice(allocator, &value);
}

fn encodeTypeTag(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    tag: TypeTag,
) anyerror!void {
    switch (tag) {
        .bool => try appendVariantIndex(out, allocator, 0),
        .u8 => try appendVariantIndex(out, allocator, 1),
        .u64 => try appendVariantIndex(out, allocator, 2),
        .u128 => try appendVariantIndex(out, allocator, 3),
        .address => try appendVariantIndex(out, allocator, 4),
        .signer => try appendVariantIndex(out, allocator, 5),
        .vector => |inner| {
            try appendVariantIndex(out, allocator, 6);
            try encodeTypeTag(out, allocator, inner.*);
        },
        .struct_ => |struct_tag| {
            try appendVariantIndex(out, allocator, 7);
            try encodeStructTag(out, allocator, struct_tag);
        },
        .u16 => try appendVariantIndex(out, allocator, 8),
        .u32 => try appendVariantIndex(out, allocator, 9),
        .u256 => try appendVariantIndex(out, allocator, 10),
    }
}

fn encodeStructTag(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    tag: StructTag,
) anyerror!void {
    try appendAddress(out, allocator, tag.address);
    try appendString(out, allocator, tag.module);
    try appendString(out, allocator, tag.name);
    try appendVariantIndex(out, allocator, tag.type_params.len);
    for (tag.type_params) |type_param| {
        try encodeTypeTag(out, allocator, type_param);
    }
}

fn encodeObjectRef(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    object_ref: ObjectRef,
) !void {
    try appendAddress(out, allocator, object_ref.object_id);
    try appendU64(out, allocator, object_ref.version);
    try appendDigest(out, allocator, object_ref.digest);
}

fn encodeObjectArg(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    object_arg: ObjectArg,
) !void {
    switch (object_arg) {
        .imm_or_owned_object => |object_ref| {
            try appendVariantIndex(out, allocator, 0);
            try encodeObjectRef(out, allocator, object_ref);
        },
        .shared_object => |shared_ref| {
            try appendVariantIndex(out, allocator, 1);
            try appendAddress(out, allocator, shared_ref.object_id);
            try appendU64(out, allocator, shared_ref.initial_shared_version);
            try appendBool(out, allocator, shared_ref.mutable);
        },
        .receiving => |object_ref| {
            try appendVariantIndex(out, allocator, 2);
            try encodeObjectRef(out, allocator, object_ref);
        },
    }
}

fn encodeCallArg(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    call_arg: CallArg,
) !void {
    switch (call_arg) {
        .pure => |bytes| {
            try appendVariantIndex(out, allocator, 0);
            try appendBytes(out, allocator, bytes);
        },
        .object => |object_arg| {
            try appendVariantIndex(out, allocator, 1);
            try encodeObjectArg(out, allocator, object_arg);
        },
    }
}

fn encodeArgument(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    argument: Argument,
) !void {
    switch (argument) {
        .gas_coin => try appendVariantIndex(out, allocator, 0),
        .input => |index| {
            try appendVariantIndex(out, allocator, 1);
            try appendU16(out, allocator, index);
        },
        .result => |index| {
            try appendVariantIndex(out, allocator, 2);
            try appendU16(out, allocator, index);
        },
        .nested_result => |nested| {
            try appendVariantIndex(out, allocator, 3);
            try appendU16(out, allocator, nested.command_index);
            try appendU16(out, allocator, nested.result_index);
        },
    }
}

fn encodeCommand(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    command: Command,
) !void {
    switch (command) {
        .move_call => |move_call| {
            try appendVariantIndex(out, allocator, 0);
            try appendAddress(out, allocator, move_call.package);
            try appendString(out, allocator, move_call.module);
            try appendString(out, allocator, move_call.function_name);
            try appendVariantIndex(out, allocator, move_call.type_arguments.len);
            for (move_call.type_arguments) |type_arg| try encodeTypeTag(out, allocator, type_arg);
            try appendVariantIndex(out, allocator, move_call.arguments.len);
            for (move_call.arguments) |argument| try encodeArgument(out, allocator, argument);
        },
        .transfer_objects => |transfer| {
            try appendVariantIndex(out, allocator, 1);
            try appendVariantIndex(out, allocator, transfer.objects.len);
            for (transfer.objects) |object_arg| try encodeArgument(out, allocator, object_arg);
            try encodeArgument(out, allocator, transfer.address);
        },
        .split_coins => |split| {
            try appendVariantIndex(out, allocator, 2);
            try encodeArgument(out, allocator, split.coin);
            try appendVariantIndex(out, allocator, split.amounts.len);
            for (split.amounts) |amount| try encodeArgument(out, allocator, amount);
        },
        .merge_coins => |merge| {
            try appendVariantIndex(out, allocator, 3);
            try encodeArgument(out, allocator, merge.destination);
            try appendVariantIndex(out, allocator, merge.sources.len);
            for (merge.sources) |source| try encodeArgument(out, allocator, source);
        },
        .publish => |publish| {
            try appendVariantIndex(out, allocator, 4);
            try appendVariantIndex(out, allocator, publish.modules.len);
            for (publish.modules) |module_bytes| try appendBytes(out, allocator, module_bytes);
            try appendVariantIndex(out, allocator, publish.dependencies.len);
            for (publish.dependencies) |dependency| try appendAddress(out, allocator, dependency);
        },
        .make_move_vec => |make_move_vec| {
            try appendVariantIndex(out, allocator, 5);
            if (make_move_vec.type_) |type_tag| {
                try out.append(allocator, 1);
                try encodeTypeTag(out, allocator, type_tag.*);
            } else {
                try out.append(allocator, 0);
            }
            try appendVariantIndex(out, allocator, make_move_vec.elements.len);
            for (make_move_vec.elements) |element| try encodeArgument(out, allocator, element);
        },
        .upgrade => |upgrade| {
            try appendVariantIndex(out, allocator, 6);
            try appendVariantIndex(out, allocator, upgrade.modules.len);
            for (upgrade.modules) |module_bytes| try appendBytes(out, allocator, module_bytes);
            try appendVariantIndex(out, allocator, upgrade.dependencies.len);
            for (upgrade.dependencies) |dependency| try appendAddress(out, allocator, dependency);
            try appendAddress(out, allocator, upgrade.package);
            try encodeArgument(out, allocator, upgrade.ticket);
        },
    }
}

fn encodeProgrammableTransaction(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    programmable_transaction: ProgrammableTransaction,
) !void {
    try appendVariantIndex(out, allocator, programmable_transaction.inputs.len);
    for (programmable_transaction.inputs) |input| try encodeCallArg(out, allocator, input);
    try appendVariantIndex(out, allocator, programmable_transaction.commands.len);
    for (programmable_transaction.commands) |command| try encodeCommand(out, allocator, command);
}

fn encodeGasData(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    gas_data: GasData,
) !void {
    try appendVariantIndex(out, allocator, gas_data.payment.len);
    for (gas_data.payment) |payment| try encodeObjectRef(out, allocator, payment);
    try appendAddress(out, allocator, gas_data.owner);
    try appendU64(out, allocator, gas_data.price);
    try appendU64(out, allocator, gas_data.budget);
}

fn encodeTransactionExpiration(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    expiration: TransactionExpiration,
) !void {
    switch (expiration) {
        .none => try appendVariantIndex(out, allocator, 0),
        .epoch => |epoch| {
            try appendVariantIndex(out, allocator, 1);
            try appendU64(out, allocator, epoch);
        },
    }
}

pub fn buildTransactionDataV1Bytes(
    allocator: std.mem.Allocator,
    transaction: TransactionDataV1,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    try appendVariantIndex(&out, allocator, 0);
    try appendVariantIndex(&out, allocator, 0);
    try encodeProgrammableTransaction(&out, allocator, transaction.programmable_transaction);
    try appendAddress(&out, allocator, transaction.sender);
    try encodeGasData(&out, allocator, transaction.gas_data);
    try encodeTransactionExpiration(&out, allocator, transaction.expiration);

    return try out.toOwnedSlice(allocator);
}

pub fn buildTransactionDataV1Base64(
    allocator: std.mem.Allocator,
    transaction: TransactionDataV1,
) ![]u8 {
    const bytes = try buildTransactionDataV1Bytes(allocator, transaction);
    defer allocator.free(bytes);

    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return encoded;
}

pub fn buildTransactionDataV1BytesFromParts(
    allocator: std.mem.Allocator,
    inputs_json: []const u8,
    commands_json: []const u8,
    sender: []const u8,
    gas_data_json: []const u8,
    expiration_json: ?[]const u8,
) ![]u8 {
    const parsed_inputs = try std.json.parseFromSlice(std.json.Value, allocator, inputs_json, .{});
    defer parsed_inputs.deinit();
    const inputs = try requireJsonArray(parsed_inputs.value);

    const parsed_commands = try std.json.parseFromSlice(std.json.Value, allocator, commands_json, .{});
    defer parsed_commands.deinit();
    const commands = try requireJsonArray(parsed_commands.value);

    const parsed_gas_data = try std.json.parseFromSlice(std.json.Value, allocator, gas_data_json, .{});
    defer parsed_gas_data.deinit();
    _ = try requireJsonObject(parsed_gas_data.value);

    var parsed_expiration: ?std.json.Parsed(std.json.Value) = null;
    defer if (parsed_expiration) |*value| value.deinit();
    const expiration_value = if (expiration_json) |raw| blk: {
        parsed_expiration = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{});
        break :blk parsed_expiration.?.value;
    } else null;

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    try appendVariantIndex(&out, allocator, 0);
    try appendVariantIndex(&out, allocator, 0);

    try appendVariantIndex(&out, allocator, inputs.items.len);
    for (inputs.items) |input| try encodeCallArgFromJson(&out, allocator, input);

    try appendVariantIndex(&out, allocator, commands.items.len);
    for (commands.items) |command| try encodeCommandFromJson(&out, allocator, command);

    try appendAddress(&out, allocator, try parseHexAddress32(sender));
    try encodeGasDataFromJson(&out, allocator, parsed_gas_data.value);
    try encodeExpirationFromJson(&out, allocator, expiration_value);

    return try out.toOwnedSlice(allocator);
}

pub fn buildTransactionDataV1Base64FromParts(
    allocator: std.mem.Allocator,
    inputs_json: []const u8,
    commands_json: []const u8,
    sender: []const u8,
    gas_data_json: []const u8,
    expiration_json: ?[]const u8,
) ![]u8 {
    const bytes = try buildTransactionDataV1BytesFromParts(
        allocator,
        inputs_json,
        commands_json,
        sender,
        gas_data_json,
        expiration_json,
    );
    defer allocator.free(bytes);

    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return encoded;
}

fn requireJsonObject(value: std.json.Value) !std.json.ObjectMap {
    if (value != .object) return error.InvalidCli;
    return value.object;
}

fn requireJsonArray(value: std.json.Value) !std.json.Array {
    if (value != .array) return error.InvalidCli;
    return value.array;
}

fn requireJsonField(object: std.json.ObjectMap, field_name: []const u8) !std.json.Value {
    return object.get(field_name) orelse error.InvalidCli;
}

fn parseUnsignedJsonValue(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => |integer| blk: {
            if (integer < 0) return error.InvalidCli;
            break :blk @intCast(integer);
        },
        .number_string => |digits| try std.fmt.parseInt(u64, digits, 10),
        .string => |digits| try std.fmt.parseInt(u64, digits, 10),
        else => error.InvalidCli,
    };
}

fn parseBoolJsonValue(value: std.json.Value) !bool {
    if (value != .bool) return error.InvalidCli;
    return value.bool;
}

fn parseStringJsonValue(value: std.json.Value) ![]const u8 {
    if (value != .string) return error.InvalidCli;
    return value.string;
}

fn parseHexBytesAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, value, " \n\r\t");
    const raw = if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X"))
        trimmed[2..]
    else
        trimmed;

    if (raw.len == 0) return error.InvalidCli;

    const byte_len = (raw.len + 1) / 2;
    const decoded = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(decoded);
    @memset(decoded, 0);

    var src_index: usize = 0;
    var dst_index: usize = 0;
    if (raw.len % 2 != 0) {
        decoded[0] = try decodeHexNibble(raw[0]);
        src_index = 1;
        dst_index = 1;
    }

    while (src_index < raw.len) : (src_index += 2) {
        const high = try decodeHexNibble(raw[src_index]);
        const low = try decodeHexNibble(raw[src_index + 1]);
        decoded[dst_index] = (high << 4) | low;
        dst_index += 1;
    }

    return decoded;
}

pub fn parseRawBytesJsonValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8 {
    switch (value) {
        .string => |raw| {
            if (std.mem.startsWith(u8, raw, "0x") or std.mem.startsWith(u8, raw, "0X")) {
                return try parseHexBytesAlloc(allocator, raw);
            }
            const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(raw) catch return error.InvalidCli;
            const decoded = try allocator.alloc(u8, decoded_len);
            errdefer allocator.free(decoded);
            std.base64.standard.Decoder.decode(decoded, raw) catch return error.InvalidCli;
            return decoded;
        },
        .array => |array| {
            const decoded = try allocator.alloc(u8, array.items.len);
            errdefer allocator.free(decoded);
            for (array.items, 0..) |entry, index| {
                const integer = try parseUnsignedJsonValue(entry);
                if (integer > std.math.maxInt(u8)) return error.InvalidCli;
                decoded[index] = @intCast(integer);
            }
            return decoded;
        },
        else => return error.InvalidCli,
    }
}

fn parseDigest32JsonValue(
    value: std.json.Value,
) !ObjectDigest {
    const raw = try parseStringJsonValue(value);
    if (std.mem.startsWith(u8, raw, "0x") or std.mem.startsWith(u8, raw, "0X")) {
        return try parseHexAddress32(raw);
    }

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(raw) catch return error.InvalidCli;
    if (decoded_len == 32) {
        var decoded: ObjectDigest = undefined;
        std.base64.standard.Decoder.decode(&decoded, raw) catch return error.InvalidCli;
        return decoded;
    }

    return try parseBase58Digest32(raw);
}

fn parseBase58Digit(ch: u8) ?u8 {
    return switch (ch) {
        '1'...'9' => ch - '1',
        'A'...'H' => ch - 'A' + 9,
        'J'...'N' => ch - 'J' + 17,
        'P'...'Z' => ch - 'P' + 22,
        'a'...'k' => ch - 'a' + 33,
        'm'...'z' => ch - 'm' + 44,
        else => null,
    };
}

fn parseBase58Digest32(raw: []const u8) !ObjectDigest {
    if (raw.len == 0) return error.InvalidCli;

    var leading_zeroes: usize = 0;
    while (leading_zeroes < raw.len and raw[leading_zeroes] == '1') : (leading_zeroes += 1) {}

    var scratch = [_]u8{0} ** 64;
    var used: usize = 0;

    for (raw[leading_zeroes..]) |ch| {
        var carry: u32 = parseBase58Digit(ch) orelse return error.InvalidCli;
        var consumed: usize = 0;
        var index: usize = scratch.len;
        while (index > 0 and (carry != 0 or consumed < used)) {
            index -= 1;
            carry += @as(u32, scratch[index]) * 58;
            scratch[index] = @intCast(carry & 0xff);
            carry >>= 8;
            consumed += 1;
        }
        if (carry != 0) return error.InvalidCli;
        used = consumed;
    }

    var first_nonzero: usize = scratch.len - used;
    while (first_nonzero < scratch.len and scratch[first_nonzero] == 0) : (first_nonzero += 1) {}

    const decoded_len = leading_zeroes + (scratch.len - first_nonzero);
    if (decoded_len != 32) return error.InvalidCli;

    var digest = [_]u8{0} ** 32;
    if (first_nonzero < scratch.len) {
        @memcpy(digest[leading_zeroes..], scratch[first_nonzero..]);
    }
    return digest;
}

pub fn encodeSimplifiedTypeTagFromString(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    name: []const u8,
) !void {
    const type_tag = parseSimplifiedTypeTag(allocator, name) catch return error.InvalidCli;
    defer deinitOwnedTypeTag(allocator, type_tag);
    try encodeTypeTag(out, allocator, type_tag);
}

fn deinitOwnedTypeTagSlice(
    allocator: std.mem.Allocator,
    tags: []const TypeTag,
) void {
    for (tags) |tag| deinitOwnedTypeTag(allocator, tag);
    if (tags.len != 0) allocator.free(tags);
}

fn deinitOwnedTypeTag(
    allocator: std.mem.Allocator,
    tag: TypeTag,
) void {
    switch (tag) {
        .vector => |inner| {
            deinitOwnedTypeTag(allocator, inner.*);
            allocator.destroy(inner);
        },
        .struct_ => |st| {
            allocator.free(st.module);
            allocator.free(st.name);
            deinitOwnedTypeTagSlice(allocator, st.type_params);
        },
        else => {},
    }
}

pub fn parseSimplifiedTypeTag(
    allocator: std.mem.Allocator,
    spec: []const u8,
) !TypeTag {
    const trimmed = std.mem.trim(u8, spec, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    if (std.mem.eql(u8, trimmed, "bool")) return .bool;
    if (std.mem.eql(u8, trimmed, "u8")) return .u8;
    if (std.mem.eql(u8, trimmed, "u64")) return .u64;
    if (std.mem.eql(u8, trimmed, "u128")) return .u128;
    if (std.mem.eql(u8, trimmed, "address")) return .address;
    if (std.mem.eql(u8, trimmed, "signer")) return .signer;
    if (std.mem.eql(u8, trimmed, "u16")) return .u16;
    if (std.mem.eql(u8, trimmed, "u32")) return .u32;
    if (std.mem.eql(u8, trimmed, "u256")) return .u256;

    if (std.mem.startsWith(u8, trimmed, "vector<") and std.mem.endsWith(u8, trimmed, ">")) {
        const inner_spec = trimmed[7 .. trimmed.len - 1];
        const inner = try parseSimplifiedTypeTag(allocator, inner_spec);
        errdefer deinitOwnedTypeTag(allocator, inner);

        const inner_heap = try allocator.create(TypeTag);
        errdefer allocator.destroy(inner_heap);
        inner_heap.* = inner;
        return .{ .vector = inner_heap };
    }

    const arrow = std.mem.indexOfScalar(u8, trimmed, '<');
    const last_gt = std.mem.lastIndexOfScalar(u8, trimmed, '>');
    if ((arrow == null) != (last_gt == null)) return error.InvalidCli;

    const struct_spec, const type_args_spec = blk: {
        if (arrow) |arrow_index| {
            const gt_index = last_gt.?;
            if (arrow_index >= gt_index) return error.InvalidCli;
            break :blk .{ trimmed[0..arrow_index], trimmed[arrow_index + 1 .. gt_index] };
        }
        break :blk .{ trimmed, "" };
    };

    const first_sep = std.mem.indexOfScalar(u8, struct_spec, ':') orelse return error.InvalidCli;
    if (first_sep + 1 >= struct_spec.len or struct_spec[first_sep + 1] != ':' or first_sep + 2 >= struct_spec.len or struct_spec[first_sep + 2] != ':') {
        return error.InvalidCli;
    }
    const second_sep = std.mem.indexOfScalar(u8, struct_spec[first_sep + 3 ..], ':');
    if (second_sep == null or second_sep.? + first_sep + 3 >= struct_spec.len) {
        return error.InvalidCli;
    }

    const addr_str = std.mem.trim(u8, struct_spec[0..first_sep], " \t");
    const module_str = std.mem.trim(u8, struct_spec[first_sep + 3 .. first_sep + 3 + second_sep.?], " \t");
    const name_str = std.mem.trim(u8, struct_spec[first_sep + 3 + second_sep.? + 3 ..], " \t");
    if (addr_str.len == 0 or module_str.len == 0 or name_str.len == 0) return error.InvalidCli;

    const address = try parseHexAddress32(addr_str);

    var type_args: []const TypeTag = &.{};
    errdefer deinitOwnedTypeTagSlice(allocator, type_args);

    const trimmed_args = std.mem.trim(u8, type_args_spec, " \n\r\t");
    if (trimmed_args.len > 0) {
        var args_list = std.ArrayListUnmanaged(TypeTag){};
        errdefer {
            for (args_list.items) |item| deinitOwnedTypeTag(allocator, item);
            args_list.deinit(allocator);
        }

        var depth: usize = 0;
        var start: usize = 0;
        var in_str = false;
        for (trimmed_args, 0..) |c, i| {
            if (c == '"' and (i == 0 or trimmed_args[i - 1] != '\\')) {
                in_str = !in_str;
            }
            if (!in_str) {
                if (c == '<') depth += 1;
                if (c == '>') {
                    if (depth == 0) continue;
                    depth -= 1;
                }
                if (c == ',' and depth == 0) {
                    const arg = try parseSimplifiedTypeTag(allocator, trimmed_args[start..i]);
                    try args_list.append(allocator, arg);
                    start = i + 1;
                }
            }
        }
        if (start < trimmed_args.len) {
            const arg = try parseSimplifiedTypeTag(allocator, trimmed_args[start..]);
            try args_list.append(allocator, arg);
        }

        type_args = try args_list.toOwnedSlice(allocator);
    }

    const module_heap = try allocator.dupe(u8, module_str);
    errdefer allocator.free(module_heap);
    const name_heap = try allocator.dupe(u8, name_str);
    errdefer allocator.free(name_heap);

    return .{
        .struct_ = .{
            .address = address,
            .module = module_heap,
            .name = name_heap,
            .type_params = type_args,
        },
    };
}

fn encodeTypeTagFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !void {
    switch (value) {
        .string => |name| {
            if (std.mem.eql(u8, name, "bool")) return try appendVariantIndex(out, allocator, 0);
            if (std.mem.eql(u8, name, "u8")) return try appendVariantIndex(out, allocator, 1);
            if (std.mem.eql(u8, name, "u64")) return try appendVariantIndex(out, allocator, 2);
            if (std.mem.eql(u8, name, "u128")) return try appendVariantIndex(out, allocator, 3);
            if (std.mem.eql(u8, name, "address")) return try appendVariantIndex(out, allocator, 4);
            if (std.mem.eql(u8, name, "signer")) return try appendVariantIndex(out, allocator, 5);
            if (std.mem.eql(u8, name, "u16")) return try appendVariantIndex(out, allocator, 8);
            if (std.mem.eql(u8, name, "u32")) return try appendVariantIndex(out, allocator, 9);
            if (std.mem.eql(u8, name, "u256")) return try appendVariantIndex(out, allocator, 10);
            try encodeSimplifiedTypeTagFromString(out, allocator, name);
            return;
        },
        .object => |object| {
            if (object.get("Vector")) |inner| {
                try appendVariantIndex(out, allocator, 6);
                return try encodeTypeTagFromJson(out, allocator, inner);
            }
            if (object.get("Struct")) |struct_value| {
                const struct_object = try requireJsonObject(struct_value);
                try appendVariantIndex(out, allocator, 7);
                try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(try requireJsonField(struct_object, "address"))));
                try appendString(out, allocator, try parseStringJsonValue(try requireJsonField(struct_object, "module")));
                try appendString(out, allocator, try parseStringJsonValue(try requireJsonField(struct_object, "name")));

                const type_params = if (struct_object.get("typeParams")) |params|
                    try requireJsonArray(params)
                else
                    std.json.Array{ .items = &.{}, .capacity = 0, .allocator = allocator };
                try appendVariantIndex(out, allocator, type_params.items.len);
                for (type_params.items) |type_param| {
                    try encodeTypeTagFromJson(out, allocator, type_param);
                }
                return;
            }
            return error.InvalidCli;
        },
        else => return error.InvalidCli,
    }
}

fn encodeObjectRefFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !void {
    const object = try requireJsonObject(value);
    try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(try requireJsonField(object, "objectId"))));
    try appendU64(out, allocator, try parseUnsignedJsonValue(try requireJsonField(object, "version")));
    try appendDigest(out, allocator, try parseDigest32JsonValue(try requireJsonField(object, "digest")));
}

fn encodeObjectArgFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !void {
    const object = try requireJsonObject(value);
    if (object.get("ImmOrOwnedObject")) |imm_or_owned| {
        try appendVariantIndex(out, allocator, 0);
        return try encodeObjectRefFromJson(out, allocator, imm_or_owned);
    }
    if (object.get("SharedObject")) |shared_object| {
        const shared = try requireJsonObject(shared_object);
        try appendVariantIndex(out, allocator, 1);
        try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(try requireJsonField(shared, "objectId"))));
        try appendU64(out, allocator, try parseUnsignedJsonValue(try requireJsonField(shared, "initialSharedVersion")));
        try appendBool(out, allocator, try parseBoolJsonValue(try requireJsonField(shared, "mutable")));
        return;
    }
    if (object.get("Receiving")) |receiving| {
        try appendVariantIndex(out, allocator, 2);
        return try encodeObjectRefFromJson(out, allocator, receiving);
    }
    return error.InvalidCli;
}

fn encodeCallArgFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !void {
    const object = try requireJsonObject(value);
    if (object.get("Pure")) |pure| {
        var bytes: []u8 = undefined;
        if (pure == .string) {
            const raw = pure.string;
            if (std.mem.startsWith(u8, raw, "bcs:") or std.mem.startsWith(u8, raw, "BCS:")) {
                bytes = try parseBcsValueSpec(allocator, raw);
            } else {
                bytes = try parseRawBytesJsonValue(allocator, pure);
            }
        } else {
            bytes = try parseRawBytesJsonValue(allocator, pure);
        }
        defer allocator.free(bytes);
        try appendVariantIndex(out, allocator, 0);
        return try appendBytes(out, allocator, bytes);
    }
    if (object.get("Object")) |object_arg| {
        try appendVariantIndex(out, allocator, 1);
        return try encodeObjectArgFromJson(out, allocator, object_arg);
    }
    return error.InvalidCli;
}

fn encodeArgumentFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !void {
    switch (value) {
        .string => |name| {
            if (!std.mem.eql(u8, name, "GasCoin")) return error.InvalidCli;
            return try appendVariantIndex(out, allocator, 0);
        },
        .object => |object| {
            if (object.get("Input")) |input| {
                try appendVariantIndex(out, allocator, 1);
                return try appendU16(out, allocator, @intCast(try parseUnsignedJsonValue(input)));
            }
            if (object.get("Result")) |result| {
                try appendVariantIndex(out, allocator, 2);
                return try appendU16(out, allocator, @intCast(try parseUnsignedJsonValue(result)));
            }
            if (object.get("NestedResult")) |nested_result| {
                const nested = try requireJsonArray(nested_result);
                if (nested.items.len != 2) return error.InvalidCli;
                try appendVariantIndex(out, allocator, 3);
                try appendU16(out, allocator, @intCast(try parseUnsignedJsonValue(nested.items[0])));
                return try appendU16(out, allocator, @intCast(try parseUnsignedJsonValue(nested.items[1])));
            }
            return error.InvalidCli;
        },
        else => return error.InvalidCli,
    }
}

fn encodeCommandFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !void {
    const object = try requireJsonObject(value);
    const kind = try parseStringJsonValue(try requireJsonField(object, "kind"));

    if (std.mem.eql(u8, kind, "MoveCall")) {
        try appendVariantIndex(out, allocator, 0);
        try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(try requireJsonField(object, "package"))));
        try appendString(out, allocator, try parseStringJsonValue(try requireJsonField(object, "module")));
        try appendString(out, allocator, try parseStringJsonValue(try requireJsonField(object, "function")));

        const type_arguments = if (object.get("typeArguments")) |items|
            try requireJsonArray(items)
        else
            std.json.Array{ .items = &.{}, .capacity = 0, .allocator = allocator };
        try appendVariantIndex(out, allocator, type_arguments.items.len);
        for (type_arguments.items) |type_argument| {
            try encodeTypeTagFromJson(out, allocator, type_argument);
        }

        const arguments = if (object.get("arguments")) |items|
            try requireJsonArray(items)
        else
            std.json.Array{ .items = &.{}, .capacity = 0, .allocator = allocator };
        try appendVariantIndex(out, allocator, arguments.items.len);
        for (arguments.items) |argument| {
            try encodeArgumentFromJson(out, allocator, argument);
        }
        return;
    }

    if (std.mem.eql(u8, kind, "TransferObjects")) {
        const objects = try requireJsonArray(try requireJsonField(object, "objects"));
        try appendVariantIndex(out, allocator, 1);
        try appendVariantIndex(out, allocator, objects.items.len);
        for (objects.items) |arg| try encodeArgumentFromJson(out, allocator, arg);
        return try encodeArgumentFromJson(out, allocator, try requireJsonField(object, "address"));
    }

    if (std.mem.eql(u8, kind, "SplitCoins")) {
        const amounts = try requireJsonArray(try requireJsonField(object, "amounts"));
        try appendVariantIndex(out, allocator, 2);
        try encodeArgumentFromJson(out, allocator, try requireJsonField(object, "coin"));
        try appendVariantIndex(out, allocator, amounts.items.len);
        for (amounts.items) |amount| try encodeArgumentFromJson(out, allocator, amount);
        return;
    }

    if (std.mem.eql(u8, kind, "MergeCoins")) {
        const sources = try requireJsonArray(try requireJsonField(object, "sources"));
        try appendVariantIndex(out, allocator, 3);
        try encodeArgumentFromJson(out, allocator, try requireJsonField(object, "destination"));
        try appendVariantIndex(out, allocator, sources.items.len);
        for (sources.items) |source| try encodeArgumentFromJson(out, allocator, source);
        return;
    }

    if (std.mem.eql(u8, kind, "Publish")) {
        const modules = try requireJsonArray(try requireJsonField(object, "modules"));
        const dependencies = try requireJsonArray(try requireJsonField(object, "dependencies"));
        try appendVariantIndex(out, allocator, 4);
        try appendVariantIndex(out, allocator, modules.items.len);
        for (modules.items) |module_bytes| {
            const raw = try parseRawBytesJsonValue(allocator, module_bytes);
            defer allocator.free(raw);
            try appendBytes(out, allocator, raw);
        }
        try appendVariantIndex(out, allocator, dependencies.items.len);
        for (dependencies.items) |dependency| {
            try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(dependency)));
        }
        return;
    }

    if (std.mem.eql(u8, kind, "MakeMoveVec")) {
        const elements = try requireJsonArray(try requireJsonField(object, "elements"));
        try appendVariantIndex(out, allocator, 5);
        if (object.get("type")) |type_tag| {
            if (type_tag == .null) {
                try out.append(allocator, 0);
            } else {
                try out.append(allocator, 1);
                try encodeTypeTagFromJson(out, allocator, type_tag);
            }
        } else {
            try out.append(allocator, 0);
        }
        try appendVariantIndex(out, allocator, elements.items.len);
        for (elements.items) |element| try encodeArgumentFromJson(out, allocator, element);
        return;
    }

    if (std.mem.eql(u8, kind, "Upgrade")) {
        const modules = try requireJsonArray(try requireJsonField(object, "modules"));
        const dependencies = try requireJsonArray(try requireJsonField(object, "dependencies"));
        try appendVariantIndex(out, allocator, 6);
        try appendVariantIndex(out, allocator, modules.items.len);
        for (modules.items) |module_bytes| {
            const raw = try parseRawBytesJsonValue(allocator, module_bytes);
            defer allocator.free(raw);
            try appendBytes(out, allocator, raw);
        }
        try appendVariantIndex(out, allocator, dependencies.items.len);
        for (dependencies.items) |dependency| {
            try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(dependency)));
        }
        try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(try requireJsonField(object, "package"))));
        return try encodeArgumentFromJson(out, allocator, try requireJsonField(object, "ticket"));
    }

    return error.InvalidCli;
}

fn encodeProgrammableTransactionFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) !void {
    const inputs = if (object.get("inputs")) |items|
        try requireJsonArray(items)
    else
        std.json.Array{ .items = &.{}, .capacity = 0, .allocator = allocator };
    try appendVariantIndex(out, allocator, inputs.items.len);
    for (inputs.items) |input| try encodeCallArgFromJson(out, allocator, input);

    const commands = try requireJsonArray(try requireJsonField(object, "commands"));
    try appendVariantIndex(out, allocator, commands.items.len);
    for (commands.items) |command| try encodeCommandFromJson(out, allocator, command);
}

fn encodeGasDataFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !void {
    const object = try requireJsonObject(value);
    const payment = try requireJsonArray(try requireJsonField(object, "payment"));
    try appendVariantIndex(out, allocator, payment.items.len);
    for (payment.items) |entry| try encodeObjectRefFromJson(out, allocator, entry);
    try appendAddress(out, allocator, try parseHexAddress32(try parseStringJsonValue(try requireJsonField(object, "owner"))));
    try appendU64(out, allocator, try parseUnsignedJsonValue(try requireJsonField(object, "price")));
    try appendU64(out, allocator, try parseUnsignedJsonValue(try requireJsonField(object, "budget")));
}

fn encodeExpirationFromJson(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: ?std.json.Value,
) !void {
    const raw = value orelse {
        try appendVariantIndex(out, allocator, 0);
        return;
    };

    switch (raw) {
        .null => try appendVariantIndex(out, allocator, 0),
        .integer, .number_string, .string => {
            try appendVariantIndex(out, allocator, 1);
            try appendU64(out, allocator, try parseUnsignedJsonValue(raw));
        },
        .object => |object| {
            if (object.get("Epoch")) |epoch| {
                try appendVariantIndex(out, allocator, 1);
                return try appendU64(out, allocator, try parseUnsignedJsonValue(epoch));
            }
            if (object.get("epoch")) |epoch| {
                try appendVariantIndex(out, allocator, 1);
                return try appendU64(out, allocator, try parseUnsignedJsonValue(epoch));
            }
            return error.InvalidCli;
        },
        else => return error.InvalidCli,
    }
}

pub fn buildTransactionDataV1BytesFromJson(
    allocator: std.mem.Allocator,
    transaction_json: []const u8,
) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, transaction_json, .{});
    defer parsed.deinit();

    const object = try requireJsonObject(parsed.value);

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    try appendVariantIndex(&out, allocator, 0);
    try appendVariantIndex(&out, allocator, 0);
    try encodeProgrammableTransactionFromJson(&out, allocator, object);
    try appendAddress(&out, allocator, try parseHexAddress32(try parseStringJsonValue(try requireJsonField(object, "sender"))));
    try encodeGasDataFromJson(&out, allocator, try requireJsonField(object, "gasData"));
    try encodeExpirationFromJson(&out, allocator, object.get("expiration"));

    return try out.toOwnedSlice(allocator);
}

pub fn buildTransactionDataV1Base64FromJson(
    allocator: std.mem.Allocator,
    transaction_json: []const u8,
) ![]u8 {
    const bytes = try buildTransactionDataV1BytesFromJson(allocator, transaction_json);
    defer allocator.free(bytes);

    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return encoded;
}

fn decodeHexNibble(value: u8) !u8 {
    return switch (value) {
        '0'...'9' => value - '0',
        'a'...'f' => 10 + (value - 'a'),
        'A'...'F' => 10 + (value - 'A'),
        else => error.InvalidCli,
    };
}

pub fn parseBcsValueSpec(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (!std.mem.startsWith(u8, trimmed, "bcs:") and !std.mem.startsWith(u8, trimmed, "BCS:")) {
        return error.InvalidCli;
    }

    var spec = trimmed[4..];
    if (spec.len == 0) return error.InvalidCli;

    const type_end = std.mem.indexOfScalar(u8, spec, ':') orelse return error.InvalidCli;
    const type_name = std.mem.trim(u8, spec[0..type_end], " \t");
    const value_str = std.mem.trim(u8, spec[type_end + 1 ..], " \n\r\t");

    return try encodeBcsValue(allocator, type_name, value_str);
}

pub fn encodeBcsValue(allocator: std.mem.Allocator, type_name: []const u8, value_str: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    if (std.mem.eql(u8, type_name, "bool")) {
        const trimmed = std.mem.trim(u8, value_str, " \n\r\t");
        if (std.mem.eql(u8, trimmed, "true") or std.mem.eql(u8, trimmed, "1")) {
            try out.append(allocator, 1);
        } else if (std.mem.eql(u8, trimmed, "false") or std.mem.eql(u8, trimmed, "0")) {
            try out.append(allocator, 0);
        } else {
            return error.InvalidCli;
        }
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "u8")) {
        const v = try std.fmt.parseInt(u8, std.mem.trim(u8, value_str, " \n\r\t"), 10);
        try out.append(allocator, v);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "u16")) {
        const v = try std.fmt.parseInt(u16, std.mem.trim(u8, value_str, " \n\r\t"), 10);
        try appendU16(&out, allocator, v);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "u32")) {
        const v = try std.fmt.parseInt(u32, std.mem.trim(u8, value_str, " \n\r\t"), 10);
        try appendU32(&out, allocator, v);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "u64")) {
        const v = try std.fmt.parseInt(u64, std.mem.trim(u8, value_str, " \n\r\t"), 10);
        try appendU64(&out, allocator, v);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "u128")) {
        const v = try std.fmt.parseInt(u128, std.mem.trim(u8, value_str, " \n\r\t"), 10);
        try appendU128(&out, allocator, v);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "u256")) {
        const v = try std.fmt.parseInt(u256, std.mem.trim(u8, value_str, " \n\r\t"), 10);
        try appendU256(&out, allocator, v);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "address")) {
        const addr = try parseHexAddress32(std.mem.trim(u8, value_str, " \n\r\t"));
        try out.appendSlice(allocator, &addr);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "signer")) {
        const addr = try parseHexAddress32(std.mem.trim(u8, value_str, " \n\r\t"));
        try out.appendSlice(allocator, &addr);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "string")) {
        try appendString(&out, allocator, std.mem.trim(u8, value_str, " \n\r\t"));
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "utf8_string")) {
        try appendString(&out, allocator, std.mem.trim(u8, value_str, " \n\r\t"));
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "ascii_string")) {
        try appendString(&out, allocator, std.mem.trim(u8, value_str, " \n\r\t"));
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.eql(u8, type_name, "object_id")) {
        const addr = try parseHexAddress32(std.mem.trim(u8, value_str, " \n\r\t"));
        try out.appendSlice(allocator, &addr);
        return out.toOwnedSlice(allocator);
    }

    if (std.mem.startsWith(u8, type_name, "vector<") and std.mem.endsWith(u8, type_name, ">")) {
        const inner_type = type_name[7 .. type_name.len - 1];
        const trimmed = std.mem.trim(u8, value_str, " \n\r\t");

        if (std.mem.eql(u8, trimmed, "[]")) {
            try appendVariantIndex(&out, allocator, 0);
            return out.toOwnedSlice(allocator);
        }

        var elements: []const []const u8 = &.{};
        var owned_elements: std.ArrayListUnmanaged([]const u8) = .{};
        defer owned_elements.deinit(allocator);

        const trimmed2 = trimmed;
        if (std.mem.startsWith(u8, trimmed2, "[") and std.mem.endsWith(u8, trimmed2, "]")) {
            const inner = trimmed2[1 .. trimmed2.len - 1];
            var parts = std.ArrayList([]const u8){};
            defer parts.deinit(allocator);
            var in_string = false;
            var depth: usize = 0;
            var start: usize = 0;
            for (inner, 0..) |c, i| {
                if (c == '"' and (i == 0 or inner[i - 1] != '\\')) {
                    in_string = !in_string;
                }
                if (!in_string) {
                    if (c == '[' or c == '{') depth += 1;
                    if (c == ']' or c == '}') depth -= 1;
                    if (c == ',' and depth == 0) {
                        try parts.append(allocator, inner[start..i]);
                        start = i + 1;
                    }
                }
            }
            if (start < inner.len) {
                try parts.append(allocator, inner[start..]);
            }
            for (parts.items) |part| {
                const trimmed_part = std.mem.trim(u8, part, " \n\r\t");
                const encoded = try encodeBcsValue(allocator, inner_type, trimmed_part);
                defer allocator.free(encoded);
                try out.appendSlice(allocator, encoded);
            }
            elements = parts.items;
        } else {
            const encoded = try encodeBcsValue(allocator, inner_type, trimmed);
            defer allocator.free(encoded);
            try out.appendSlice(allocator, encoded);
        }

        var with_header = std.ArrayList(u8){};
        errdefer with_header.deinit(allocator);
        try appendVariantIndex(&with_header, allocator, elements.len);
        try with_header.appendSlice(allocator, out.items);

        return with_header.toOwnedSlice(allocator);
    }

    if (std.mem.startsWith(u8, type_name, "option<") and std.mem.endsWith(u8, type_name, ">")) {
        const inner_type = type_name[7 .. type_name.len - 1];
        const trimmed = std.mem.trim(u8, value_str, " \n\r\t");

        if (std.mem.eql(u8, trimmed, "null") or std.mem.eql(u8, trimmed, "none") or trimmed.len == 0) {
            try out.append(allocator, 0);
            return out.toOwnedSlice(allocator);
        }

        try out.append(allocator, 1);
        const encoded = try encodeBcsValue(allocator, inner_type, trimmed);
        defer allocator.free(encoded);
        try out.appendSlice(allocator, encoded);
        return out.toOwnedSlice(allocator);
    }

    return error.InvalidCli;
}

pub fn encodeBcsPureValue(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");

    if (std.mem.startsWith(u8, trimmed, "bcs:") or std.mem.startsWith(u8, trimmed, "BCS:")) {
        return try parseBcsValueSpec(allocator, trimmed);
    }

    return try parseRawBytesJsonValueFromString(allocator, trimmed);
}

pub fn parseRawBytesJsonValueFromString(
    allocator: std.mem.Allocator,
    value: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, value, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
        return try parseHexBytesAlloc(allocator, trimmed);
    }

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(trimmed) catch return error.InvalidCli;
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, trimmed) catch return error.InvalidCli;
    return decoded;
}

pub fn parseHexAddress32(value: []const u8) !Address {
    const trimmed = std.mem.trim(u8, value, " \n\r\t");
    const raw = if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X"))
        trimmed[2..]
    else
        trimmed;

    if (raw.len == 0 or raw.len > 64) return error.InvalidCli;

    var address = std.mem.zeroes(Address);
    const normalized_len = if (raw.len % 2 == 0) raw.len else raw.len + 1;
    const start = address.len - (normalized_len / 2);

    var src_index: usize = 0;
    var dst_index = start;
    if (raw.len % 2 != 0) {
        address[dst_index] = try decodeHexNibble(raw[0]);
        src_index = 1;
        dst_index += 1;
    }

    while (src_index < raw.len) : (src_index += 2) {
        const high = try decodeHexNibble(raw[src_index]);
        const low = try decodeHexNibble(raw[src_index + 1]);
        address[dst_index] = (high << 4) | low;
        dst_index += 1;
    }

    return address;
}

fn repeatedByteAddress(byte: u8) Address {
    var out: Address = undefined;
    @memset(out[0..], byte);
    return out;
}

fn repeatedByteDigest(byte: u8) ObjectDigest {
    var out: ObjectDigest = undefined;
    @memset(out[0..], byte);
    return out;
}

test "parseHexAddress32 left pads short object ids" {
    const testing = std.testing;

    const parsed = try parseHexAddress32("0x2");
    var expected = std.mem.zeroes(Address);
    expected[31] = 0x02;
    try testing.expectEqualSlices(u8, &expected, &parsed);

    const odd = try parseHexAddress32("abc");
    var odd_expected = std.mem.zeroes(Address);
    odd_expected[30] = 0x0a;
    odd_expected[31] = 0xbc;
    try testing.expectEqualSlices(u8, &odd_expected, &odd);
}

test "parseDigest32JsonValue accepts base58 Sui digests" {
    const testing = std.testing;

    const zero_digest = try parseDigest32JsonValue(.{ .string = "11111111111111111111111111111111" });
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &zero_digest);

    const real_digest = try parseDigest32JsonValue(.{ .string = "FHL9d5iUQqHpWXH4mPbHBekKHhMKAAQNwF8Vxad4meoh" });
    const expected = try parseHexAddress32("0x20d4328fb5e6b7e14018d56d7591abef99ca042c41ee048067601ba76aa702db");
    try testing.expectEqualSlices(u8, &expected, &real_digest);
}

test "buildTransactionDataV1Bytes encodes struct type tags with nested vectors" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const inner_vector_tag: TypeTag = .address;
    const vector_tag: TypeTag = .{ .vector = &inner_vector_tag };
    const struct_tag: TypeTag = .{
        .struct_ = .{
            .address = repeatedByteAddress(0xaa),
            .module = "clmm",
            .name = "Pool",
            .type_params = &.{ .u64, vector_tag },
        },
    };

    const bytes = try buildTransactionDataV1Bytes(allocator, .{
        .programmable_transaction = .{
            .commands = &.{.{
                .move_call = .{
                    .package = repeatedByteAddress(0x11),
                    .module = "pkg",
                    .function_name = "f",
                    .type_arguments = &.{struct_tag},
                },
            }},
        },
        .sender = repeatedByteAddress(0x22),
        .gas_data = .{
            .payment = &.{.{
                .object_id = repeatedByteAddress(0x33),
                .version = 1,
                .digest = repeatedByteDigest(0x44),
            }},
            .owner = repeatedByteAddress(0x55),
            .price = 2,
            .budget = 3,
        },
    });
    defer allocator.free(bytes);

    const expected_suffix = [_]u8{
        0x07,
    } ++ repeatedByteAddress(0xaa) ++ [_]u8{
        0x04, 'c',  'l',  'm',  'm',
        0x04, 'P',  'o',  'o',  'l',
        0x02, 0x02, 0x06, 0x04,
    };
    try testing.expect(std.mem.indexOf(u8, bytes, &expected_suffix) != null);
}

test "buildTransactionDataV1Bytes encodes a minimal programmable move call exactly" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const transaction = TransactionDataV1{
        .programmable_transaction = .{
            .commands = &.{.{
                .move_call = .{
                    .package = repeatedByteAddress(0x11),
                    .module = "pool",
                    .function_name = "swap",
                },
            }},
        },
        .sender = repeatedByteAddress(0x22),
        .gas_data = .{
            .payment = &.{.{
                .object_id = repeatedByteAddress(0x33),
                .version = 5,
                .digest = repeatedByteDigest(0x44),
            }},
            .owner = repeatedByteAddress(0x55),
            .price = 7,
            .budget = 9,
        },
    };

    const bytes = try buildTransactionDataV1Bytes(allocator, transaction);
    defer allocator.free(bytes);

    var expected = std.ArrayList(u8){};
    defer expected.deinit(allocator);
    try expected.appendSlice(allocator, &.{ 0x00, 0x00, 0x00, 0x01, 0x00 });
    try expected.appendSlice(allocator, &repeatedByteAddress(0x11));
    try expected.appendSlice(allocator, &.{ 0x04, 'p', 'o', 'o', 'l' });
    try expected.appendSlice(allocator, &.{ 0x04, 's', 'w', 'a', 'p' });
    try expected.appendSlice(allocator, &.{ 0x00, 0x00 });
    try expected.appendSlice(allocator, &repeatedByteAddress(0x22));
    try expected.appendSlice(allocator, &.{0x01});
    try expected.appendSlice(allocator, &repeatedByteAddress(0x33));
    try expected.appendSlice(allocator, &.{ 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
    try expected.appendSlice(allocator, &.{0x20});
    try expected.appendSlice(allocator, &repeatedByteDigest(0x44));
    try expected.appendSlice(allocator, &repeatedByteAddress(0x55));
    try expected.appendSlice(allocator, &.{ 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
    try expected.appendSlice(allocator, &.{ 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
    try expected.appendSlice(allocator, &.{0x00});

    try testing.expectEqualSlices(u8, expected.items, bytes);

    const encoded = try buildTransactionDataV1Base64(allocator, transaction);
    defer allocator.free(encoded);

    const expected_base64_len = std.base64.standard.Encoder.calcSize(expected.items.len);
    const expected_base64 = try allocator.alloc(u8, expected_base64_len);
    defer allocator.free(expected_base64);
    _ = std.base64.standard.Encoder.encode(expected_base64, expected.items);

    try testing.expectEqualStrings(expected_base64, encoded);
}

test "buildTransactionDataV1Bytes supports all programmable command variants" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const type_arg_inner: TypeTag = .address;
    const type_arg_vector: TypeTag = .{ .vector = &type_arg_inner };

    const transaction = TransactionDataV1{
        .programmable_transaction = .{
            .inputs = &.{
                .{ .pure = &.{0x07} },
                .{ .object = .{ .imm_or_owned_object = .{
                    .object_id = repeatedByteAddress(0x61),
                    .version = 11,
                    .digest = repeatedByteDigest(0x71),
                } } },
                .{ .object = .{ .shared_object = .{
                    .object_id = repeatedByteAddress(0x62),
                    .initial_shared_version = 12,
                    .mutable = true,
                } } },
                .{ .object = .{ .receiving = .{
                    .object_id = repeatedByteAddress(0x63),
                    .version = 13,
                    .digest = repeatedByteDigest(0x73),
                } } },
            },
            .commands = &.{
                .{
                    .move_call = .{
                        .package = repeatedByteAddress(0x10),
                        .module = "pkg",
                        .function_name = "swap",
                        .type_arguments = &.{type_arg_vector},
                        .arguments = &.{ .gas_coin, .{ .input = 0 }, .{ .nested_result = .{ .command_index = 1, .result_index = 0 } } },
                    },
                },
                .{
                    .transfer_objects = .{
                        .objects = &.{ .{ .input = 1 }, .{ .result = 0 } },
                        .address = .{ .input = 0 },
                    },
                },
                .{
                    .split_coins = .{
                        .coin = .gas_coin,
                        .amounts = &.{.{ .input = 0 }},
                    },
                },
                .{
                    .merge_coins = .{
                        .destination = .{ .input = 1 },
                        .sources = &.{.{ .input = 3 }},
                    },
                },
                .{
                    .publish = .{
                        .modules = &.{&.{ 0xaa, 0xbb }},
                        .dependencies = &.{repeatedByteAddress(0x20)},
                    },
                },
                .{
                    .make_move_vec = .{
                        .type_ = &type_arg_inner,
                        .elements = &.{ .{ .input = 1 }, .{ .result = 2 } },
                    },
                },
                .{
                    .upgrade = .{
                        .modules = &.{&.{0xcc}},
                        .dependencies = &.{repeatedByteAddress(0x21)},
                        .package = repeatedByteAddress(0x22),
                        .ticket = .{ .input = 1 },
                    },
                },
            },
        },
        .sender = repeatedByteAddress(0x30),
        .gas_data = .{
            .payment = &.{.{
                .object_id = repeatedByteAddress(0x40),
                .version = 14,
                .digest = repeatedByteDigest(0x50),
            }},
            .owner = repeatedByteAddress(0x31),
            .price = 15,
            .budget = 16,
        },
        .expiration = .{ .epoch = 17 },
    };

    const bytes = try buildTransactionDataV1Bytes(allocator, transaction);
    defer allocator.free(bytes);

    try testing.expect(bytes.len > 0);
    try testing.expectEqual(@as(u8, 0), bytes[0]);
    try testing.expectEqual(@as(u8, 0), bytes[1]);
}

test "buildTransactionDataV1BytesFromJson lowers lowerable PTB json into the same bytes as the typed builder" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const type_arg_inner: TypeTag = .address;
    const type_arg_vector: TypeTag = .{ .vector = &type_arg_inner };

    const typed_transaction = TransactionDataV1{
        .programmable_transaction = .{
            .inputs = &.{
                .{ .pure = &.{0x07} },
                .{ .object = .{ .imm_or_owned_object = .{
                    .object_id = repeatedByteAddress(0x61),
                    .version = 11,
                    .digest = repeatedByteDigest(0x71),
                } } },
                .{ .object = .{ .shared_object = .{
                    .object_id = repeatedByteAddress(0x62),
                    .initial_shared_version = 12,
                    .mutable = true,
                } } },
                .{ .object = .{ .receiving = .{
                    .object_id = repeatedByteAddress(0x63),
                    .version = 13,
                    .digest = repeatedByteDigest(0x73),
                } } },
            },
            .commands = &.{
                .{
                    .move_call = .{
                        .package = repeatedByteAddress(0x10),
                        .module = "pkg",
                        .function_name = "swap",
                        .type_arguments = &.{type_arg_vector},
                        .arguments = &.{ .gas_coin, .{ .input = 0 }, .{ .nested_result = .{ .command_index = 1, .result_index = 0 } } },
                    },
                },
                .{
                    .transfer_objects = .{
                        .objects = &.{ .{ .input = 1 }, .{ .result = 0 } },
                        .address = .{ .input = 0 },
                    },
                },
                .{
                    .split_coins = .{
                        .coin = .gas_coin,
                        .amounts = &.{.{ .input = 0 }},
                    },
                },
                .{
                    .merge_coins = .{
                        .destination = .{ .input = 1 },
                        .sources = &.{.{ .input = 3 }},
                    },
                },
            },
        },
        .sender = repeatedByteAddress(0x30),
        .gas_data = .{
            .payment = &.{.{
                .object_id = repeatedByteAddress(0x40),
                .version = 14,
                .digest = repeatedByteDigest(0x50),
            }},
            .owner = repeatedByteAddress(0x31),
            .price = 15,
            .budget = 16,
        },
        .expiration = .{ .epoch = 17 },
    };

    const typed_bytes = try buildTransactionDataV1Bytes(allocator, typed_transaction);
    defer allocator.free(typed_bytes);
    const typed_base64 = try buildTransactionDataV1Base64(allocator, typed_transaction);
    defer allocator.free(typed_base64);

    const json_transaction =
        \\{
        \\  "inputs":[
        \\    {"Pure":[7]},
        \\    {"Object":{"ImmOrOwnedObject":{"objectId":"0x6161616161616161616161616161616161616161616161616161616161616161","version":11,"digest":"cXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXE="}}},
        \\    {"Object":{"SharedObject":{"objectId":"0x6262626262626262626262626262626262626262626262626262626262626262","initialSharedVersion":12,"mutable":true}}},
        \\    {"Object":{"Receiving":{"objectId":"0x6363636363636363636363636363636363636363636363636363636363636363","version":13,"digest":"c3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3M="}}}
        \\  ],
        \\  "commands":[
        \\    {"kind":"MoveCall","package":"0x1010101010101010101010101010101010101010101010101010101010101010","module":"pkg","function":"swap","typeArguments":[{"Vector":"address"}],"arguments":["GasCoin",{"Input":0},{"NestedResult":[1,0]}]},
        \\    {"kind":"TransferObjects","objects":[{"Input":1},{"Result":0}],"address":{"Input":0}},
        \\    {"kind":"SplitCoins","coin":"GasCoin","amounts":[{"Input":0}]},
        \\    {"kind":"MergeCoins","destination":{"Input":1},"sources":[{"Input":3}]}
        \\  ],
        \\  "sender":"0x3030303030303030303030303030303030303030303030303030303030303030",
        \\  "gasData":{
        \\    "payment":[{"objectId":"0x4040404040404040404040404040404040404040404040404040404040404040","version":14,"digest":"UFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFA="}],
        \\    "owner":"0x3131313131313131313131313131313131313131313131313131313131313131",
        \\    "price":15,
        \\    "budget":16
        \\  },
        \\  "expiration":{"epoch":17}
        \\}
    ;

    const json_bytes = try buildTransactionDataV1BytesFromJson(allocator, json_transaction);
    defer allocator.free(json_bytes);
    const json_base64 = try buildTransactionDataV1Base64FromJson(allocator, json_transaction);
    defer allocator.free(json_base64);

    try testing.expectEqualSlices(u8, typed_bytes, json_bytes);
    try testing.expectEqualStrings(typed_base64, json_base64);
}

test "buildTransactionDataV1BytesFromJson accepts real base58 digests in object refs" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sender = try parseHexAddress32("0xae4469ed51da68ccde6642e22b6d44dfbb4ee56836d6b0ea2066db2cdb273bcf");
    const object_id = try parseHexAddress32("0xcdc3da0627feca81dc6a099a615522ae4cea565f3f6ebf868d22e28ef332cef8");
    const gas_id = try parseHexAddress32("0x0d3fe7d4a650b0d12577a847b046b7e4ae2febb201f58021c024bf3c7ed0d5b9");
    const digest = try parseHexAddress32("0x20d4328fb5e6b7e14018d56d7591abef99ca042c41ee048067601ba76aa702db");

    const typed_transaction = TransactionDataV1{
        .programmable_transaction = .{
            .inputs = &.{
                .{ .object = .{ .imm_or_owned_object = .{
                    .object_id = object_id,
                    .version = 2,
                    .digest = digest,
                } } },
                .{ .pure = &sender },
            },
            .commands = &.{.{
                .transfer_objects = .{
                    .objects = &.{.{ .input = 0 }},
                    .address = .{ .input = 1 },
                },
            }},
        },
        .sender = sender,
        .gas_data = .{
            .payment = &.{.{
                .object_id = gas_id,
                .version = 2,
                .digest = digest,
            }},
            .owner = sender,
            .price = 1000,
            .budget = 100000000,
        },
    };

    const typed_base64 = try buildTransactionDataV1Base64(allocator, typed_transaction);
    defer allocator.free(typed_base64);

    const json_transaction =
        \\{
        \\  "inputs":[
        \\    {"Object":{"ImmOrOwnedObject":{"objectId":"0xcdc3da0627feca81dc6a099a615522ae4cea565f3f6ebf868d22e28ef332cef8","version":2,"digest":"FHL9d5iUQqHpWXH4mPbHBekKHhMKAAQNwF8Vxad4meoh"}}},
        \\    {"Pure":"rkRp7VHaaMzeZkLiK21E37tO5Wg21rDqIGbbLNsnO88="}
        \\  ],
        \\  "commands":[
        \\    {"kind":"TransferObjects","objects":[{"Input":0}],"address":{"Input":1}}
        \\  ],
        \\  "sender":"0xae4469ed51da68ccde6642e22b6d44dfbb4ee56836d6b0ea2066db2cdb273bcf",
        \\  "gasData":{
        \\    "payment":[{"objectId":"0x0d3fe7d4a650b0d12577a847b046b7e4ae2febb201f58021c024bf3c7ed0d5b9","version":"2","digest":"FHL9d5iUQqHpWXH4mPbHBekKHhMKAAQNwF8Vxad4meoh"}],
        \\    "owner":"0xae4469ed51da68ccde6642e22b6d44dfbb4ee56836d6b0ea2066db2cdb273bcf",
        \\    "price":1000,
        \\    "budget":100000000
        \\  }
        \\}
    ;

    const json_base64 = try buildTransactionDataV1Base64FromJson(allocator, json_transaction);
    defer allocator.free(json_base64);

    try testing.expectEqualStrings(typed_base64, json_base64);
    try testing.expectEqualStrings(
        "AAACAQDNw9oGJ/7KgdxqCZphVSKuTOpWXz9uv4aNIuKO8zLO+AIAAAAAAAAAINQyj7Xmt+FAGNVtdZGr75nKBCxB7gSAZ2Abp2qnAtsYACCuRGntUdpozN5mQuIrbUTfu07laDbWsOogZtss2yc7zwEBAQEAAAEBAK5Eae1R2mjM3mZC4ittRN+7TuVoNtaw6iBm2yzbJzvPAQ0/59SmULDRJXeoR7BGt+SuL+uyAfWAIcAkvzx+0NW5AgAAAAAAAAAgOdPVQ2ByIZFHX9p7jJNlpd5UZy1I5mxdieQ9pmwcxLquRGntUdpozN5mQuIrbUTfu07laDbWsOogZtss2yc7z+gDAAAAAAAAAOH1BQAAAAAA",
        typed_base64,
    );
}

test "buildTransactionDataV1BytesFromJson supports make-move-vec publish and upgrade commands" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_transaction =
        \\{
        \\  "inputs":[
        \\    {"Object":{"ImmOrOwnedObject":{"objectId":"0x6161616161616161616161616161616161616161616161616161616161616161","version":11,"digest":"cXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXE="}}},
        \\    {"Object":{"ImmOrOwnedObject":{"objectId":"0x6262626262626262626262626262626262626262626262626262626262626262","version":12,"digest":"cnJycnJycnJycnJycnJycnJycnJycnJycnJycnJycnI="}}}
        \\  ],
        \\  "commands":[
        \\    {"kind":"MakeMoveVec","type":null,"elements":[{"Input":0}]},
        \\    {"kind":"Publish","modules":["AQID"],"dependencies":["0x2020202020202020202020202020202020202020202020202020202020202020"]},
        \\    {"kind":"Upgrade","modules":["BAUG"],"dependencies":["0x2121212121212121212121212121212121212121212121212121212121212121"],"package":"0x2222222222222222222222222222222222222222222222222222222222222222","ticket":{"Input":1}}
        \\  ],
        \\  "sender":"0x3030303030303030303030303030303030303030303030303030303030303030",
        \\  "gasData":{
        \\    "payment":[{"objectId":"0x4040404040404040404040404040404040404040404040404040404040404040","version":14,"digest":"UFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFA="}],
        \\    "owner":"0x3131313131313131313131313131313131313131313131313131313131313131",
        \\    "price":15,
        \\    "budget":16
        \\  }
        \\}
    ;

    const bytes = try buildTransactionDataV1BytesFromJson(allocator, json_transaction);
    defer allocator.free(bytes);
    const base64 = try buildTransactionDataV1Base64FromJson(allocator, json_transaction);
    defer allocator.free(base64);

    try testing.expect(bytes.len != 0);
    try testing.expect(base64.len != 0);
}

test "buildTransactionDataV1BytesFromParts matches the full local PTB json builder" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const inputs_json =
        \\[
        \\  {"Pure":[7]},
        \\  {"Object":{"ImmOrOwnedObject":{"objectId":"0x6161616161616161616161616161616161616161616161616161616161616161","version":11,"digest":"cXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXE="}}},
        \\  {"Object":{"SharedObject":{"objectId":"0x6262626262626262626262626262626262626262626262626262626262626262","initialSharedVersion":12,"mutable":true}}},
        \\  {"Object":{"Receiving":{"objectId":"0x6363636363636363636363636363636363636363636363636363636363636363","version":13,"digest":"c3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3M="}}}
        \\]
    ;
    const commands_json =
        \\[
        \\  {"kind":"MoveCall","package":"0x1010101010101010101010101010101010101010101010101010101010101010","module":"pkg","function":"swap","typeArguments":[{"Vector":"address"}],"arguments":["GasCoin",{"Input":0},{"NestedResult":[1,0]}]},
        \\  {"kind":"TransferObjects","objects":[{"Input":1},{"Result":0}],"address":{"Input":0}},
        \\  {"kind":"SplitCoins","coin":"GasCoin","amounts":[{"Input":0}]},
        \\  {"kind":"MergeCoins","destination":{"Input":1},"sources":[{"Input":3}]}
        \\]
    ;
    const gas_data_json =
        \\{
        \\  "payment":[{"objectId":"0x4040404040404040404040404040404040404040404040404040404040404040","version":14,"digest":"UFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFA="}],
        \\  "owner":"0x3131313131313131313131313131313131313131313131313131313131313131",
        \\  "price":15,
        \\  "budget":16
        \\}
    ;
    const sender = "0x3030303030303030303030303030303030303030303030303030303030303030";
    const expiration_json = "{\"epoch\":17}";

    const from_parts = try buildTransactionDataV1BytesFromParts(
        allocator,
        inputs_json,
        commands_json,
        sender,
        gas_data_json,
        expiration_json,
    );
    defer allocator.free(from_parts);

    const from_parts_b64 = try buildTransactionDataV1Base64FromParts(
        allocator,
        inputs_json,
        commands_json,
        sender,
        gas_data_json,
        expiration_json,
    );
    defer allocator.free(from_parts_b64);

    const full_json =
        \\{
        \\  "inputs":[
        \\    {"Pure":[7]},
        \\    {"Object":{"ImmOrOwnedObject":{"objectId":"0x6161616161616161616161616161616161616161616161616161616161616161","version":11,"digest":"cXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXE="}}},
        \\    {"Object":{"SharedObject":{"objectId":"0x6262626262626262626262626262626262626262626262626262626262626262","initialSharedVersion":12,"mutable":true}}},
        \\    {"Object":{"Receiving":{"objectId":"0x6363636363636363636363636363636363636363636363636363636363636363","version":13,"digest":"c3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3Nzc3M="}}}
        \\  ],
        \\  "commands":[
        \\    {"kind":"MoveCall","package":"0x1010101010101010101010101010101010101010101010101010101010101010","module":"pkg","function":"swap","typeArguments":[{"Vector":"address"}],"arguments":["GasCoin",{"Input":0},{"NestedResult":[1,0]}]},
        \\    {"kind":"TransferObjects","objects":[{"Input":1},{"Result":0}],"address":{"Input":0}},
        \\    {"kind":"SplitCoins","coin":"GasCoin","amounts":[{"Input":0}]},
        \\    {"kind":"MergeCoins","destination":{"Input":1},"sources":[{"Input":3}]}
        \\  ],
        \\  "sender":"0x3030303030303030303030303030303030303030303030303030303030303030",
        \\  "gasData":{
        \\    "payment":[{"objectId":"0x4040404040404040404040404040404040404040404040404040404040404040","version":14,"digest":"UFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFA="}],
        \\    "owner":"0x3131313131313131313131313131313131313131313131313131313131313131",
        \\    "price":15,
        \\    "budget":16
        \\  },
        \\  "expiration":{"epoch":17}
        \\}
    ;

    const from_full_json = try buildTransactionDataV1BytesFromJson(allocator, full_json);
    defer allocator.free(from_full_json);
    const from_full_json_b64 = try buildTransactionDataV1Base64FromJson(allocator, full_json);
    defer allocator.free(from_full_json_b64);

    try testing.expectEqualSlices(u8, from_full_json, from_parts);
    try testing.expectEqualStrings(from_full_json_b64, from_parts_b64);
}

test "buildTransactionDataV1BytesFromParts rejects malformed explicit local PTB parts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(
        error.InvalidCli,
        buildTransactionDataV1BytesFromParts(
            allocator,
            "{}",
            "[]",
            "0x1",
            "{\"payment\":[],\"owner\":\"0x2\",\"price\":1,\"budget\":2}",
            null,
        ),
    );
}
