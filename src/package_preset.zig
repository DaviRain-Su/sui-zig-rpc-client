const std = @import("std");

pub const cetus_clmm_mainnet = "0x25ebb9a7c50eb17b3fa9c5a30fb8b5ad8f97caaf4928943acbcff7153dfee5e3";
pub const cetus_clmm_testnet = "0x6bbdf09f9fa0baa1524080a5b8991042e95061c4e1206217279aec51ba08edf7";

fn trimPresetPrefix(raw: []const u8) []const u8 {
    if (std.mem.startsWith(u8, raw, "preset:")) return raw["preset:".len..];
    if (std.mem.startsWith(u8, raw, "pkg:")) return raw["pkg:".len..];
    return raw;
}

pub fn resolvePackageIdAlias(raw: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (std.mem.startsWith(u8, trimmed, "0x")) return null;

    const name = trimPresetPrefix(trimmed);

    if (std.ascii.eqlIgnoreCase(name, "sui") or
        std.ascii.eqlIgnoreCase(name, "sui_framework") or
        std.ascii.eqlIgnoreCase(name, "sui-framework") or
        std.ascii.eqlIgnoreCase(name, "framework"))
    {
        return "0x2";
    }
    if (std.ascii.eqlIgnoreCase(name, "sui_system") or
        std.ascii.eqlIgnoreCase(name, "sui-system") or
        std.ascii.eqlIgnoreCase(name, "system"))
    {
        return "0x3";
    }
    if (std.ascii.eqlIgnoreCase(name, "cetus_clmm_mainnet") or
        std.ascii.eqlIgnoreCase(name, "cetus-clmm-mainnet") or
        std.ascii.eqlIgnoreCase(name, "cetus.mainnet.clmm"))
    {
        return cetus_clmm_mainnet;
    }
    if (std.ascii.eqlIgnoreCase(name, "cetus_clmm_testnet") or
        std.ascii.eqlIgnoreCase(name, "cetus-clmm-testnet") or
        std.ascii.eqlIgnoreCase(name, "cetus.testnet.clmm"))
    {
        return cetus_clmm_testnet;
    }
    return null;
}

test "resolvePackageIdAlias resolves built-in package aliases" {
    const testing = std.testing;

    try testing.expectEqualStrings("0x2", resolvePackageIdAlias("sui").?);
    try testing.expectEqualStrings("0x2", resolvePackageIdAlias("preset:sui-framework").?);
    try testing.expectEqualStrings("0x3", resolvePackageIdAlias("system").?);
    try testing.expectEqualStrings(cetus_clmm_mainnet, resolvePackageIdAlias("cetus_clmm_mainnet").?);
    try testing.expectEqualStrings(cetus_clmm_mainnet, resolvePackageIdAlias("pkg:cetus.mainnet.clmm").?);
    try testing.expectEqualStrings(cetus_clmm_testnet, resolvePackageIdAlias("CETUS-CLMM-TESTNET").?);
    try testing.expect(resolvePackageIdAlias("0x2") == null);
    try testing.expect(resolvePackageIdAlias("unknown_alias") == null);
}
