const std = @import("std");

pub const Kind = enum {
    clock,
};

pub const clock = "0x6";

pub fn objectId(kind: Kind) []const u8 {
    return switch (kind) {
        .clock => clock,
    };
}

pub fn canonicalName(kind: Kind) []const u8 {
    return switch (kind) {
        .clock => "clock",
    };
}

pub fn resolveKindName(name: []const u8) ?Kind {
    if (std.ascii.eqlIgnoreCase(name, "clock") or
        std.ascii.eqlIgnoreCase(name, "sui_clock") or
        std.ascii.eqlIgnoreCase(name, "system_clock"))
    {
        return .clock;
    }
    return null;
}

pub fn inferKindFromTypeSignature(signature: []const u8) ?Kind {
    if (std.mem.eql(u8, signature, "0x2::clock::Clock")) return .clock;
    return null;
}

test "resolveKindName resolves built-in object presets" {
    const testing = std.testing;

    try testing.expectEqual(Kind.clock, resolveKindName("clock").?);
    try testing.expectEqual(Kind.clock, resolveKindName("sui_clock").?);
    try testing.expectEqual(Kind.clock, resolveKindName("system_clock").?);
    try testing.expect(resolveKindName("unknown") == null);
}

test "inferKindFromTypeSignature resolves built-in object preset types" {
    const testing = std.testing;

    try testing.expectEqual(Kind.clock, inferKindFromTypeSignature("0x2::clock::Clock").?);
    try testing.expect(inferKindFromTypeSignature("0x2::coin::Coin<0x2::sui::SUI>") == null);
}
