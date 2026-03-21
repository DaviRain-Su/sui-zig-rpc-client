/// commands/move.zig - Move contract commands
const std = @import("std");
const types = @import("types.zig");
const shared = @import("shared.zig");

/// Move function template output type
pub const MoveFunctionTemplateOutput = enum {
    commands,
    preferred_commands,
    tx_dry_run_request,
    preferred_tx_dry_run_request,
    tx_dry_run_argv,
    preferred_tx_dry_run_argv,
    tx_dry_run_command,
    preferred_tx_dry_run_command,
    tx_send_from_keystore_request,
    preferred_tx_send_from_keystore_request,
    tx_send_from_keystore_argv,
    preferred_tx_send_from_keystore_argv,
    tx_send_from_keystore_command,
    preferred_tx_send_from_keystore_command,
};

/// Move call argument
pub const MoveCallArg = union(enum) {
    pure: []const u8,
    object: []const u8,
    obj_vec: []const []const u8,
};

/// Move function identifier
pub const MoveFunctionId = struct {
    package: []const u8,
    module: []const u8,
    function: []const u8,

    pub fn deinit(self: *MoveFunctionId, allocator: std.mem.Allocator) void {
        allocator.free(self.package);
        allocator.free(self.module);
        allocator.free(self.function);
    }
};

/// Parse template output type string
pub fn parseMoveFunctionTemplateOutput(value: []const u8) !MoveFunctionTemplateOutput {
    if (std.mem.eql(u8, value, "commands")) return .commands;
    if (std.mem.eql(u8, value, "preferred-commands")) return .preferred_commands;
    if (std.mem.eql(u8, value, "dry-run-request")) return .tx_dry_run_request;
    if (std.mem.eql(u8, value, "preferred-dry-run-request")) return .preferred_tx_dry_run_request;
    if (std.mem.eql(u8, value, "dry-run-argv")) return .tx_dry_run_argv;
    if (std.mem.eql(u8, value, "preferred-dry-run-argv")) return .preferred_tx_dry_run_argv;
    if (std.mem.eql(u8, value, "dry-run-command")) return .tx_dry_run_command;
    if (std.mem.eql(u8, value, "preferred-dry-run-command")) return .preferred_tx_dry_run_command;
    if (std.mem.eql(u8, value, "send-request")) return .tx_send_from_keystore_request;
    if (std.mem.eql(u8, value, "preferred-send-request")) return .preferred_tx_send_from_keystore_request;
    if (std.mem.eql(u8, value, "send-argv")) return .tx_send_from_keystore_argv;
    if (std.mem.eql(u8, value, "preferred-send-argv")) return .preferred_tx_send_from_keystore_argv;
    if (std.mem.eql(u8, value, "send-command")) return .tx_send_from_keystore_command;
    if (std.mem.eql(u8, value, "preferred-send-command")) return .preferred_tx_send_from_keystore_command;
    return error.InvalidCli;
}

/// Check if has complete move call args
pub fn hasCompleteMoveCallArgs(args: anytype) bool {
    return args.tx_build_package != null and
        args.tx_build_module != null and
        args.tx_build_function != null;
}

/// Build move function id
pub fn buildMoveFunctionId(
    allocator: std.mem.Allocator,
    package: []const u8,
    module: []const u8,
    function: []const u8,
) !MoveFunctionId {
    return MoveFunctionId{
        .package = try allocator.dupe(u8, package),
        .module = try allocator.dupe(u8, module),
        .function = try allocator.dupe(u8, function),
    };
}

/// Format move function id
pub fn formatMoveFunctionId(
    writer: anytype,
    id: *const MoveFunctionId,
) !void {
    try writer.print("{s}::{s}::{s}", .{ id.package, id.module, id.function });
}

// ============================================================
// Tests
// ============================================================

test "parseMoveFunctionTemplateOutput parses valid values" {
    const testing = std.testing;

    try testing.expectEqual(MoveFunctionTemplateOutput.commands, try parseMoveFunctionTemplateOutput("commands"));
    try testing.expectEqual(MoveFunctionTemplateOutput.tx_dry_run_request, try parseMoveFunctionTemplateOutput("dry-run-request"));
    try testing.expectEqual(MoveFunctionTemplateOutput.tx_send_from_keystore_request, try parseMoveFunctionTemplateOutput("send-request"));
}

test "hasCompleteMoveCallArgs checks required fields" {
    const testing = std.testing;

    const MockArgs = struct {
        tx_build_package: ?[]const u8 = "0x1",
        tx_build_module: ?[]const u8 = "module",
        tx_build_function: ?[]const u8 = "func",
    };

    var args1 = MockArgs{};
    try testing.expect(hasCompleteMoveCallArgs(&args1));

    var args2 = MockArgs{ .tx_build_module = null };
    try testing.expect(!hasCompleteMoveCallArgs(&args2));
}

test "MoveFunctionId lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var id = try buildMoveFunctionId(allocator, "0x1", "module", "func");
    defer id.deinit(allocator);

    try testing.expectEqualStrings("0x1", id.package);
    try testing.expectEqualStrings("module", id.module);
    try testing.expectEqualStrings("func", id.function);

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try formatMoveFunctionId(output.writer(), &id);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "0x1::module::func"));
}
