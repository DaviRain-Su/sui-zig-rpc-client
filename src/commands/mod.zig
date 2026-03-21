/// commands/mod.zig - 命令模块入口
///
/// 这是命令处理模块的主入口文件，重新导出所有子模块的公共接口。
/// 重构目标是将原本庞大的 commands.zig 拆分为多个专注的子模块。
///
/// 模块结构：
/// - shared: 共享工具函数和辅助类型
/// - tx: 交易相关命令 (tx_send, tx_build, tx_simulate, etc.)
/// - move: Move 合约命令 (move_package, move_module, move_function)
/// - account: 账户命令 (account_list, account_info, account_coins, etc.)
///
const std = @import("std");
const cli = @import("../cli.zig");
const client = @import("../root.zig");

// 子模块重新导出
pub const shared = @import("shared.zig");
pub const tx = @import("tx.zig");
pub const move = @import("move.zig");
pub const account = @import("account.zig");

/// 主命令分发函数
/// 
/// 注意：当前实现保持与旧版 commands.zig 的兼容。
/// 完整的重构将逐步迁移 runCommand 的实现到各个子模块。
pub fn runCommand(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
) !void {
    // 目前转发到旧版实现
    // 重构完成后，这里将直接使用子模块的实现
    const legacy = @import("../commands.zig");
    try legacy.runCommand(allocator, rpc, args, writer);
}

/// 带程序化提供者的命令执行
pub fn runCommandWithProgrammaticProvider(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
    provider: ?client.tx_request_builder.ProgrammaticProvider,
) !void {
    const legacy = @import("../commands.zig");
    try legacy.runCommandWithProgrammaticProvider(allocator, rpc, args, writer, provider);
}

// ============================================================
// 兼容性类型重新导出
// ============================================================

/// Move 函数模板输出类型（兼容性导出）
pub const MoveFunctionTemplateOutput = move.MoveFunctionTemplateOutput;

/// 命令结果类型（兼容性导出）
pub const CommandResult = shared.CommandResult;

/// 交易构建错误（兼容性导出）
pub const TxBuildError = shared.TxBuildError;

// ============================================================
// 测试
// ============================================================

test "module imports successfully" {
    _ = shared;
    _ = tx;
    _ = move;
    _ = account;
}

test "shared functions are accessible" {
    const testing = std.testing;
    
    // 验证共享函数可用
    const result = shared.stringContainsUnresolvedMoveFunctionPlaceholder("<arg0>");
    try testing.expect(result);
}

test "move module functions are accessible" {
    const testing = std.testing;
    
    const output = move.parseMoveFunctionTemplateOutput("commands") catch unreachable;
    try testing.expectEqual(move.MoveFunctionTemplateOutput.commands, output);
}
