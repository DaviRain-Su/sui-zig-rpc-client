const std = @import("std");
const built_in_object_preset = @import("./builtin_object_preset.zig");
const protocol_object_registry = @import("./protocol_object_registry.zig");

pub const Kind = enum {
    clock,
    cetus_clmm_global_config_mainnet,
    cetus_clmm_global_config_testnet,
};

pub const clock = built_in_object_preset.clock;
pub const cetus_clmm_global_config_mainnet = protocol_object_registry.cetus_clmm_global_config_mainnet;
pub const cetus_clmm_global_config_testnet = protocol_object_registry.cetus_clmm_global_config_testnet;
pub const cetus_clmm_global_config_mainnet_type = protocol_object_registry.cetus_clmm_global_config_mainnet_type;

fn trimPresetPrefix(raw: []const u8) []const u8 {
    if (std.mem.startsWith(u8, raw, "preset:")) return raw["preset:".len..];
    if (std.mem.startsWith(u8, raw, "obj:")) return raw["obj:".len..];
    if (std.mem.startsWith(u8, raw, "object:")) return raw["object:".len..];
    return raw;
}

fn trimReferencePrefix(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.startsWith(u8, trimmed, "&mut ")) return trimmed["&mut ".len..];
    if (std.mem.startsWith(u8, trimmed, "&")) return trimmed[1..];
    return trimmed;
}

pub fn objectId(kind: Kind) []const u8 {
    return switch (kind) {
        .clock => built_in_object_preset.objectId(.clock),
        .cetus_clmm_global_config_mainnet => protocol_object_registry.objectId(.cetus_clmm_global_config_mainnet),
        .cetus_clmm_global_config_testnet => protocol_object_registry.objectId(.cetus_clmm_global_config_testnet),
    };
}

pub fn canonicalName(kind: Kind) []const u8 {
    return switch (kind) {
        .clock => built_in_object_preset.canonicalName(.clock),
        .cetus_clmm_global_config_mainnet => protocol_object_registry.canonicalName(.cetus_clmm_global_config_mainnet),
        .cetus_clmm_global_config_testnet => protocol_object_registry.canonicalName(.cetus_clmm_global_config_testnet),
    };
}

pub fn resolveKind(raw: []const u8) ?Kind {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (std.mem.startsWith(u8, trimmed, "0x")) return null;

    const name = trimPresetPrefix(trimmed);

    if (built_in_object_preset.resolveKindName(name)) |kind| return switch (kind) {
        .clock => .clock,
    };
    if (protocol_object_registry.resolveKindName(name)) |kind| return switch (kind) {
        .cetus_clmm_global_config_mainnet => .cetus_clmm_global_config_mainnet,
        .cetus_clmm_global_config_testnet => .cetus_clmm_global_config_testnet,
    };
    return null;
}

pub fn resolveObjectIdAlias(raw: []const u8) ?[]const u8 {
    const kind = resolveKind(raw) orelse return null;
    return objectId(kind);
}

pub fn inferKindFromTypeSignature(signature: []const u8) ?Kind {
    const trimmed = trimReferencePrefix(signature);
    if (built_in_object_preset.inferKindFromTypeSignature(trimmed)) |kind| return switch (kind) {
        .clock => .clock,
    };
    if (protocol_object_registry.inferKindFromTypeSignature(trimmed)) |kind| return switch (kind) {
        .cetus_clmm_global_config_mainnet => .cetus_clmm_global_config_mainnet,
        .cetus_clmm_global_config_testnet => .cetus_clmm_global_config_testnet,
    };
    return null;
}

test "resolveKind resolves built-in object preset aliases" {
    const testing = std.testing;

    try testing.expectEqual(Kind.clock, resolveKind("clock").?);
    try testing.expectEqual(Kind.clock, resolveKind("preset:sui_clock").?);
    try testing.expectEqual(Kind.clock, resolveKind("object:system_clock").?);
    try testing.expectEqual(
        Kind.cetus_clmm_global_config_mainnet,
        resolveKind("obj:cetus.mainnet.clmm.global_config").?,
    );
    try testing.expectEqual(
        Kind.cetus_clmm_global_config_testnet,
        resolveKind("CETUS-GLOBAL-CONFIG-TESTNET").?,
    );
    try testing.expect(resolveKind("0x6") == null);
    try testing.expect(resolveKind("unknown_alias") == null);
}

test "resolveObjectIdAlias resolves built-in object preset aliases" {
    const testing = std.testing;

    try testing.expectEqualStrings(clock, resolveObjectIdAlias("clock").?);
    try testing.expectEqualStrings(clock, resolveObjectIdAlias("preset:sui_clock").?);
    try testing.expectEqualStrings(
        cetus_clmm_global_config_mainnet,
        resolveObjectIdAlias("cetus_clmm_global_config_mainnet").?,
    );
    try testing.expectEqualStrings(
        cetus_clmm_global_config_testnet,
        resolveObjectIdAlias("object:cetus.testnet.clmm.global_config").?,
    );
    try testing.expect(resolveObjectIdAlias("0x6") == null);
    try testing.expect(resolveObjectIdAlias("unknown_alias") == null);
}

test "inferKindFromTypeSignature resolves known preset object types" {
    const testing = std.testing;

    try testing.expectEqual(Kind.clock, inferKindFromTypeSignature("&0x2::clock::Clock").?);
    try testing.expectEqual(
        Kind.cetus_clmm_global_config_mainnet,
        inferKindFromTypeSignature("&mut " ++ cetus_clmm_global_config_mainnet_type).?,
    );
    try testing.expect(inferKindFromTypeSignature("&0x2::coin::Coin<0x2::sui::SUI>") == null);
}
