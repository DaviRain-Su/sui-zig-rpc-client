/// ptb_bytes_builder/bcs_encoder.zig - BCS encoding utilities
const std = @import("std");
const types = @import("types.zig");

const Address = types.Address;
const TypeTag = types.TypeTag;
const StructTag = types.StructTag;

/// Parse BCS value specification
pub fn parseBcsValueSpec(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // Try to parse as JSON first
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch {
        // If not JSON, treat as raw hex
        return try parseHexString(allocator, raw);
    };
    defer parsed.deinit();

    // Encode based on type
    return try encodeJsonValue(allocator, parsed.value);
}

/// Encode BCS value from type name and value string
pub fn encodeBcsValue(allocator: std.mem.Allocator, type_name: []const u8, value_str: []const u8) ![]u8 {
    if (std.mem.eql(u8, type_name, "u8")) {
        const value = try std.fmt.parseInt(u8, value_str, 10);
        const result = try allocator.alloc(u8, 1);
        result[0] = value;
        return result;
    } else if (std.mem.eql(u8, type_name, "u16")) {
        const value = try std.fmt.parseInt(u16, value_str, 10);
        const result = try allocator.alloc(u8, 2);
        std.mem.writeInt(u16, result[0..2], value, .little);
        return result;
    } else if (std.mem.eql(u8, type_name, "u32")) {
        const value = try std.fmt.parseInt(u32, value_str, 10);
        const result = try allocator.alloc(u8, 4);
        std.mem.writeInt(u32, result[0..4], value, .little);
        return result;
    } else if (std.mem.eql(u8, type_name, "u64")) {
        const value = try std.fmt.parseInt(u64, value_str, 10);
        const result = try allocator.alloc(u8, 8);
        std.mem.writeInt(u64, result[0..8], value, .little);
        return result;
    } else if (std.mem.eql(u8, type_name, "u128")) {
        const value = try std.fmt.parseInt(u128, value_str, 10);
        const result = try allocator.alloc(u8, 16);
        std.mem.writeInt(u128, result[0..16], value, .little);
        return result;
    } else if (std.mem.eql(u8, type_name, "u256")) {
        const value = try std.fmt.parseInt(u256, value_str, 10);
        const result = try allocator.alloc(u8, 32);
        std.mem.writeInt(u256, result[0..32], value, .little);
        return result;
    } else if (std.mem.eql(u8, type_name, "bool")) {
        const result = try allocator.alloc(u8, 1);
        result[0] = if (std.mem.eql(u8, value_str, "true")) 1 else 0;
        return result;
    } else if (std.mem.eql(u8, type_name, "address")) {
        return try parseHexAddress32Bytes(allocator, value_str);
    } else {
        return error.UnsupportedType;
    }
}

/// Encode BCS pure value (auto-detect type)
pub fn encodeBcsPureValue(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // Try to parse as JSON
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch {
        // If not JSON, return as-is
        return try allocator.dupe(u8, raw);
    };
    defer parsed.deinit();

    return try encodeJsonValue(allocator, parsed.value);
}

/// Encode JSON value to BCS
fn encodeJsonValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return switch (value) {
        .integer => |i| {
            const result = try allocator.alloc(u8, 8);
            std.mem.writeInt(u64, result[0..8], @intCast(i), .little);
            return result;
        },
        .string => |s| {
            // Try to parse as number
            if (std.fmt.parseInt(u64, s, 10)) |num| {
                const result = try allocator.alloc(u8, 8);
                std.mem.writeInt(u64, result[0..8], num, .little);
                return result;
            } else |_| {
                // Try to parse as address
                if (s.len == 66 and std.mem.startsWith(u8, s, "0x")) {
                    return try parseHexAddress32Bytes(allocator, s);
                }
                // Return as string bytes
                return try allocator.dupe(u8, s);
            }
        },
        .bool => |b| {
            const result = try allocator.alloc(u8, 1);
            result[0] = if (b) 1 else 0;
            return result;
        },
        .array => |arr| {
            var result = std.ArrayList(u8).init(allocator);
            defer result.deinit();

            // Write length
            const len_bytes = try allocator.alloc(u8, 4);
            defer allocator.free(len_bytes);
            std.mem.writeInt(u32, len_bytes[0..4], @intCast(arr.items.len), .little);
            try result.appendSlice(len_bytes);

            // Write elements
            for (arr.items) |item| {
                const encoded = try encodeJsonValue(allocator, item);
                defer allocator.free(encoded);
                try result.appendSlice(encoded);
            }

            return result.toOwnedSlice();
        },
        else => error.UnsupportedJsonType,
    };
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

/// Parse hex digit
fn parseHexDigit(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHexDigit,
    };
}

/// Parse hex address to 32 bytes
fn parseHexAddress32Bytes(allocator: std.mem.Allocator, value: []const u8) ![32]u8 {
    const start = if (std.mem.startsWith(u8, value, "0x")) 2 else 0;
    const hex_part = value[start..];

    var result: [32]u8 = [_]u8{0} ** 32;

    // Pad with zeros on the left
    const hex_len = hex_part.len;
    if (hex_len > 64) return error.AddressTooLong;

    const start_offset = 32 - (hex_len / 2);

    for (0..hex_len / 2) |i| {
        const hi = try parseHexDigit(hex_part[i * 2]);
        const lo = try parseHexDigit(hex_part[i * 2 + 1]);
        result[start_offset + i] = (hi << 4) | lo;
    }

    return result;
}

/// Parse hex address (public)
pub fn parseHexAddress32(value: []const u8) !Address {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    return try parseHexAddress32Bytes(allocator, value);
}

/// Encode type tag to BCS
pub fn encodeTypeTag(allocator: std.mem.Allocator, tag: TypeTag) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    switch (tag) {
        .bool => try result.append(0),
        .u8 => try result.append(1),
        .u16 => try result.append(2),
        .u32 => try result.append(3),
        .u64 => try result.append(4),
        .u128 => try result.append(5),
        .u256 => try result.append(6),
        .address => try result.append(7),
        .signer => try result.append(8),
        .vector => |v| {
            try result.append(9);
            const inner = try encodeTypeTag(allocator, v.*);
            defer allocator.free(inner);
            try result.appendSlice(inner);
        },
        .struct => |s| {
            try result.append(10);
            try result.appendSlice(&s.address);
            const module_len = try std.fmt.allocPrint(allocator, "{d}", .{s.module.len});
            defer allocator.free(module_len);
            try result.appendSlice(module_len);
            try result.appendSlice(s.module);
            const name_len = try std.fmt.allocPrint(allocator, "{d}", .{s.name.len});
            defer allocator.free(name_len);
            try result.appendSlice(name_len);
            try result.appendSlice(s.name);
            // Type params
            const params_len = try std.fmt.allocPrint(allocator, "{d}", .{s.type_params.len});
            defer allocator.free(params_len);
            try result.appendSlice(params_len);
            for (s.type_params) |tp| {
                const encoded = try encodeTypeTag(allocator, tp);
                defer allocator.free(encoded);
                try result.appendSlice(encoded);
            }
        },
        .type_param => |p| {
            try result.append(11);
            const buf = try allocator.alloc(u8, 2);
            defer allocator.free(buf);
            std.mem.writeInt(u16, buf[0..2], p, .little);
            try result.appendSlice(buf);
        },
    }

    return result.toOwnedSlice();
}

// ============================================================
// Tests
// ============================================================

test "parseHexDigit" {
    const testing = std.testing;
    try testing.expectEqual(@as(u8, 0), try parseHexDigit('0'));
    try testing.expectEqual(@as(u8, 9), try parseHexDigit('9'));
    try testing.expectEqual(@as(u8, 10), try parseHexDigit('a'));
    try testing.expectEqual(@as(u8, 15), try parseHexDigit('F'));
}

test "parseHexString" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try parseHexString(allocator, "0x1234");
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 2), result.len);
    try testing.expectEqual(@as(u8, 0x12), result[0]);
    try testing.expectEqual(@as(u8, 0x34), result[1]);
}

test "parseHexAddress32Bytes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try parseHexAddress32Bytes(allocator, "0x1234");
    try testing.expectEqual(@as(usize, 32), result.len);
    try testing.expectEqual(@as(u8, 0x12), result[30]);
    try testing.expectEqual(@as(u8, 0x34), result[31]);
}

test "parseHexAddress32Bytes left pads short addresses" {
    const testing = std.testing;

    const result = try parseHexAddress32("0x1");
    try testing.expectEqual(@as(usize, 32), result.len);
    try testing.expectEqual(@as(u8, 0), result[30]);
    try testing.expectEqual(@as(u8, 1), result[31]);
}

test "encodeBcsValue u64" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeBcsValue(allocator, "u64", "12345");
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 8), result.len);
    const value = std.mem.readInt(u64, result[0..8], .little);
    try testing.expectEqual(@as(u64, 12345), value);
}

test "encodeBcsValue bool" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const true_result = try encodeBcsValue(allocator, "bool", "true");
    defer allocator.free(true_result);
    try testing.expectEqual(@as(u8, 1), true_result[0]);

    const false_result = try encodeBcsValue(allocator, "bool", "false");
    defer allocator.free(false_result);
    try testing.expectEqual(@as(u8, 0), false_result[0]);
}

test "encodeBcsValue address" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeBcsValue(allocator, "address", "0x1234");
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 32), result.len);
}

test "encodeBcsPureValue with integer" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeBcsPureValue(allocator, "12345");
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 8), result.len);
}

test "encodeBcsPureValue with string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeBcsPureValue(allocator, "\"hello\"");
    defer allocator.free(result);

    // Should be the string content
    try testing.expect(result.len > 0);
}

test "encodeJsonValue integer" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeJsonValue(allocator, .{ .integer = 42 });
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 8), result.len);
    const value = std.mem.readInt(u64, result[0..8], .little);
    try testing.expectEqual(@as(u64, 42), value);
}

test "encodeJsonValue bool" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeJsonValue(allocator, .{ .bool = true });
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u8, 1), result[0]);
}

test "encodeTypeTag bool" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeTypeTag(allocator, .bool);
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u8, 0), result[0]);
}

test "encodeTypeTag u64" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try encodeTypeTag(allocator, .u64);
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u8, 4), result[0]);
}
