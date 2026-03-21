/// commands/move.zig - Move 合约相关命令处理
const std = @import("std");
const client = @import("sui_client_zig");
const cli = @import("../cli.zig");
const shared = @import("shared.zig");

/// Move 函数模板输出类型
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

/// 解析模板输出类型字符串
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

/// 检查是否有完整的 Move 调用参数
pub fn hasCompleteMoveCallArgs(args: *const cli.ParsedArgs) bool {
    return args.tx_build_package != null and
        args.tx_build_module != null and
        args.tx_build_function != null;
}

/// 获取 Move 包信息
pub fn getMovePackage(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    package_id: []const u8,
    writer: anytype,
    pretty: bool,
) !void {
    const response = try rpc.getNormalizedMovePackage(package_id);
    defer rpc.allocator.free(response);
    
    try shared.printResponse(allocator, writer, response, pretty);
}

/// 获取 Move 模块信息
pub fn getMoveModule(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    package_id: []const u8,
    module_name: []const u8,
    writer: anytype,
    pretty: bool,
) !void {
    const response = try rpc.getNormalizedMoveModule(package_id, module_name);
    defer rpc.allocator.free(response);
    
    try shared.printResponse(allocator, writer, response, pretty);
}

/// 获取 Move 函数信息
pub fn getMoveFunction(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    package_id: []const u8,
    module_name: []const u8,
    function_name: []const u8,
    writer: anytype,
    args: *const cli.ParsedArgs,
) !void {
    const response = try rpc.getNormalizedMoveFunction(package_id, module_name, function_name);
    defer rpc.allocator.free(response);
    
    if (args.move_function_template_output) |output_type| {
        // 解析响应并生成模板输出
        _ = output_type;
        // 实际实现需要解析 JSON 并生成模板
        try writer.writeAll("template-output\n");
    } else if (args.move_function_execute_dry_run) {
        // 执行 dry-run
        try writer.writeAll("dry-run-execution\n");
    } else if (args.move_function_execute_send) {
        // 执行发送
        try writer.writeAll("send-execution\n");
    } else {
        // 默认输出函数信息
        try shared.printResponse(allocator, writer, response, args.pretty);
    }
}

/// 选择可执行的 Move 函数请求工件
pub fn selectExecutableMoveFunctionRequestArtifact(
    allocator: std.mem.Allocator,
    preferred_request_json: ?[]const u8,
    base_request_json: []const u8,
) !struct { used_preferred: bool, request_json: []u8 } {
    // 优先检查 preferred
    if (preferred_request_json) |preferred| {
        const is_executable = try shared.requestArtifactJsonIsExecutable(allocator, preferred);
        if (is_executable) {
            return .{
                .used_preferred = true,
                .request_json = try allocator.dupe(u8, preferred),
            };
        }
    }
    
    // 检查 base
    const is_executable = try shared.requestArtifactJsonIsExecutable(allocator, base_request_json);
    if (!is_executable) {
        return error.UnresolvedMoveFunctionExecutionTemplate;
    }
    
    return .{
        .used_preferred = false,
        .request_json = try allocator.dupe(u8, base_request_json),
    };
}

/// 优先选择可执行的 Move 函数模板变体
pub fn preferExecutableMoveFunctionTemplateVariant(
    allocator: std.mem.Allocator,
    preferred_request_json: ?[]const u8,
    base_request_json: []const u8,
) !bool {
    const selection = selectExecutableMoveFunctionRequestArtifact(
        allocator,
        preferred_request_json,
        base_request_json,
    ) catch |err| switch (err) {
        error.UnresolvedMoveFunctionExecutionTemplate => return preferred_request_json != null,
        else => return err,
    };
    defer allocator.free(selection.request_json);
    return selection.used_preferred;
}

// ============================================================
// 测试
// ============================================================

test "parseMoveFunctionTemplateOutput parses valid values" {
    const testing = std.testing;
    
    try testing.expectEqual(MoveFunctionTemplateOutput.commands, try parseMoveFunctionTemplateOutput("commands"));
    try testing.expectEqual(MoveFunctionTemplateOutput.preferred_commands, try parseMoveFunctionTemplateOutput("preferred-commands"));
    try testing.expectEqual(MoveFunctionTemplateOutput.tx_dry_run_request, try parseMoveFunctionTemplateOutput("dry-run-request"));
    try testing.expectEqual(MoveFunctionTemplateOutput.preferred_tx_send_from_keystore_request, try parseMoveFunctionTemplateOutput("preferred-send-request"));
}

test "parseMoveFunctionTemplateOutput rejects invalid values" {
    const testing = std.testing;
    
    try testing.expectError(error.InvalidCli, parseMoveFunctionTemplateOutput("invalid"));
    try testing.expectError(error.InvalidCli, parseMoveFunctionTemplateOutput(""));
}

test "hasCompleteMoveCallArgs checks required fields" {
    const testing = std.testing;
    
    var args1 = cli.ParsedArgs{
        .command = .tx_build,
        .tx_build_package = "0x1",
        .tx_build_module = "module",
        .tx_build_function = "func",
    };
    try testing.expect(hasCompleteMoveCallArgs(&args1));
    
    var args2 = cli.ParsedArgs{
        .command = .tx_build,
        .tx_build_package = "0x1",
        .tx_build_module = null,
        .tx_build_function = "func",
    };
    try testing.expect(!hasCompleteMoveCallArgs(&args2));
}

test "selectExecutableMoveFunctionRequestArtifact prefers executable" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const base = "{\"executable\":true}";
    const preferred = "{\"executable\":true, \"preferred\":true}";
    
    const result = try selectExecutableMoveFunctionRequestArtifact(allocator, preferred, base);
    defer allocator.free(result.request_json);
    
    try testing.expect(result.used_preferred);
    try testing.expect(std.mem.containsAtLeast(u8, result.request_json, 1, "preferred"));
}

test "selectExecutableMoveFunctionRequestArtifact falls back to base" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const base = "{\"executable\":true}";
    
    const result = try selectExecutableMoveFunctionRequestArtifact(allocator, null, base);
    defer allocator.free(result.request_json);
    
    try testing.expect(!result.used_preferred);
    try testing.expectEqualStrings(base, result.request_json);
}
