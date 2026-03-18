const std = @import("std");

pub const MoveCallSpec = struct {
    package_id: []const u8,
    module: []const u8,
    function_name: []const u8,
    type_args: ?[]const u8 = null,
    arguments: ?[]const u8 = null,
};

pub const CommandSource = struct {
    command_items: []const []const u8 = &.{},
    commands_json: ?[]const u8 = null,
    move_call: ?MoveCallSpec = null,
};

pub const TransferObjectsSpec = struct {
    objects_json: []const u8,
    address_json: []const u8,
};

pub const SplitCoinsSpec = struct {
    coin_json: []const u8,
    amounts_json: []const u8,
};

pub const MergeCoinsSpec = struct {
    destination_json: []const u8,
    sources_json: []const u8,
};

pub const PublishSpec = struct {
    modules_json: []const u8,
    dependencies_json: []const u8,
};

pub const UpgradeSpec = struct {
    modules_json: []const u8,
    dependencies_json: []const u8,
    package_id: []const u8,
    ticket_json: []const u8,
};

fn requireProgrammaticField(obj: std.json.ObjectMap, field_name: []const u8) !std.json.Value {
    return obj.get(field_name) orelse error.InvalidCli;
}

fn requireProgrammaticStringField(obj: std.json.ObjectMap, field_name: []const u8) !void {
    const value = try requireProgrammaticField(obj, field_name);
    if (value != .string or value.string.len == 0) return error.InvalidCli;
}

fn requireProgrammaticArrayField(obj: std.json.ObjectMap, field_name: []const u8) !void {
    const value = try requireProgrammaticField(obj, field_name);
    if (value != .array) return error.InvalidCli;
}

fn writeRequiredJsonArray(
    allocator: std.mem.Allocator,
    writer: anytype,
    raw: []const u8,
) !void {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidCli;
    try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
}

fn writeRequiredJsonValue(
    allocator: std.mem.Allocator,
    writer: anytype,
    raw: []const u8,
) !void {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
}

pub fn buildJsonStringArray(
    allocator: std.mem.Allocator,
    entries: []const []const u8,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("[");
    for (entries, 0..) |entry, index| {
        const trimmed = std.mem.trim(u8, entry, " \n\r\t");
        if (trimmed.len == 0) return error.InvalidCli;
        if (index != 0) try writer.writeAll(",");
        try writer.print("{f}", .{std.json.fmt(trimmed, .{})});
    }
    try writer.writeAll("]");

    return try out.toOwnedSlice(allocator);
}

pub fn buildCliValueJson(
    allocator: std.mem.Allocator,
    raw: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    if (parsed) |value| {
        defer value.deinit();
        var out = std.ArrayList(u8){};
        errdefer out.deinit(allocator);
        try out.writer(allocator).print("{f}", .{std.json.fmt(value.value, .{})});
        return try out.toOwnedSlice(allocator);
    }

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    try out.writer(allocator).print("{f}", .{std.json.fmt(trimmed, .{})});
    return try out.toOwnedSlice(allocator);
}

fn maybeBuildCliPtbArgumentJson(
    allocator: std.mem.Allocator,
    raw: []const u8,
) !?[]u8 {
    const trimmed = std.mem.trim(u8, raw, " \n\r\t");
    if (!std.mem.startsWith(u8, trimmed, "ptb:")) return null;

    const spec = trimmed[4..];
    if (spec.len == 0) return error.InvalidCli;

    if (std.mem.eql(u8, spec, "gas") or std.mem.eql(u8, spec, "gascoin")) {
        return try allocator.dupe(u8, "\"GasCoin\"");
    }
    if (std.mem.startsWith(u8, spec, "input:")) {
        const index = try std.fmt.parseInt(u16, spec["input:".len..], 10);
        return try std.fmt.allocPrint(allocator, "{{\"Input\":{}}}", .{index});
    }
    if (std.mem.startsWith(u8, spec, "result:")) {
        const index = try std.fmt.parseInt(u16, spec["result:".len..], 10);
        return try std.fmt.allocPrint(allocator, "{{\"Result\":{}}}", .{index});
    }
    if (std.mem.startsWith(u8, spec, "nested:")) {
        const rest = spec["nested:".len..];
        const sep = std.mem.indexOfScalar(u8, rest, ':') orelse return error.InvalidCli;
        const command_index = try std.fmt.parseInt(u16, rest[0..sep], 10);
        const result_index = try std.fmt.parseInt(u16, rest[sep + 1 ..], 10);
        return try std.fmt.allocPrint(allocator, "{{\"NestedResult\":[{},{}]}}", .{ command_index, result_index });
    }

    return error.InvalidCli;
}

pub fn buildCliPtbArgumentJson(
    allocator: std.mem.Allocator,
    raw: []const u8,
) ![]u8 {
    if (try maybeBuildCliPtbArgumentJson(allocator, raw)) |json| return json;
    return try buildCliValueJson(allocator, raw);
}

pub fn buildCliValueArray(
    allocator: std.mem.Allocator,
    entries: []const []const u8,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("[");
    for (entries, 0..) |entry, index| {
        const trimmed = std.mem.trim(u8, entry, " \n\r\t");
        if (trimmed.len == 0) return error.InvalidCli;
        if (index != 0) try writer.writeAll(",");
        const json = try buildCliValueJson(allocator, trimmed);
        defer allocator.free(json);
        try writer.writeAll(json);
    }
    try writer.writeAll("]");

    return try out.toOwnedSlice(allocator);
}

pub fn buildCliPtbArgumentArray(
    allocator: std.mem.Allocator,
    entries: []const []const u8,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("[");
    for (entries, 0..) |entry, index| {
        const trimmed = std.mem.trim(u8, entry, " \n\r\t");
        if (trimmed.len == 0) return error.InvalidCli;
        if (index != 0) try writer.writeAll(",");
        const json = try buildCliPtbArgumentJson(allocator, trimmed);
        defer allocator.free(json);
        try writer.writeAll(json);
    }
    try writer.writeAll("]");

    return try out.toOwnedSlice(allocator);
}

pub fn validateCommandEntry(entry: std.json.Value) !void {
    if (entry != .object) return error.InvalidCli;
    const kind = entry.object.get("kind") orelse return error.InvalidCli;
    if (kind != .string or kind.string.len == 0) return error.InvalidCli;

    if (std.mem.eql(u8, kind.string, "MoveCall")) {
        try requireProgrammaticStringField(entry.object, "package");
        try requireProgrammaticStringField(entry.object, "module");
        try requireProgrammaticStringField(entry.object, "function");

        if (entry.object.get("typeArguments")) |type_arguments| {
            if (type_arguments != .array) return error.InvalidCli;
        }
        if (entry.object.get("arguments")) |arguments| {
            if (arguments != .array) return error.InvalidCli;
        }
        return;
    }

    if (std.mem.eql(u8, kind.string, "TransferObjects")) {
        try requireProgrammaticArrayField(entry.object, "objects");
        _ = try requireProgrammaticField(entry.object, "address");
        return;
    }

    if (std.mem.eql(u8, kind.string, "SplitCoins")) {
        _ = try requireProgrammaticField(entry.object, "coin");
        try requireProgrammaticArrayField(entry.object, "amounts");
        return;
    }

    if (std.mem.eql(u8, kind.string, "MergeCoins")) {
        _ = try requireProgrammaticField(entry.object, "destination");
        try requireProgrammaticArrayField(entry.object, "sources");
        return;
    }

    if (std.mem.eql(u8, kind.string, "MakeMoveVec")) {
        _ = entry.object.get("type");
        try requireProgrammaticArrayField(entry.object, "elements");
        return;
    }

    if (std.mem.eql(u8, kind.string, "Publish")) {
        try requireProgrammaticArrayField(entry.object, "modules");
        try requireProgrammaticArrayField(entry.object, "dependencies");
        return;
    }

    if (std.mem.eql(u8, kind.string, "Upgrade")) {
        try requireProgrammaticArrayField(entry.object, "modules");
        try requireProgrammaticArrayField(entry.object, "dependencies");
        try requireProgrammaticStringField(entry.object, "package");
        _ = try requireProgrammaticField(entry.object, "ticket");
        return;
    }
}

fn writeOptionalJsonArray(
    allocator: std.mem.Allocator,
    writer: anytype,
    raw: ?[]const u8,
) !void {
    const value = raw orelse "[]";
    const trimmed = std.mem.trim(u8, value, " \n\r\t");
    if (trimmed.len == 0) {
        try writer.writeAll("[]");
        return;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidCli;
    try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
}

pub fn writeMoveCallInstruction(
    allocator: std.mem.Allocator,
    writer: anytype,
    package_id: []const u8,
    module: []const u8,
    function_name: []const u8,
    type_args: ?[]const u8,
    call_args: ?[]const u8,
) !void {
    try writer.writeAll("{\"kind\":\"MoveCall\"");
    try writer.print(",\"package\":{f}", .{std.json.fmt(package_id, .{})});
    try writer.print(",\"module\":{f}", .{std.json.fmt(module, .{})});
    try writer.print(",\"function\":{f}", .{std.json.fmt(function_name, .{})});
    try writer.writeAll(",\"typeArguments\":");
    try writeOptionalJsonArray(allocator, writer, type_args);
    try writer.writeAll(",\"arguments\":");
    try writeOptionalJsonArray(allocator, writer, call_args);
    try writer.writeAll("}");
}

pub fn writeMoveCallTransactionBlock(
    allocator: std.mem.Allocator,
    writer: anytype,
    package_id: []const u8,
    module: []const u8,
    function_name: []const u8,
    type_args: ?[]const u8,
    call_args: ?[]const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
) !void {
    try writer.writeAll("{\"kind\":\"ProgrammableTransaction\",\"commands\":[");
    try writeMoveCallInstruction(allocator, writer, package_id, module, function_name, type_args, call_args);
    try writer.writeAll("]");
    if (sender) |value| {
        try writer.writeAll(",\"sender\":");
        try writer.print("{f}", .{std.json.fmt(value, .{})});
    }
    if (gas_budget) |value| {
        try writer.print(",\"gasBudget\":{}", .{value});
    }
    if (gas_price) |value| {
        try writer.print(",\"gasPrice\":{}", .{value});
    }
    try writer.writeAll("}\n");
}

pub fn writeProgrammableTransaction(
    allocator: std.mem.Allocator,
    writer: anytype,
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    gas_payment_json: ?[]const u8,
) !void {
    const trimmed = std.mem.trim(u8, commands_json, " \n\r\t");
    if (trimmed.len == 0) {
        return error.InvalidCli;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidCli;

    try writer.writeAll("{\"kind\":\"ProgrammableTransaction\",\"commands\":");
    try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
    if (sender) |value| {
        try writer.writeAll(",\"sender\":");
        try writer.print("{f}", .{std.json.fmt(value, .{})});
    }
    if (gas_budget) |value| {
        try writer.print(",\"gasBudget\":{}", .{value});
    }
    if (gas_price) |value| {
        try writer.print(",\"gasPrice\":{}", .{value});
    }
    if (gas_payment_json) |value| {
        try writer.writeAll(",\"gasPayment\":");
        try writeRequiredJsonArray(allocator, writer, value);
    }
    try writer.writeAll("}\n");
}

pub fn buildMoveCallCommandArray(
    allocator: std.mem.Allocator,
    package_id: []const u8,
    module: []const u8,
    function_name: []const u8,
    type_args: ?[]const u8,
    arguments: ?[]const u8,
) ![]u8 {
    var builder = CommandBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendMoveCall(.{
        .package_id = package_id,
        .module = module,
        .function_name = function_name,
        .type_args = type_args,
        .arguments = arguments,
    });
    return builder.finish();
}

pub fn normalizeProgrammaticCommandsFromJson(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, commands_json, " \n\r\t");
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    switch (parsed.value) {
        .array => |array| {
            if (array.items.len == 0) return error.InvalidCli;
            for (array.items) |entry| {
                try validateCommandEntry(entry);
            }
            return try allocator.dupe(u8, trimmed);
        },
        .object => {
            try validateCommandEntry(parsed.value);

            var out = std.ArrayList(u8){};
            errdefer out.deinit(allocator);
            const writer = out.writer(allocator);
            try writer.writeAll("[");
            try writer.print("{f}", .{std.json.fmt(parsed.value, .{})});
            try writer.writeAll("]");
            return out.toOwnedSlice(allocator);
        },
        else => return error.InvalidCli,
    }
}

pub const CommandBuilder = struct {
    allocator: std.mem.Allocator,
    out: std.ArrayList(u8) = .{},
    has_output: bool = false,
    finished: bool = false,

    pub fn init(allocator: std.mem.Allocator) CommandBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CommandBuilder) void {
        self.out.deinit(self.allocator);
    }

    fn ensureWritable(self: *CommandBuilder) !void {
        if (self.finished) return error.InvalidCli;
        if (self.out.items.len == 0) {
            try self.out.writer(self.allocator).writeAll("[");
        }
        if (self.has_output) {
            try self.out.append(self.allocator, ',');
        }
    }

    pub fn appendRawJson(self: *CommandBuilder, commands_json: []const u8) !void {
        if (self.finished) return error.InvalidCli;

        const normalized = try normalizeProgrammaticCommandsFromJson(self.allocator, commands_json);
        defer self.allocator.free(normalized);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, normalized, .{});
        defer parsed.deinit();

        for (parsed.value.array.items) |entry| {
            try self.ensureWritable();
            const writer = self.out.writer(self.allocator);
            try writer.print("{f}", .{std.json.fmt(entry, .{})});
            self.has_output = true;
        }
    }

    pub fn appendMoveCall(self: *CommandBuilder, spec: MoveCallSpec) !void {
        try self.ensureWritable();
        const writer = self.out.writer(self.allocator);
        try writeMoveCallInstruction(
            self.allocator,
            writer,
            spec.package_id,
            spec.module,
            spec.function_name,
            spec.type_args,
            spec.arguments,
        );
        self.has_output = true;
    }

    pub fn appendMakeMoveVec(
        self: *CommandBuilder,
        spec: struct {
            type_json: ?[]const u8 = null,
            elements_json: []const u8,
        },
    ) !void {
        try self.ensureWritable();
        const writer = self.out.writer(self.allocator);
        try writer.writeAll("{\"kind\":\"MakeMoveVec\",\"type\":");
        if (spec.type_json) |type_json| {
            try writeRequiredJsonValue(self.allocator, writer, type_json);
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"elements\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.elements_json);
        try writer.writeAll("}");
        self.has_output = true;
    }

    pub fn appendTransferObjects(self: *CommandBuilder, spec: TransferObjectsSpec) !void {
        try self.ensureWritable();
        const writer = self.out.writer(self.allocator);
        try writer.writeAll("{\"kind\":\"TransferObjects\",\"objects\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.objects_json);
        try writer.writeAll(",\"address\":");
        try writeRequiredJsonValue(self.allocator, writer, spec.address_json);
        try writer.writeAll("}");
        self.has_output = true;
    }

    pub fn appendSplitCoins(self: *CommandBuilder, spec: SplitCoinsSpec) !void {
        try self.ensureWritable();
        const writer = self.out.writer(self.allocator);
        try writer.writeAll("{\"kind\":\"SplitCoins\",\"coin\":");
        try writeRequiredJsonValue(self.allocator, writer, spec.coin_json);
        try writer.writeAll(",\"amounts\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.amounts_json);
        try writer.writeAll("}");
        self.has_output = true;
    }

    pub fn appendMergeCoins(self: *CommandBuilder, spec: MergeCoinsSpec) !void {
        try self.ensureWritable();
        const writer = self.out.writer(self.allocator);
        try writer.writeAll("{\"kind\":\"MergeCoins\",\"destination\":");
        try writeRequiredJsonValue(self.allocator, writer, spec.destination_json);
        try writer.writeAll(",\"sources\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.sources_json);
        try writer.writeAll("}");
        self.has_output = true;
    }

    pub fn appendPublish(self: *CommandBuilder, spec: PublishSpec) !void {
        try self.ensureWritable();
        const writer = self.out.writer(self.allocator);
        try writer.writeAll("{\"kind\":\"Publish\",\"modules\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.modules_json);
        try writer.writeAll(",\"dependencies\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.dependencies_json);
        try writer.writeAll("}");
        self.has_output = true;
    }

    pub fn appendUpgrade(self: *CommandBuilder, spec: UpgradeSpec) !void {
        try self.ensureWritable();
        const writer = self.out.writer(self.allocator);
        try writer.writeAll("{\"kind\":\"Upgrade\",\"modules\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.modules_json);
        try writer.writeAll(",\"dependencies\":");
        try writeRequiredJsonArray(self.allocator, writer, spec.dependencies_json);
        try writer.writeAll(",\"package\":");
        try writer.print("{f}", .{std.json.fmt(spec.package_id, .{})});
        try writer.writeAll(",\"ticket\":");
        try writeRequiredJsonValue(self.allocator, writer, spec.ticket_json);
        try writer.writeAll("}");
        self.has_output = true;
    }

    pub fn finish(self: *CommandBuilder) ![]u8 {
        if (self.finished) return error.InvalidCli;
        if (!self.has_output) return error.InvalidCli;

        if (self.out.items.len == 0) {
            try self.out.writer(self.allocator).writeAll("[");
        }
        try self.out.writer(self.allocator).writeAll("]");
        self.finished = true;

        const owned = try self.out.toOwnedSlice(self.allocator);
        self.out = .{};
        return owned;
    }
};

pub fn resolveCommands(
    allocator: std.mem.Allocator,
    source: CommandSource,
) ![]u8 {
    var builder = CommandBuilder.init(allocator);
    defer builder.deinit();

    if (source.command_items.len == 0 and source.commands_json == null) {
        const move_call = source.move_call orelse return error.InvalidCli;
        try builder.appendMoveCall(move_call);
        return builder.finish();
    }

    if (source.move_call != null) return error.InvalidCli;

    if (source.commands_json) |commands| {
        try builder.appendRawJson(commands);
    }
    for (source.command_items) |command_json| {
        try builder.appendRawJson(command_json);
    }

    return builder.finish();
}

pub fn buildExecutePayload(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
    signatures: []const []const u8,
    options_json: ?[]const u8,
) ![]u8 {
    if (options_json) |raw_options| {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_options, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidCli;
    }

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    var writer = out.writer(allocator);

    try writer.writeAll("[");
    try writer.print("{f}", .{std.json.fmt(tx_bytes, .{})});
    try writer.writeAll(",");
    try writer.print("{f}", .{std.json.fmt(signatures, .{})});
    if (options_json != null) {
        try writer.writeAll(",");
        try writer.writeAll(options_json.?);
    }
    try writer.writeAll("]");

    return out.toOwnedSlice(allocator);
}

pub fn buildDryRunPayload(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    var writer = out.writer(allocator);

    try writer.writeAll("[");
    try writer.print("{f}", .{std.json.fmt(tx_bytes, .{})});
    try writer.writeAll("]");

    return out.toOwnedSlice(allocator);
}

pub fn buildProgrammaticTxExecutePayload(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    gas_payment_json: ?[]const u8,
    signatures: []const []const u8,
    options_json: ?[]const u8,
) ![]u8 {
    var tx_block = std.ArrayList(u8){};
    defer tx_block.deinit(allocator);

    {
        const tx_writer = tx_block.writer(allocator);
        try writeProgrammableTransaction(
            allocator,
            tx_writer,
            commands_json,
            sender,
            gas_budget,
            gas_price,
            gas_payment_json,
        );
    }

    const trimmed_tx_block = std.mem.trim(u8, tx_block.items, " \n\r\t");
    return try buildExecutePayload(
        allocator,
        trimmed_tx_block,
        signatures,
        options_json,
    );
}

pub fn buildProgrammaticTxSimulatePayload(
    allocator: std.mem.Allocator,
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    gas_payment_json: ?[]const u8,
    options_json: ?[]const u8,
) ![]u8 {
    var tx_block = std.ArrayList(u8){};
    defer tx_block.deinit(allocator);

    {
        const tx_writer = tx_block.writer(allocator);
        try writeProgrammableTransaction(
            allocator,
            tx_writer,
            commands_json,
            sender,
            gas_budget,
            gas_price,
            gas_payment_json,
        );
    }

    return try buildProgrammaticTxSimulatePayloadFromTransactionBlock(
        allocator,
        std.mem.trim(u8, tx_block.items, " \n\r\t"),
        sender,
        gas_budget,
        gas_price,
        options_json,
    );
}

pub fn buildProgrammaticTxSimulatePayloadFromTransactionBlock(
    allocator: std.mem.Allocator,
    transaction_block_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    options_json: ?[]const u8,
) ![]u8 {
    var parsed_options: ?std.json.Parsed(std.json.Value) = null;
    defer {
        if (parsed_options) |*parsed| {
            parsed.deinit();
        }
    }

    if (options_json) |raw_options| {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_options, .{});
        if (parsed.value != .object) return error.InvalidCli;
        parsed_options = parsed;
    }

    const trimmed_tx_block = std.mem.trim(u8, transaction_block_json, " \n\r\t");
    if (trimmed_tx_block.len == 0) return error.InvalidCli;
    const has_context = sender != null or gas_budget != null or gas_price != null or options_json != null;

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    var writer = out.writer(allocator);

    try writer.writeAll("[");
    try writer.print("{f}", .{std.json.fmt(trimmed_tx_block, .{})});
    if (has_context) {
        try writer.writeAll(",{");

        var written = false;
        if (sender) |value| {
            try writer.print("\"sender\":{f}", .{std.json.fmt(value, .{})});
            written = true;
        }
        if (gas_budget) |value| {
            if (written) try writer.writeAll(",");
            try writer.print("\"gasBudget\":{}", .{value});
            written = true;
        }
        if (gas_price) |value| {
            if (written) try writer.writeAll(",");
            try writer.print("\"gasPrice\":{}", .{value});
            written = true;
        }
        if (parsed_options) |options| {
            if (written) try writer.writeAll(",");
            try writer.print("\"options\":{f}", .{std.json.fmt(options.value, .{})});
        }

        try writer.writeAll("}");
    }
    try writer.writeAll("]");

    return out.toOwnedSlice(allocator);
}

pub const ProgrammaticTxContext = struct {
    commands_json: []const u8,
    sender: ?[]const u8,
    gas_budget: ?u64,
    gas_price: ?u64,
    gas_payment_json: ?[]const u8,
    options_json: ?[]const u8,

    pub fn initResolved(
        allocator: std.mem.Allocator,
        source: CommandSource,
        sender: ?[]const u8,
        gas_budget: ?u64,
        gas_price: ?u64,
        gas_payment_json: ?[]const u8,
        options_json: ?[]const u8,
    ) !ProgrammaticTxContext {
        const commands_json = try resolveCommands(allocator, source);
        return .{
            .commands_json = commands_json,
            .sender = sender,
            .gas_budget = gas_budget,
            .gas_price = gas_price,
            .gas_payment_json = gas_payment_json,
            .options_json = options_json,
        };
    }

    pub fn deinit(self: ProgrammaticTxContext, allocator: std.mem.Allocator) void {
        allocator.free(self.commands_json);
    }

    pub fn buildTransactionBlock(
        self: ProgrammaticTxContext,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var tx_block = std.ArrayList(u8){};
        errdefer tx_block.deinit(allocator);

        const tx_writer = tx_block.writer(allocator);
        try writeProgrammableTransaction(
            allocator,
            tx_writer,
            self.commands_json,
            self.sender,
            self.gas_budget,
            self.gas_price,
            self.gas_payment_json,
        );
        return tx_block.toOwnedSlice(allocator);
    }

    pub fn buildInspectPayload(
        self: ProgrammaticTxContext,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return buildProgrammaticTxSimulatePayload(
            allocator,
            self.commands_json,
            self.sender,
            self.gas_budget,
            self.gas_price,
            self.gas_payment_json,
            self.options_json,
        );
    }

    pub fn buildExecutePayload(
        self: ProgrammaticTxContext,
        allocator: std.mem.Allocator,
        signatures: []const []const u8,
    ) ![]u8 {
        return buildProgrammaticTxExecutePayload(
            allocator,
            self.commands_json,
            self.sender,
            self.gas_budget,
            self.gas_price,
            self.gas_payment_json,
            signatures,
            self.options_json,
        );
    }
};

pub const PreparedProgrammaticTxRequest = struct {
    request: ProgrammaticTxRequest,
    owned_commands_json: []u8,
    owned_sender: ?[]u8 = null,
    owned_gas_payment_json: ?[]u8 = null,
    owned_options_json: ?[]u8 = null,
    signatures: std.ArrayListUnmanaged([]const u8) = .{},
    owned_signatures: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *PreparedProgrammaticTxRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.owned_commands_json);
        if (self.owned_sender) |value| allocator.free(value);
        if (self.owned_gas_payment_json) |value| allocator.free(value);
        if (self.owned_options_json) |value| allocator.free(value);
        for (self.owned_signatures.items) |value| allocator.free(value);
        self.signatures.deinit(allocator);
        self.owned_signatures.deinit(allocator);
    }

    pub fn buildInspectPayload(
        self: PreparedProgrammaticTxRequest,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return buildProgrammaticTxSimulatePayload(
            allocator,
            self.owned_commands_json,
            self.request.sender,
            self.request.gas_budget,
            self.request.gas_price,
            self.request.gas_payment_json,
            self.request.options_json,
        );
    }

    pub fn buildExecutePayload(
        self: PreparedProgrammaticTxRequest,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return buildProgrammaticTxExecutePayload(
            allocator,
            self.owned_commands_json,
            self.request.sender,
            self.request.gas_budget,
            self.request.gas_price,
            self.request.gas_payment_json,
            self.request.signatures,
            self.request.options_json,
        );
    }
};

pub const ProgrammaticTxRequest = struct {
    source: CommandSource,
    sender: ?[]const u8 = null,
    gas_budget: ?u64 = null,
    gas_price: ?u64 = null,
    gas_payment_json: ?[]const u8 = null,
    signatures: []const []const u8 = &.{},
    options_json: ?[]const u8 = null,
    wait_for_confirmation: bool = false,
    confirm_timeout_ms: u64 = std.math.maxInt(u64),
    confirm_poll_ms: u64 = 2_000,

    pub fn prepare(
        self: ProgrammaticTxRequest,
        allocator: std.mem.Allocator,
    ) !PreparedProgrammaticTxRequest {
        return prepareRequest(allocator, self);
    }

    pub fn resolveContext(
        self: ProgrammaticTxRequest,
        allocator: std.mem.Allocator,
    ) !ProgrammaticTxContext {
        return try ProgrammaticTxContext.initResolved(
            allocator,
            self.source,
            self.sender,
            self.gas_budget,
            self.gas_price,
            self.gas_payment_json,
            self.options_json,
        );
    }

    pub fn buildInspectPayload(
        self: ProgrammaticTxRequest,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var context = try self.resolveContext(allocator);
        defer context.deinit(allocator);
        return try context.buildInspectPayload(allocator);
    }

    pub fn buildExecutePayload(
        self: ProgrammaticTxRequest,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var context = try self.resolveContext(allocator);
        defer context.deinit(allocator);
        return try context.buildExecutePayload(allocator, self.signatures);
    }
};

pub fn prepareRequest(
    allocator: std.mem.Allocator,
    request: ProgrammaticTxRequest,
) !PreparedProgrammaticTxRequest {
    var prepared = PreparedProgrammaticTxRequest{
        .request = request,
        .owned_commands_json = try resolveCommands(allocator, request.source),
    };
    errdefer prepared.deinit(allocator);

    prepared.request.source = .{ .commands_json = prepared.owned_commands_json };

    if (request.sender) |value| {
        prepared.owned_sender = try allocator.dupe(u8, value);
        prepared.request.sender = prepared.owned_sender.?;
    }

    if (request.gas_payment_json) |value| {
        prepared.owned_gas_payment_json = try allocator.dupe(u8, value);
        prepared.request.gas_payment_json = prepared.owned_gas_payment_json.?;
    }

    if (request.options_json) |value| {
        prepared.owned_options_json = try allocator.dupe(u8, value);
        prepared.request.options_json = prepared.owned_options_json.?;
    }

    for (request.signatures) |value| {
        const copy = try allocator.dupe(u8, value);
        try prepared.signatures.append(allocator, copy);
        try prepared.owned_signatures.append(allocator, copy);
    }
    prepared.request.signatures = prepared.signatures.items;

    return prepared;
}

test "validateCommandEntry rejects malformed known command" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        "{\"kind\":\"TransferObjects\",\"objects\":[\"0xabc\"]}",
        .{},
    );
    defer parsed.deinit();

    try testing.expectError(error.InvalidCli, validateCommandEntry(parsed.value));
}

test "resolveCommands accepts unknown future command kinds" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const commands = try resolveCommands(allocator, .{
        .commands_json = "[{\"kind\":\"CustomFutureCommand\",\"value\":1}]",
    });
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
    try testing.expectEqualStrings("CustomFutureCommand", parsed.value.array.items[0].object.get("kind").?.string);
}

test "ProgrammaticTxContext builds inspect and execute payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = try ProgrammaticTxContext.initResolved(
        allocator,
        .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        "0xabc",
        1000,
        7,
        "{\"skipChecks\":true}",
    );
    defer context.deinit(allocator);

    const inspect_payload = try context.buildInspectPayload(allocator);
    defer allocator.free(inspect_payload);

    const execute_payload = try context.buildExecutePayload(allocator, &.{"sig-a"});
    defer allocator.free(execute_payload);

    const inspect = try std.json.parseFromSlice(std.json.Value, allocator, inspect_payload, .{});
    defer inspect.deinit();
    try testing.expect(inspect.value == .array);
    try testing.expectEqual(@as(usize, 2), inspect.value.array.items.len);

    const execute = try std.json.parseFromSlice(std.json.Value, allocator, execute_payload, .{});
    defer execute.deinit();
    try testing.expect(execute.value == .array);
    try testing.expectEqual(@as(usize, 3), execute.value.array.items.len);
}

test "buildDryRunPayload wraps tx bytes in a single-parameter array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = try buildDryRunPayload(allocator, "base64-tx-bytes");
    defer allocator.free(payload);

    try testing.expectEqualStrings("[\"base64-tx-bytes\"]", payload);
}

test "prepareRequest normalizes commands and owns request fields" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sender = try allocator.dupe(u8, "0xabc");
    defer allocator.free(sender);
    const options = try allocator.dupe(u8, "{\"showEffects\":true}");
    defer allocator.free(options);
    const signature = try allocator.dupe(u8, "sig-a");
    defer allocator.free(signature);

    var prepared = try prepareRequest(allocator, .{
        .source = .{
            .command_items = &.{
                "{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}",
            },
        },
        .sender = sender,
        .gas_budget = 1000,
        .gas_price = 9,
        .signatures = &.{signature},
        .options_json = options,
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 5_000,
        .confirm_poll_ms = 50,
    });
    defer prepared.deinit(allocator);

    try testing.expect(prepared.request.source.commands_json != null);
    try testing.expectEqualStrings(
        "[{\"kind\":\"MoveCall\",\"package\":\"0x2\",\"module\":\"counter\",\"function\":\"increment\",\"typeArguments\":[],\"arguments\":[\"0xabc\"]}]",
        prepared.request.source.commands_json.?,
    );
    try testing.expect(prepared.request.sender.?.ptr != sender.ptr);
    try testing.expect(prepared.request.options_json.?.ptr != options.ptr);
    try testing.expect(prepared.request.signatures[0].ptr != signature.ptr);
    try testing.expectEqualStrings("0xabc", prepared.request.sender.?);
    try testing.expectEqualStrings("{\"showEffects\":true}", prepared.request.options_json.?);
    try testing.expectEqualStrings("sig-a", prepared.request.signatures[0]);
    try testing.expect(prepared.request.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 5_000), prepared.request.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 50), prepared.request.confirm_poll_ms);
}

test "PreparedProgrammaticTxRequest builds payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try (ProgrammaticTxRequest{
        .source = .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        .sender = "0xabc",
        .signatures = &.{"sig-a"},
    }).prepare(allocator);
    defer prepared.deinit(allocator);

    const inspect_payload = try prepared.buildInspectPayload(allocator);
    defer allocator.free(inspect_payload);
    const execute_payload = try prepared.buildExecutePayload(allocator);
    defer allocator.free(execute_payload);

    const inspect = try std.json.parseFromSlice(std.json.Value, allocator, inspect_payload, .{});
    defer inspect.deinit();
    const execute = try std.json.parseFromSlice(std.json.Value, allocator, execute_payload, .{});
    defer execute.deinit();

    try testing.expect(inspect.value == .array);
    try testing.expect(execute.value == .array);
}

test "ProgrammaticTxRequest builds payloads and keeps execution settings" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const request = ProgrammaticTxRequest{
        .source = .{
            .move_call = .{
                .package_id = "0x2",
                .module = "counter",
                .function_name = "increment",
                .type_args = "[]",
                .arguments = "[\"0xabc\"]",
            },
        },
        .sender = "0xabc",
        .gas_budget = 1000,
        .gas_price = 7,
        .signatures = &.{"sig-a"},
        .options_json = "{\"skipChecks\":true}",
        .wait_for_confirmation = true,
        .confirm_timeout_ms = 5_000,
        .confirm_poll_ms = 10,
    };

    const inspect_payload = try request.buildInspectPayload(allocator);
    defer allocator.free(inspect_payload);

    const execute_payload = try request.buildExecutePayload(allocator);
    defer allocator.free(execute_payload);

    try testing.expect(request.wait_for_confirmation);
    try testing.expectEqual(@as(u64, 5_000), request.confirm_timeout_ms);
    try testing.expectEqual(@as(u64, 10), request.confirm_poll_ms);

    const inspect = try std.json.parseFromSlice(std.json.Value, allocator, inspect_payload, .{});
    defer inspect.deinit();
    const execute = try std.json.parseFromSlice(std.json.Value, allocator, execute_payload, .{});
    defer execute.deinit();

    try testing.expect(inspect.value == .array);
    try testing.expect(execute.value == .array);
}

test "CommandBuilder builds mixed typed command arrays" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = CommandBuilder.init(allocator);
    defer builder.deinit();

    try builder.appendMoveCall(.{
        .package_id = "0x2",
        .module = "counter",
        .function_name = "increment",
        .type_args = "[]",
        .arguments = "[\"0xabc\"]",
    });
    try builder.appendMakeMoveVec(.{
        .type_json = "\"0x2::sui::SUI\"",
        .elements_json = "[\"0xcoin\"]",
    });
    try builder.appendTransferObjects(.{
        .objects_json = "[\"0xcoin\"]",
        .address_json = "\"0xreceiver\"",
    });
    try builder.appendSplitCoins(.{
        .coin_json = "\"0xcoin\"",
        .amounts_json = "[1,2]",
    });
    try builder.appendMergeCoins(.{
        .destination_json = "\"0xdest\"",
        .sources_json = "[\"0xsrc\"]",
    });
    try builder.appendPublish(.{
        .modules_json = "[\"AQID\"]",
        .dependencies_json = "[\"0x2\"]",
    });
    try builder.appendUpgrade(.{
        .modules_json = "[\"BAUG\"]",
        .dependencies_json = "[\"0x2\",\"0x3\"]",
        .package_id = "0x42",
        .ticket_json = "{\"Result\":0}",
    });

    const commands = try builder.finish();
    defer allocator.free(commands);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, commands, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .array);
    try testing.expectEqual(@as(usize, 7), parsed.value.array.items.len);
    try testing.expectEqualStrings("MoveCall", parsed.value.array.items[0].object.get("kind").?.string);
    try testing.expectEqualStrings("MakeMoveVec", parsed.value.array.items[1].object.get("kind").?.string);
    try testing.expectEqualStrings("TransferObjects", parsed.value.array.items[2].object.get("kind").?.string);
    try testing.expectEqualStrings("SplitCoins", parsed.value.array.items[3].object.get("kind").?.string);
    try testing.expectEqualStrings("MergeCoins", parsed.value.array.items[4].object.get("kind").?.string);
    try testing.expectEqualStrings("Publish", parsed.value.array.items[5].object.get("kind").?.string);
    try testing.expectEqualStrings("Upgrade", parsed.value.array.items[6].object.get("kind").?.string);
    try testing.expectEqualStrings("0x42", parsed.value.array.items[6].object.get("package").?.string);
    try testing.expectEqual(@as(i64, 0), parsed.value.array.items[6].object.get("ticket").?.object.get("Result").?.integer);
}

test "CommandBuilder rejects invalid typed command fragments" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = CommandBuilder.init(allocator);
    defer builder.deinit();

    try testing.expectError(error.InvalidCli, builder.appendTransferObjects(.{
        .objects_json = "\"0xcoin\"",
        .address_json = "\"0xreceiver\"",
    }));
    try testing.expectError(error.InvalidCli, builder.appendSplitCoins(.{
        .coin_json = "",
        .amounts_json = "[1]",
    }));
    try testing.expectError(error.InvalidCli, builder.appendPublish(.{
        .modules_json = "\"AQID\"",
        .dependencies_json = "[\"0x2\"]",
    }));
    try testing.expectError(error.InvalidCli, builder.appendUpgrade(.{
        .modules_json = "[\"BAUG\"]",
        .dependencies_json = "[\"0x2\"]",
        .package_id = "0x42",
        .ticket_json = "",
    }));
}

test "buildJsonStringArray builds a JSON string array" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const values = [_][]const u8{
        "0x2::sui::SUI",
        "  0x2::balance::Balance<0x2::sui::SUI>  ",
    };

    const json = try buildJsonStringArray(allocator, &values);
    defer allocator.free(json);

    try testing.expectEqualStrings("[\"0x2::sui::SUI\",\"0x2::balance::Balance<0x2::sui::SUI>\"]", json);
}

test "buildCliValueArray preserves JSON values and stringifies bare tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const values = [_][]const u8{
        "0xabc",
        "7",
        "true",
        "{\"nested\":1}",
    };

    const json = try buildCliValueArray(allocator, &values);
    defer allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    try testing.expectEqualStrings("0xabc", parsed.value.array.items[0].string);
    try testing.expectEqual(@as(i64, 7), parsed.value.array.items[1].integer);
    try testing.expect(parsed.value.array.items[2].bool);
    try testing.expectEqual(@as(i64, 1), parsed.value.array.items[3].object.get("nested").?.integer);
}

test "buildCliValueJson preserves JSON values and stringifies bare tokens" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bare = try buildCliValueJson(allocator, "0xabc");
    defer allocator.free(bare);
    try testing.expectEqualStrings("\"0xabc\"", bare);

    const json_number = try buildCliValueJson(allocator, "7");
    defer allocator.free(json_number);
    try testing.expectEqualStrings("7", json_number);
}

test "buildCliPtbArgumentArray preserves PTB references and fallback values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const values = [_][]const u8{
        "ptb:gas",
        "ptb:input:0",
        "ptb:result:1",
        "ptb:nested:2:3",
        "0xabc",
        "7",
    };

    const json = try buildCliPtbArgumentArray(allocator, &values);
    defer allocator.free(json);

    try testing.expectEqualStrings("[\"GasCoin\",{\"Input\":0},{\"Result\":1},{\"NestedResult\":[2,3]},\"0xabc\",7]", json);
}

test "buildCliPtbArgumentJson preserves PTB references and fallback values" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const gas = try buildCliPtbArgumentJson(allocator, "ptb:gas");
    defer allocator.free(gas);
    try testing.expectEqualStrings("\"GasCoin\"", gas);

    const nested = try buildCliPtbArgumentJson(allocator, "ptb:nested:4:5");
    defer allocator.free(nested);
    try testing.expectEqualStrings("{\"NestedResult\":[4,5]}", nested);

    const fallback = try buildCliPtbArgumentJson(allocator, "0xabc");
    defer allocator.free(fallback);
    try testing.expectEqualStrings("\"0xabc\"", fallback);
}
