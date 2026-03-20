const std = @import("std");

pub const artifact_kind = "wallet_intent";
pub const schema_version: u32 = 1;

pub const ParsedEnvelope = struct {
    request_json: []u8,
    network: ?[]u8 = null,
    execution_mode: ?[]u8 = null,
    policy_json: ?[]u8 = null,
    delegated_session_json: ?[]u8 = null,
    correlation_id: ?[]u8 = null,
    valid_after_ms: ?u64 = null,
    valid_before_ms: ?u64 = null,
    sponsor_mode: ?[]u8 = null,
    sponsor_policy_json: ?[]u8 = null,
    sponsor_gas_source_preference: ?[]u8 = null,
    sponsor_refusal_fallback: ?[]u8 = null,
    payment_reference: ?[]u8 = null,
    payment_memo: ?[]u8 = null,
    invoice_reference: ?[]u8 = null,
    reconciliation_group: ?[]u8 = null,
    execution_lane: ?[]u8 = null,
    gas_lane: ?[]u8 = null,
    conflict_keys_json: ?[]u8 = null,
    conflict_strategy: ?[]u8 = null,

    pub fn deinit(self: *ParsedEnvelope, allocator: std.mem.Allocator) void {
        allocator.free(self.request_json);
        if (self.network) |value| allocator.free(value);
        if (self.execution_mode) |value| allocator.free(value);
        if (self.policy_json) |value| allocator.free(value);
        if (self.delegated_session_json) |value| allocator.free(value);
        if (self.correlation_id) |value| allocator.free(value);
        if (self.sponsor_mode) |value| allocator.free(value);
        if (self.sponsor_policy_json) |value| allocator.free(value);
        if (self.sponsor_gas_source_preference) |value| allocator.free(value);
        if (self.sponsor_refusal_fallback) |value| allocator.free(value);
        if (self.payment_reference) |value| allocator.free(value);
        if (self.payment_memo) |value| allocator.free(value);
        if (self.invoice_reference) |value| allocator.free(value);
        if (self.reconciliation_group) |value| allocator.free(value);
        if (self.execution_lane) |value| allocator.free(value);
        if (self.gas_lane) |value| allocator.free(value);
        if (self.conflict_keys_json) |value| allocator.free(value);
        if (self.conflict_strategy) |value| allocator.free(value);
    }
};

fn renderJsonValueCompact(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})});
}

fn jsonOptionalStringDup(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[]u8 {
    inline for (names) |name| {
        if (object.get(name)) |value| {
            return switch (value) {
                .null => null,
                .string => |text| try allocator.dupe(u8, text),
                else => error.InvalidCli,
            };
        }
    }
    return null;
}

fn jsonOptionalU64(
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?u64 {
    inline for (names) |name| {
        if (object.get(name)) |value| {
            return switch (value) {
                .null => null,
                .integer => |number| blk: {
                    if (number < 0) return error.InvalidCli;
                    break :blk @as(u64, @intCast(number));
                },
                .string => |text| try std.fmt.parseInt(u64, text, 10),
                else => error.InvalidCli,
            };
        }
    }
    return null;
}

fn jsonOptionalCompactValue(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[]u8 {
    inline for (names) |name| {
        if (object.get(name)) |value| {
            return switch (value) {
                .null => null,
                else => try renderJsonValueCompact(allocator, value),
            };
        }
    }
    return null;
}

pub fn defaultNetworkLabelForRpcUrl(rpc_url: []const u8) []const u8 {
    if (std.mem.indexOf(u8, rpc_url, "mainnet") != null) return "sui:mainnet";
    if (std.mem.indexOf(u8, rpc_url, "testnet") != null) return "sui:testnet";
    if (std.mem.indexOf(u8, rpc_url, "devnet") != null) return "sui:devnet";
    if (std.mem.indexOf(u8, rpc_url, "local") != null or std.mem.indexOf(u8, rpc_url, "127.0.0.1") != null or std.mem.indexOf(u8, rpc_url, "localhost") != null) {
        return "sui:localnet";
    }
    return "sui:custom";
}

pub fn validateExecutionMode(value: []const u8) !void {
    if (std.mem.eql(u8, value, "build") or
        std.mem.eql(u8, value, "dry_run") or
        std.mem.eql(u8, value, "send") or
        std.mem.eql(u8, value, "sign") or
        std.mem.eql(u8, value, "sponsor") or
        std.mem.eql(u8, value, "schedule"))
    {
        return;
    }
    return error.InvalidCli;
}

pub fn parseEnvelope(
    allocator: std.mem.Allocator,
    raw_json: []const u8,
) !ParsedEnvelope {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCli;

    const object = parsed.value.object;
    if (object.get("artifact_kind")) |kind_value| {
        if (kind_value != .string or !std.mem.eql(u8, kind_value.string, artifact_kind)) return error.InvalidCli;
    }

    const request_value = object.get("request") orelse object.get("request_artifact") orelse return error.InvalidCli;
    const request_json = switch (request_value) {
        .string => |text| try allocator.dupe(u8, text),
        .object, .array => try renderJsonValueCompact(allocator, request_value),
        else => return error.InvalidCli,
    };
    errdefer allocator.free(request_json);

    var envelope = ParsedEnvelope{
        .request_json = request_json,
        .network = try jsonOptionalStringDup(allocator, object, &.{"network"}),
        .execution_mode = try jsonOptionalStringDup(allocator, object, &.{ "execution_mode", "executionMode" }),
        .policy_json = try jsonOptionalCompactValue(allocator, object, &.{ "policy", "policy_metadata" }),
        .delegated_session_json = try jsonOptionalCompactValue(allocator, object, &.{ "delegated_session", "delegatedSession" }),
        .correlation_id = try jsonOptionalStringDup(allocator, object, &.{ "correlation_id", "correlationId" }),
        .valid_after_ms = try jsonOptionalU64(object, &.{ "valid_after_ms", "validAfterMs" }),
        .valid_before_ms = try jsonOptionalU64(object, &.{ "valid_before_ms", "validBeforeMs" }),
    };
    errdefer envelope.deinit(allocator);

    if (object.get("sponsor")) |sponsor_value| {
        if (sponsor_value != .object) return error.InvalidCli;
        envelope.sponsor_mode = try jsonOptionalStringDup(allocator, sponsor_value.object, &.{"mode"});
        envelope.sponsor_policy_json = try jsonOptionalCompactValue(
            allocator,
            sponsor_value.object,
            &.{ "policy_metadata", "policyMetadata" },
        );
        envelope.sponsor_gas_source_preference = try jsonOptionalStringDup(
            allocator,
            sponsor_value.object,
            &.{ "gas_source_preference", "gasSourcePreference" },
        );
        envelope.sponsor_refusal_fallback = try jsonOptionalStringDup(
            allocator,
            sponsor_value.object,
            &.{ "refusal_fallback", "refusalFallback" },
        );
        if (envelope.valid_after_ms == null) {
            envelope.valid_after_ms = try jsonOptionalU64(sponsor_value.object, &.{ "valid_after_ms", "validAfterMs" });
        }
        if (envelope.valid_before_ms == null) {
            envelope.valid_before_ms = try jsonOptionalU64(sponsor_value.object, &.{ "valid_before_ms", "validBeforeMs" });
        }
    }

    if (object.get("payment")) |payment_value| {
        if (payment_value != .object) return error.InvalidCli;
        envelope.payment_reference = try jsonOptionalStringDup(
            allocator,
            payment_value.object,
            &.{ "payment_reference", "paymentReference", "reference" },
        );
        envelope.payment_memo = try jsonOptionalStringDup(
            allocator,
            payment_value.object,
            &.{ "memo", "payment_memo", "paymentMemo" },
        );
        envelope.invoice_reference = try jsonOptionalStringDup(
            allocator,
            payment_value.object,
            &.{ "invoice_reference", "invoiceReference" },
        );
        envelope.reconciliation_group = try jsonOptionalStringDup(
            allocator,
            payment_value.object,
            &.{ "reconciliation_group", "reconciliationGroup" },
        );
    }

    if (object.get("concurrency")) |concurrency_value| {
        if (concurrency_value != .object) return error.InvalidCli;
        envelope.execution_lane = try jsonOptionalStringDup(
            allocator,
            concurrency_value.object,
            &.{ "execution_lane", "executionLane" },
        );
        envelope.gas_lane = try jsonOptionalStringDup(
            allocator,
            concurrency_value.object,
            &.{ "gas_lane", "gasLane" },
        );
        envelope.conflict_keys_json = try jsonOptionalCompactValue(
            allocator,
            concurrency_value.object,
            &.{ "conflict_keys", "conflictKeys" },
        );
        envelope.conflict_strategy = try jsonOptionalStringDup(
            allocator,
            concurrency_value.object,
            &.{ "conflict_strategy", "conflictStrategy" },
        );
    }

    if (envelope.execution_mode) |value| try validateExecutionMode(value);
    return envelope;
}

test "wallet_intent parseEnvelope reads request and sponsor metadata" {
    const testing = std.testing;

    var parsed = try parseEnvelope(testing.allocator,
        \\{
        \\  "artifact_kind":"wallet_intent",
        \\  "schema_version":1,
        \\  "network":"sui:mainnet",
        \\  "execution_mode":"send",
        \\  "request":{"commands":[{"kind":"MoveCall","package":"0x2","module":"counter","function":"increment","typeArguments":[],"arguments":[7]}],"sender":"0xabc","gasBudget":1200},
        \\  "sponsor":{"mode":"required","policy_metadata":{"tier":"vip"},"gas_source_preference":"sponsor","refusal_fallback":"fail_closed"},
        \\  "payment":{"payment_reference":"pay-1","memo":"coffee","invoice_reference":"inv-7","reconciliation_group":"merchant-a"},
        \\  "concurrency":{"execution_lane":"lane-1","gas_lane":"gas-a","conflict_keys":["shared:pool-1","owned:wallet-1"],"conflict_strategy":"serialize_same_lane"},
        \\  "policy":{"session_key":"0x1"},
        \\  "delegated_session":{"source_kind":"session_registry","selector":"session:wallet-session-1","session_id":"wallet-session-1"},
        \\  "correlation_id":"req-1",
        \\  "valid_after_ms":100,
        \\  "valid_before_ms":200
        \\}
    );
    defer parsed.deinit(testing.allocator);

    try testing.expect(std.mem.indexOf(u8, parsed.request_json, "\"commands\"") != null);
    try testing.expectEqualStrings("sui:mainnet", parsed.network.?);
    try testing.expectEqualStrings("send", parsed.execution_mode.?);
    try testing.expectEqualStrings("{\"session_key\":\"0x1\"}", parsed.policy_json.?);
    try testing.expectEqualStrings("required", parsed.sponsor_mode.?);
    try testing.expectEqualStrings("{\"tier\":\"vip\"}", parsed.sponsor_policy_json.?);
    try testing.expectEqualStrings("sponsor", parsed.sponsor_gas_source_preference.?);
    try testing.expectEqualStrings("fail_closed", parsed.sponsor_refusal_fallback.?);
    try testing.expectEqualStrings("pay-1", parsed.payment_reference.?);
    try testing.expectEqualStrings("coffee", parsed.payment_memo.?);
    try testing.expectEqualStrings("inv-7", parsed.invoice_reference.?);
    try testing.expectEqualStrings("merchant-a", parsed.reconciliation_group.?);
    try testing.expectEqualStrings("lane-1", parsed.execution_lane.?);
    try testing.expectEqualStrings("gas-a", parsed.gas_lane.?);
    try testing.expectEqualStrings("[\"shared:pool-1\",\"owned:wallet-1\"]", parsed.conflict_keys_json.?);
    try testing.expectEqualStrings("serialize_same_lane", parsed.conflict_strategy.?);
    try testing.expectEqualStrings("{\"source_kind\":\"session_registry\",\"selector\":\"session:wallet-session-1\",\"session_id\":\"wallet-session-1\"}", parsed.delegated_session_json.?);
    try testing.expectEqualStrings("req-1", parsed.correlation_id.?);
    try testing.expectEqual(@as(u64, 100), parsed.valid_after_ms.?);
    try testing.expectEqual(@as(u64, 200), parsed.valid_before_ms.?);
}

test "wallet_intent parseEnvelope rejects missing request" {
    const testing = std.testing;
    try testing.expectError(
        error.InvalidCli,
        parseEnvelope(testing.allocator, "{\"artifact_kind\":\"wallet_intent\"}"),
    );
}
