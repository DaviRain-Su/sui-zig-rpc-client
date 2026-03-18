const std = @import("std");
const tx_request_builder = @import("./tx_request_builder.zig");

pub const ArtifactDataKind = enum {
    tx_bytes,
    transaction_block,
};

pub const ExecutePayloadKind = enum {
    execute_payload,
};

pub const InspectPayloadKind = enum {
    inspect_payload,
};

pub const BuildArtifactKind = enum {
    instruction,
    transaction_block,
};

pub const OwnedExecutePayloadSummary = struct {
    payload_kind: ExecutePayloadKind = .execute_payload,
    data_kind: ArtifactDataKind = .tx_bytes,
    payload_items_count: usize = 0,
    data_length: usize = 0,
    signature_count: usize = 0,
    has_options: bool = false,
    options_keys_count: usize = 0,
    tx_kind: ?[]u8 = null,
    sender: ?[]u8 = null,
    gas_budget: ?u64 = null,
    gas_price: ?u64 = null,
    command_count: usize = 0,

    pub fn deinit(self: *OwnedExecutePayloadSummary, allocator: std.mem.Allocator) void {
        if (self.tx_kind) |value| allocator.free(value);
        if (self.sender) |value| allocator.free(value);
    }
};

pub const OwnedInspectPayloadSummary = struct {
    payload_kind: InspectPayloadKind = .inspect_payload,
    data_kind: ArtifactDataKind = .tx_bytes,
    payload_items_count: usize = 0,
    data_length: usize = 0,
    has_context: bool = false,
    has_options: bool = false,
    options_keys_count: usize = 0,
    tx_kind: ?[]u8 = null,
    sender: ?[]u8 = null,
    gas_budget: ?u64 = null,
    gas_price: ?u64 = null,
    command_count: usize = 0,

    pub fn deinit(self: *OwnedInspectPayloadSummary, allocator: std.mem.Allocator) void {
        if (self.tx_kind) |value| allocator.free(value);
        if (self.sender) |value| allocator.free(value);
    }
};

pub const OwnedBuildArtifactSummary = struct {
    artifact_kind: BuildArtifactKind,
    kind: ?[]u8 = null,
    sender: ?[]u8 = null,
    gas_budget: ?u64 = null,
    gas_price: ?u64 = null,
    command_count: usize = 0,
    package: ?[]u8 = null,
    module: ?[]u8 = null,
    function_name: ?[]u8 = null,
    type_arguments_count: usize = 0,
    arguments_count: usize = 0,

    pub fn deinit(self: *OwnedBuildArtifactSummary, allocator: std.mem.Allocator) void {
        if (self.kind) |value| allocator.free(value);
        if (self.sender) |value| allocator.free(value);
        if (self.package) |value| allocator.free(value);
        if (self.module) |value| allocator.free(value);
        if (self.function_name) |value| allocator.free(value);
    }
};

pub const OwnedProgrammaticArtifactSummary = union(enum) {
    transaction_block: OwnedBuildArtifactSummary,
    inspect_payload: OwnedInspectPayloadSummary,
    execute_payload: OwnedExecutePayloadSummary,

    pub fn deinit(self: *OwnedProgrammaticArtifactSummary, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .transaction_block => |*value| value.deinit(allocator),
            .inspect_payload => |*value| value.deinit(allocator),
            .execute_payload => |*value| value.deinit(allocator),
        }
    }
};

fn parseOptionalU64(value: ?std.json.Value) ?u64 {
    const raw = value orelse return null;
    return switch (raw) {
        .integer => |number| if (number < 0) null else @as(u64, @intCast(number)),
        else => null,
    };
}

fn fillTransactionBlockFields(
    allocator: std.mem.Allocator,
    tx_data_json: []const u8,
    data_kind: *ArtifactDataKind,
    tx_kind: *?[]u8,
    sender: *?[]u8,
    gas_budget: *?u64,
    gas_price: *?u64,
    command_count: *usize,
) !void {
    const tx_data = std.json.parseFromSlice(std.json.Value, allocator, tx_data_json, .{}) catch {
        data_kind.* = .tx_bytes;
        return;
    };
    defer tx_data.deinit();

    if (tx_data.value == .object and tx_data.value.object.get("kind") != null) {
        data_kind.* = .transaction_block;
        const object = tx_data.value.object;

        if (object.get("kind")) |kind_value| {
            if (kind_value == .string) {
                tx_kind.* = try allocator.dupe(u8, kind_value.string);
            }
        }
        if (object.get("sender")) |sender_value| {
            if (sender_value == .string) {
                sender.* = try allocator.dupe(u8, sender_value.string);
            }
        }
        gas_budget.* = parseOptionalU64(object.get("gasBudget"));
        gas_price.* = parseOptionalU64(object.get("gasPrice"));
        if (object.get("commands")) |commands_value| {
            if (commands_value == .array) {
                command_count.* = commands_value.array.items.len;
            }
        }
        return;
    }

    data_kind.* = .tx_bytes;
}

pub fn extractExecutePayloadSummary(
    allocator: std.mem.Allocator,
    payload_json: []const u8,
) !OwnedExecutePayloadSummary {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload_json, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidResponse;
    const items = parsed.value.array.items;
    if (items.len < 2) return error.InvalidResponse;
    if (items[0] != .string) return error.InvalidResponse;
    if (items[1] != .array) return error.InvalidResponse;

    var summary = OwnedExecutePayloadSummary{
        .payload_items_count = items.len,
        .data_length = items[0].string.len,
        .signature_count = items[1].array.items.len,
        .has_options = items.len >= 3 and items[2] != .null,
        .options_keys_count = if (items.len >= 3 and items[2] == .object) items[2].object.count() else 0,
    };
    try fillTransactionBlockFields(
        allocator,
        items[0].string,
        &summary.data_kind,
        &summary.tx_kind,
        &summary.sender,
        &summary.gas_budget,
        &summary.gas_price,
        &summary.command_count,
    );

    return summary;
}

pub fn extractInspectPayloadSummary(
    allocator: std.mem.Allocator,
    payload_json: []const u8,
) !OwnedInspectPayloadSummary {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload_json, .{});
    defer parsed.deinit();

    if (parsed.value != .array) return error.InvalidResponse;
    const items = parsed.value.array.items;
    if (items.len == 0) return error.InvalidResponse;
    if (items[0] != .string) return error.InvalidResponse;
    if (items.len >= 2 and items[1] != .object) return error.InvalidResponse;

    var summary = OwnedInspectPayloadSummary{
        .payload_items_count = items.len,
        .data_length = items[0].string.len,
        .has_context = items.len >= 2,
    };

    try fillTransactionBlockFields(
        allocator,
        items[0].string,
        &summary.data_kind,
        &summary.tx_kind,
        &summary.sender,
        &summary.gas_budget,
        &summary.gas_price,
        &summary.command_count,
    );

    if (items.len >= 2) {
        const context = items[1].object;
        if (context.get("sender")) |sender_value| {
            if (summary.sender == null and sender_value == .string) {
                summary.sender = try allocator.dupe(u8, sender_value.string);
            }
        }
        if (summary.gas_budget == null) summary.gas_budget = parseOptionalU64(context.get("gasBudget"));
        if (summary.gas_price == null) summary.gas_price = parseOptionalU64(context.get("gasPrice"));
        if (context.get("options")) |options_value| {
            summary.has_options = true;
            if (options_value == .object) {
                summary.options_keys_count = options_value.object.count();
            }
        }
    }

    return summary;
}

pub fn extractBuildArtifactSummary(
    allocator: std.mem.Allocator,
    artifact_json: []const u8,
) !OwnedBuildArtifactSummary {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, artifact_json, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidResponse;
    const object = parsed.value.object;
    const kind_value = object.get("kind") orelse return error.InvalidResponse;
    if (kind_value != .string) return error.InvalidResponse;

    if (std.mem.eql(u8, kind_value.string, "ProgrammableTransaction")) {
        var summary = OwnedBuildArtifactSummary{
            .artifact_kind = .transaction_block,
            .kind = try allocator.dupe(u8, kind_value.string),
            .gas_budget = parseOptionalU64(object.get("gasBudget")),
            .gas_price = parseOptionalU64(object.get("gasPrice")),
        };
        if (object.get("sender")) |sender_value| {
            if (sender_value == .string) {
                summary.sender = try allocator.dupe(u8, sender_value.string);
            }
        }
        if (object.get("commands")) |commands_value| {
            if (commands_value == .array) {
                summary.command_count = commands_value.array.items.len;
            }
        }
        return summary;
    }

    if (std.mem.eql(u8, kind_value.string, "MoveCall")) {
        var summary = OwnedBuildArtifactSummary{
            .artifact_kind = .instruction,
            .kind = try allocator.dupe(u8, kind_value.string),
        };
        if (object.get("package")) |package_value| {
            if (package_value == .string) {
                summary.package = try allocator.dupe(u8, package_value.string);
            }
        }
        if (object.get("module")) |module_value| {
            if (module_value == .string) {
                summary.module = try allocator.dupe(u8, module_value.string);
            }
        }
        if (object.get("function")) |function_value| {
            if (function_value == .string) {
                summary.function_name = try allocator.dupe(u8, function_value.string);
            }
        }
        if (object.get("typeArguments")) |type_arguments_value| {
            if (type_arguments_value == .array) {
                summary.type_arguments_count = type_arguments_value.array.items.len;
            }
        }
        if (object.get("arguments")) |arguments_value| {
            if (arguments_value == .array) {
                summary.arguments_count = arguments_value.array.items.len;
            }
        }
        return summary;
    }

    return error.InvalidResponse;
}

pub fn summarizeProgrammaticArtifact(
    allocator: std.mem.Allocator,
    kind: tx_request_builder.ProgrammaticArtifactKind,
    artifact_json: []const u8,
) !OwnedProgrammaticArtifactSummary {
    return switch (kind) {
        .transaction_block => .{ .transaction_block = try extractBuildArtifactSummary(allocator, artifact_json) },
        .inspect_payload => .{ .inspect_payload = try extractInspectPayloadSummary(allocator, artifact_json) },
        .execute_payload => .{ .execute_payload = try extractExecutePayloadSummary(allocator, artifact_json) },
    };
}

test "extractExecutePayloadSummary parses execute payload transaction blocks" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractExecutePayloadSummary(allocator,
        \\["{\"kind\":\"ProgrammableTransaction\",\"sender\":\"0xabc\",\"gasBudget\":1200,\"gasPrice\":8,\"commands\":[{\"kind\":\"MoveCall\"},{\"kind\":\"TransferObjects\"}]}",["sig-a","sig-b"],{"showEffects":true,"showEvents":true}]
    );
    defer summary.deinit(allocator);

    try testing.expectEqual(ExecutePayloadKind.execute_payload, summary.payload_kind);
    try testing.expectEqual(ArtifactDataKind.transaction_block, summary.data_kind);
    try testing.expectEqual(@as(usize, 3), summary.payload_items_count);
    try testing.expectEqual(@as(usize, 2), summary.signature_count);
    try testing.expect(summary.has_options);
    try testing.expectEqual(@as(usize, 2), summary.options_keys_count);
    try testing.expectEqualStrings("ProgrammableTransaction", summary.tx_kind.?);
    try testing.expectEqualStrings("0xabc", summary.sender.?);
    try testing.expectEqual(@as(u64, 1200), summary.gas_budget.?);
    try testing.expectEqual(@as(u64, 8), summary.gas_price.?);
    try testing.expectEqual(@as(usize, 2), summary.command_count);
}

test "extractExecutePayloadSummary parses raw tx bytes payloads" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractExecutePayloadSummary(allocator,
        \\["AAABBB",["sig-a"],{"showEffects":true}]
    );
    defer summary.deinit(allocator);

    try testing.expectEqual(ArtifactDataKind.tx_bytes, summary.data_kind);
    try testing.expectEqual(@as(usize, 3), summary.payload_items_count);
    try testing.expectEqual(@as(usize, 6), summary.data_length);
    try testing.expectEqual(@as(usize, 1), summary.signature_count);
    try testing.expect(summary.has_options);
    try testing.expectEqual(@as(usize, 1), summary.options_keys_count);
    try testing.expect(summary.tx_kind == null);
    try testing.expect(summary.sender == null);
    try testing.expect(summary.gas_budget == null);
    try testing.expect(summary.gas_price == null);
    try testing.expectEqual(@as(usize, 0), summary.command_count);
}

test "extractBuildArtifactSummary parses move-call instruction artifacts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractBuildArtifactSummary(allocator,
        \\{"kind":"MoveCall","package":"0x2","module":"counter","function":"increment","typeArguments":["T"],"arguments":["0xabc",1]}
    );
    defer summary.deinit(allocator);

    try testing.expectEqual(BuildArtifactKind.instruction, summary.artifact_kind);
    try testing.expectEqualStrings("MoveCall", summary.kind.?);
    try testing.expectEqualStrings("0x2", summary.package.?);
    try testing.expectEqualStrings("counter", summary.module.?);
    try testing.expectEqualStrings("increment", summary.function_name.?);
    try testing.expectEqual(@as(usize, 1), summary.type_arguments_count);
    try testing.expectEqual(@as(usize, 2), summary.arguments_count);
    try testing.expect(summary.sender == null);
}

test "extractBuildArtifactSummary parses programmable transaction block artifacts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractBuildArtifactSummary(allocator,
        \\{"kind":"ProgrammableTransaction","sender":"0xabc","gasBudget":1000,"gasPrice":7,"commands":[{"kind":"MoveCall"}]}
    );
    defer summary.deinit(allocator);

    try testing.expectEqual(BuildArtifactKind.transaction_block, summary.artifact_kind);
    try testing.expectEqualStrings("ProgrammableTransaction", summary.kind.?);
    try testing.expectEqualStrings("0xabc", summary.sender.?);
    try testing.expectEqual(@as(u64, 1000), summary.gas_budget.?);
    try testing.expectEqual(@as(u64, 7), summary.gas_price.?);
    try testing.expectEqual(@as(usize, 1), summary.command_count);
    try testing.expect(summary.package == null);
    try testing.expect(summary.module == null);
    try testing.expect(summary.function_name == null);
}

test "extractInspectPayloadSummary parses inspect payload artifacts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractInspectPayloadSummary(allocator,
        \\["{\"kind\":\"ProgrammableTransaction\",\"sender\":\"0xabc\",\"gasBudget\":1000,\"gasPrice\":7,\"commands\":[{\"kind\":\"MoveCall\"}]}",{"sender":"0xabc","gasBudget":1000,"gasPrice":7,"options":{"skipChecks":true}}]
    );
    defer summary.deinit(allocator);

    try testing.expectEqual(InspectPayloadKind.inspect_payload, summary.payload_kind);
    try testing.expectEqual(ArtifactDataKind.transaction_block, summary.data_kind);
    try testing.expectEqual(@as(usize, 2), summary.payload_items_count);
    try testing.expect(summary.has_context);
    try testing.expect(summary.has_options);
    try testing.expectEqual(@as(usize, 1), summary.options_keys_count);
    try testing.expectEqualStrings("ProgrammableTransaction", summary.tx_kind.?);
    try testing.expectEqualStrings("0xabc", summary.sender.?);
    try testing.expectEqual(@as(u64, 1000), summary.gas_budget.?);
    try testing.expectEqual(@as(u64, 7), summary.gas_price.?);
    try testing.expectEqual(@as(usize, 1), summary.command_count);
}

test "summarizeProgrammaticArtifact dispatches by artifact kind" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try summarizeProgrammaticArtifact(
        allocator,
        .execute_payload,
        "[\"AAABBB\",[\"sig-a\"],{\"showEffects\":true}]",
    );
    defer summary.deinit(allocator);

    switch (summary) {
        .execute_payload => |value| {
            try testing.expectEqual(ArtifactDataKind.tx_bytes, value.data_kind);
            try testing.expectEqual(@as(usize, 1), value.signature_count);
        },
        else => return error.TestUnexpectedResult,
    }
}
