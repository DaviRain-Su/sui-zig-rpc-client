const std = @import("std");

pub const Kind = enum {
    clock,
    cetus_clmm_global_config_mainnet,
    cetus_clmm_global_config_testnet,
};

pub const clock = "0x6";
pub const cetus_clmm_global_config_mainnet = "0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f";
pub const cetus_clmm_global_config_testnet = "0xc6273f844b4bc258952c4e477697aa12c918c8e08106fac6b934811298c9820a";
pub const cetus_clmm_global_config_mainnet_type = "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::config::GlobalConfig";

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
        .clock => clock,
        .cetus_clmm_global_config_mainnet => cetus_clmm_global_config_mainnet,
        .cetus_clmm_global_config_testnet => cetus_clmm_global_config_testnet,
    };
}

pub fn canonicalName(kind: Kind) []const u8 {
    return switch (kind) {
        .clock => "clock",
        .cetus_clmm_global_config_mainnet => "cetus_clmm_global_config_mainnet",
        .cetus_clmm_global_config_testnet => "cetus_clmm_global_config_testnet",
    };
}

pub fn resolveKind(raw: []const u8) ?Kind {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (std.mem.startsWith(u8, trimmed, "0x")) return null;

    const name = trimPresetPrefix(trimmed);

    if (std.ascii.eqlIgnoreCase(name, "clock") or
        std.ascii.eqlIgnoreCase(name, "sui_clock") or
        std.ascii.eqlIgnoreCase(name, "system_clock"))
    {
        return .clock;
    }
    if (std.ascii.eqlIgnoreCase(name, "cetus_clmm_global_config_mainnet") or
        std.ascii.eqlIgnoreCase(name, "cetus-global-config-mainnet") or
        std.ascii.eqlIgnoreCase(name, "cetus_global_config_mainnet") or
        std.ascii.eqlIgnoreCase(name, "cetus.mainnet.clmm.global_config"))
    {
        return .cetus_clmm_global_config_mainnet;
    }
    if (std.ascii.eqlIgnoreCase(name, "cetus_clmm_global_config_testnet") or
        std.ascii.eqlIgnoreCase(name, "cetus-global-config-testnet") or
        std.ascii.eqlIgnoreCase(name, "cetus_global_config_testnet") or
        std.ascii.eqlIgnoreCase(name, "cetus.testnet.clmm.global_config"))
    {
        return .cetus_clmm_global_config_testnet;
    }
    return null;
}

pub fn resolveObjectIdAlias(raw: []const u8) ?[]const u8 {
    const kind = resolveKind(raw) orelse return null;
    return objectId(kind);
}

pub fn inferKindFromTypeSignature(signature: []const u8) ?Kind {
    const trimmed = trimReferencePrefix(signature);
    if (std.mem.eql(u8, trimmed, "0x2::clock::Clock")) return .clock;
    if (std.mem.eql(u8, trimmed, cetus_clmm_global_config_mainnet_type)) {
        return .cetus_clmm_global_config_mainnet;
    }
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
