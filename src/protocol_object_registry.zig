const std = @import("std");

pub const Kind = enum {
    cetus_clmm_global_config_mainnet,
    cetus_clmm_global_config_testnet,
};

pub const cetus_clmm_global_config_mainnet = "0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f";
pub const cetus_clmm_global_config_testnet = "0xc6273f844b4bc258952c4e477697aa12c918c8e08106fac6b934811298c9820a";

pub const cetus_clmm_global_config_mainnet_type =
    "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::config::GlobalConfig";

pub fn objectId(kind: Kind) []const u8 {
    return switch (kind) {
        .cetus_clmm_global_config_mainnet => cetus_clmm_global_config_mainnet,
        .cetus_clmm_global_config_testnet => cetus_clmm_global_config_testnet,
    };
}

pub fn canonicalName(kind: Kind) []const u8 {
    return switch (kind) {
        .cetus_clmm_global_config_mainnet => "cetus_clmm_global_config_mainnet",
        .cetus_clmm_global_config_testnet => "cetus_clmm_global_config_testnet",
    };
}

pub fn resolveKindName(name: []const u8) ?Kind {
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

pub fn inferKindFromTypeSignature(signature: []const u8) ?Kind {
    if (std.mem.eql(u8, signature, cetus_clmm_global_config_mainnet_type)) {
        return .cetus_clmm_global_config_mainnet;
    }
    return null;
}

test "resolveKindName resolves protocol object aliases" {
    const testing = std.testing;

    try testing.expectEqual(
        Kind.cetus_clmm_global_config_mainnet,
        resolveKindName("cetus.mainnet.clmm.global_config").?,
    );
    try testing.expectEqual(
        Kind.cetus_clmm_global_config_testnet,
        resolveKindName("CETUS-GLOBAL-CONFIG-TESTNET").?,
    );
    try testing.expect(resolveKindName("unknown") == null);
}

test "inferKindFromTypeSignature resolves protocol object types" {
    const testing = std.testing;

    try testing.expectEqual(
        Kind.cetus_clmm_global_config_mainnet,
        inferKindFromTypeSignature(cetus_clmm_global_config_mainnet_type).?,
    );
    try testing.expect(inferKindFromTypeSignature("0x2::clock::Clock") == null);
}
