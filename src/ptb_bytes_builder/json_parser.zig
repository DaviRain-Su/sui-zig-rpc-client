/// ptb_bytes_builder/json_parser.zig - JSON parsing utilities
const std = @import("std");
const types = @import("types.zig");

const TypeTag = types.TypeTag;
const StructTag = types.StructTag;
const Address = types.Address;

/// Parse simplified type tag from string
pub fn parseSimplifiedTypeTag(allocator: std.mem.Allocator, type_str: []const u8) !TypeTag {
    // Remove whitespace
    const trimmed = std.mem.trim(u8, type_str, " \t\n\r");

    // Check for vector
    if (std.mem.startsWith(u8, trimmed, "vector<")) {
        const inner_start = 7;
        const inner_end = std.mem.lastIndexOf(u8, trimmed, ">") orelse return error.InvalidVectorType;
        const inner = trimmed[inner_start..inner_end];

        const inner_tag = try parseSimplifiedTypeTag(allocator, inner);
        const ptr = try allocator.create(TypeTag);
        ptr.* = inner_tag;
        return TypeTag{ .vector = ptr };
    }

    // Check for struct type
    if (std.mem.indexOf(u8, trimmed, "::")) |_| {
        return try parseStructTypeTag(allocator, trimmed);
    }

    // Primitive types
    if (std.mem.eql(u8, trimmed, "bool")) return .bool;
    if (std.mem.eql(u8, trimmed, "u8")) return .u8;
    if (std.mem.eql(u8, trimmed, "u16")) return .u16;
    if (std.mem.eql(u8, trimmed, "u32")) return .u32;
    if (std.mem.eql(u8, trimmed, "u64")) return .u64;
    if (std.mem.eql(u8, trimmed, "u128")) return .u128;
    if (std.mem.eql(u8, trimmed, "u256")) return .u256;
    if (std.mem.eql(u8, trimmed, "address")) return .address;
    if (std.mem.eql(u8, trimmed, "signer")) return .signer;

    return error.UnknownType;
}

/// Parse struct type tag
fn parseStructTypeTag(allocator: std.mem.Allocator, type_str: []const u8) !TypeTag {
    // Format: address::module::name or address::module::name<type1, type2>

    // Find type parameters
    var base_str = type_str;
    var type_params = std.ArrayList(TypeTag).init(allocator);
    defer {
        for (type_params.items) |*tp| tp.deinit(allocator);
        type_params.deinit();
    }

    if (std.mem.indexOf(u8, type_str, "<")) |angle_pos| {
        base_str = type_str[0..angle_pos];

        // Parse type parameters
        const params_start = angle_pos + 1;
        const params_end = std.mem.lastIndexOf(u8, type_str, ">") orelse return error.InvalidTypeParams;
        const params_str = type_str[params_start..params_end];

        // Split by comma
        var iter = std.mem.split(u8, params_str, ",");
        while (iter.next()) |param| {
            const trimmed = std.mem.trim(u8, param, " \t\n\r");
            if (trimmed.len == 0) continue;
            const param_tag = try parseSimplifiedTypeTag(allocator, trimmed);
            try type_params.append(param_tag);
        }
    }

    // Parse address::module::name
    var parts = std.mem.split(u8, base_str, "::");
    const addr_str = parts.next() orelse return error.MissingAddress;
    const module_str = parts.next() orelse return error.MissingModule;
    const name_str = parts.next() orelse return error.MissingName;

    const addr = try parseAddress(addr_str);
    const module_dup = try allocator.dupe(u8, module_str);
    errdefer allocator.free(module_dup);
    const name_dup = try allocator.dupe(u8, name_str);
    errdefer allocator.free(name_dup);

    return TypeTag{
        .struct = .{
            .address = addr,
            .module = module_dup,
            .name = name_dup,
            .type_params = try type_params.toOwnedSlice(),
        },
    };
}

/// Parse address from string
fn parseAddress(value: []const u8) !Address {
    const start = if (std.mem.startsWith(u8, value, "0x")) 2 else 0;
    const hex_part = value[start..];

    var result: Address = [_]u8{0} ** 32;

    if (hex_part.len > 64) return error.AddressTooLong;

    const start_offset = 32 - (hex_part.len / 2);

    for (0..hex_part.len / 2) |i| {
        const hi = try parseHexDigit(hex_part[i * 2]);
        const lo = try parseHexDigit(hex_part[i * 2 + 1]);
        result[start_offset + i] = (hi << 4) | lo;
    }

    return result;
}

/// Parse hex digit
fn parseHexDigit(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHexDigit,
    };
}

/// Parse raw bytes from JSON value
pub fn parseRawBytesJsonValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return switch (value) {
        .string => |s| try parseHexString(allocator, s),
        .array => |arr| {
            var result = std.ArrayList(u8).init(allocator);
            defer result.deinit();
            for (arr.items) |item| {
                const bytes = try parseRawBytesJsonValue(allocator, item);
                defer allocator.free(bytes);
                try result.appendSlice(bytes);
            }
            return result.toOwnedSlice();
        },
        else => error.UnsupportedValueType,
    };
}

/// Parse raw bytes from string
pub fn parseRawBytesJsonValueFromString(allocator: std.mem.Allocator, value_str: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, value_str, .{});
    defer parsed.deinit();
    return try parseRawBytesJsonValue(allocator, parsed.value);
}

/// Parse hex string to bytes
fn parseHexString(allocator: std.mem.Allocator, hex: []const u8) ![]u8 {
    const start = if (std.mem.startsWith(u8, hex, "0x")) 2 else 0;
    const hex_len = hex.len - start;

    if (hex_len % 2 != 0) return error.InvalidHexLength;

    const result = try allocator.alloc(u8, hex_len / 2);
    errdefer allocator.free(result);

    for (0..hex_len / 2) |i| {
        const hi = try parseHexDigit(hex[start + i * 2]);
        const lo = try parseHexDigit(hex[start + i * 2 + 1]);
        result[i] = (hi << 4) | lo;
    }

    return result;
}

/// Encode simplified type tag from string (convenience function)
pub fn encodeSimplifiedTypeTagFromString(allocator: std.mem.Allocator, type_str: []const u8) !TypeTag {
    return try parseSimplifiedTypeTag(allocator, type_str);
}

// ============================================================
// Tests
// ============================================================

test "parseSimplifiedTypeTag primitive types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const bool_tag = try parseSimplifiedTypeTag(allocator, "bool");
    try testing.expect(bool_tag == .bool);

    const u64_tag = try parseSimplifiedTypeTag(allocator, "u64");
    try testing.expect(u64_tag == .u64);

    const address_tag = try parseSimplifiedTypeTag(allocator, "address");
    try testing.expect(address_tag == .address);
}

test "parseSimplifiedTypeTag vector" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var tag = try parseSimplifiedTypeTag(allocator, "vector<u8>");
    defer tag.deinit(allocator);

    try testing.expect(tag == .vector);
    try testing.expect(tag.vector.* == .u8);
}

test "parseSimplifiedTypeTag struct" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var tag = try parseSimplifiedTypeTag(allocator, "0x2::sui::SUI");
    defer tag.deinit(allocator);

    try testing.expect(tag == .struct);
    try testing.expectEqualStrings("sui", tag.struct.module);
    try testing.expectEqualStrings("SUI", tag.struct.name);
}

test "parseSimplifiedTypeTag struct with type params" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var tag = try parseSimplifiedTypeTag(allocator, "0x2::coin::Coin<0x2::sui::SUI>");
    defer tag.deinit(allocator);

    try testing.expect(tag == .struct);
    try testing.expectEqualStrings("coin", tag.struct.module);
    try testing.expectEqual(@as(usize, 1), tag.struct.type_params.len);
}

test "parseAddress" {
    const testing = std.testing;

    const addr = try parseAddress("0x1234");
    try testing.expectEqual(@as(usize, 32), addr.len);
    try testing.expectEqual(@as(u8, 0x12), addr[30]);
    try testing.expectEqual(@as(u8, 0x34), addr[31]);
}

test "parseHexString" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try parseHexString(allocator, "0xabcd");
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 2), result.len);
    try testing.expectEqual(@as(u8, 0xab), result[0]);
    try testing.expectEqual(@as(u8, 0xcd), result[1]);
}

test "parseRawBytesJsonValue with hex string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try parseRawBytesJsonValue(allocator, .{ .string = "0x1234" });
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 2), result.len);
}

test "parseRawBytesJsonValue with array" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var arr = std.json.Array.init(allocator);
    defer arr.deinit();
    try arr.append(.{ .string = "0x12" });
    try arr.append(.{ .string = "0x34" });

    const result = try parseRawBytesJsonValue(allocator, .{ .array = arr });
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 2), result.len);
}

test "parseRawBytesJsonValueFromString" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try parseRawBytesJsonValueFromString(allocator, "\"0x1234\"");
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 2), result.len);
}

test "encodeSimplifiedTypeTagFromString" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const tag = try encodeSimplifiedTypeTagFromString(allocator, "u64");
    try testing.expect(tag == .u64);
}

test "parseSimplifiedTypeTag unknown type" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = parseSimplifiedTypeTag(allocator, "unknown");
    try testing.expectError(error.UnknownType, result);
}

test "parseSimplifiedTypeTag invalid vector" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = parseSimplifiedTypeTag(allocator, "vector<");
    try testing.expectError(error.InvalidVectorType, result);
}

test "parseAddress without 0x prefix" {
    const testing = std.testing;

    const addr = try parseAddress("1234");
    try testing.expectEqual(@as(usize, 32), addr.len);
    try testing.expectEqual(@as(u8, 0x12), addr[30]);
}

test "parseSimplifiedTypeTag nested vector" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator;

    var tag = try parseSimplifiedTypeTag(allocator, "vector<vector<u8>>");
    defer tag.deinit(allocator);

    try testing.expect(tag == .vector);
    try testing.expect(tag.vector.* == .vector);
}
