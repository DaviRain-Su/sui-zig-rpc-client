/// ptb_bytes_builder/root.zig - PTB bytes builder module root
const std = @import("std");

// Import sub-modules
pub const types = @import("types.zig");
pub const bcs_encoder = @import("bcs_encoder.zig");
pub const json_parser = @import("json_parser.zig");
pub const transaction = @import("transaction.zig");

// Re-export types
pub const Address = types.Address;
pub const ObjectDigest = types.ObjectDigest;
pub const ObjectRef = types.ObjectRef;
pub const SharedObjectRef = types.SharedObjectRef;
pub const ObjectArg = types.ObjectArg;
pub const CallArg = types.CallArg;
pub const NestedResult = types.NestedResult;
pub const Argument = types.Argument;
pub const StructTag = types.StructTag;
pub const TypeTag = types.TypeTag;
pub const MoveCallCommand = types.MoveCallCommand;
pub const TransferObjectsCommand = types.TransferObjectsCommand;
pub const SplitCoinsCommand = types.SplitCoinsCommand;
pub const MergeCoinsCommand = types.MergeCoinsCommand;
pub const PublishCommand = types.PublishCommand;
pub const MakeMoveVecCommand = types.MakeMoveVecCommand;
pub const UpgradeCommand = types.UpgradeCommand;
pub const Command = types.Command;
pub const ProgrammableTransaction = types.ProgrammableTransaction;
pub const GasData = types.GasData;
pub const TransactionExpiration = types.TransactionExpiration;
pub const TransactionDataV1 = types.TransactionDataV1;

// Re-export BCS encoder functions
pub const parseBcsValueSpec = bcs_encoder.parseBcsValueSpec;
pub const encodeBcsValue = bcs_encoder.encodeBcsValue;
pub const encodeBcsPureValue = bcs_encoder.encodeBcsPureValue;
pub const parseHexAddress32 = bcs_encoder.parseHexAddress32;
pub const encodeTypeTag = bcs_encoder.encodeTypeTag;

// Re-export JSON parser functions
pub const parseSimplifiedTypeTag = json_parser.parseSimplifiedTypeTag;
pub const parseRawBytesJsonValue = json_parser.parseRawBytesJsonValue;
pub const parseRawBytesJsonValueFromString = json_parser.parseRawBytesJsonValueFromString;
pub const encodeSimplifiedTypeTagFromString = json_parser.encodeSimplifiedTypeTagFromString;

// Re-export transaction functions
pub const buildTransactionDataV1Bytes = transaction.buildTransactionDataV1Bytes;
pub const buildTransactionDataV1Base64 = transaction.buildTransactionDataV1Base64;
pub const buildTransactionDataV1BytesFromParts = transaction.buildTransactionDataV1BytesFromParts;
pub const buildTransactionDataV1Base64FromParts = transaction.buildTransactionDataV1Base64FromParts;
pub const buildTransactionDataV1BytesFromJson = transaction.buildTransactionDataV1BytesFromJson;
pub const buildTransactionDataV1Base64FromJson = transaction.buildTransactionDataV1Base64FromJson;

// ============================================================
// Tests
// ============================================================

test "ptb_bytes_builder module imports successfully" {
    _ = types;
    _ = bcs_encoder;
    _ = json_parser;
    _ = transaction;
}

test "re-exports work correctly" {
    const testing = std.testing;

    // Test types
    _ = Address{0} ** 32;
    _ = ObjectRef{ .object_id = Address{0} ** 32, .version = 1, .digest = ObjectDigest{0} ** 32 };
    _ = Argument{ .gas = {} };
    _ = TypeTag{ .u64 = {} };
    _ = Command{ .make_move_vec = .{ .type = null, .elements = &.{} } };
    _ = ProgrammableTransaction{ .inputs = &.{}, .commands = &.{} };
    _ = TransactionDataV1{ .kind = .{ .inputs = &.{}, .commands = &.{} }, .sender = Address{0} ** 32, .gas_data = .{ .payment = &.{}, .owner = Address{0} ** 32, .price = 0, .budget = 0 }, .expiration = .{ .none = {} } };

    // Test functions exist
    _ = parseBcsValueSpec;
    _ = encodeBcsValue;
    _ = parseSimplifiedTypeTag;
    _ = buildTransactionDataV1Bytes;
}

test "end-to-end type usage" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    // Create a type tag
    const tag = TypeTag{ .u64 = {} };
    try testing.expect(tag == .u64);

    // Create an argument
    const arg = Argument{ .input = 0 };
    try testing.expectEqual(@as(u16, 0), arg.input);

    // Parse a type tag from string
    const parsed_tag = try parseSimplifiedTypeTag(allocator, "u64");
    try testing.expect(parsed_tag == .u64);

    // Encode a BCS value
    const encoded = try encodeBcsValue(allocator, "u64", "12345");
    defer allocator.free(encoded);
    try testing.expectEqual(@as(usize, 8), encoded.len);
}
