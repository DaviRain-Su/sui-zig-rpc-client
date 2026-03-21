/// commands/account.zig - 账户相关命令处理
const std = @import("std");
const cli = @import("../cli.zig");
const client = @import("../root.zig");
const shared = @import("shared.zig");

/// 账户列表输出格式
pub const AccountListFormat = enum {
    raw,
    summarize,
    json,
};

/// 获取账户列表
pub fn listAccounts(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
) !void {
    _ = rpc;
    
    const format: AccountListFormat = if (args.account_list_json) .json else .summarize;
    
    switch (format) {
        .raw => {
            // 原始输出 - 实际实现需要从 keystore 读取
            try writer.writeAll("[]\n");
        },
        .summarize => {
            // 汇总输出
            try writer.writeAll("Accounts:\n");
            // 实际实现需要查询 keystore
        },
        .json => {
            try writer.writeAll("[]\n");
        },
    }
}

/// 获取账户信息
pub fn getAccountInfo(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
) !void {
    const selector = args.account_selector orelse return error.InvalidCli;
    
    // 解析选择器获取地址
    const address = if (std.mem.startsWith(u8, selector, "0x"))
        selector
    else
        // 从 keystore 解析
        return error.InvalidCli;
    
    _ = allocator;
    _ = rpc;
    
    if (args.account_info_json) {
        try writer.print("{{\"address\":\"{s}\"}}\n", .{address});
    } else {
        try writer.print("Address: {s}\n", .{address});
    }
}

/// 获取账户代币
pub fn getAccountCoins(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
) !void {
    const selector = args.account_selector orelse return error.InvalidCli;
    
    // 构建请求参数
    var params_arr = std.ArrayList(u8).init(allocator);
    defer params_arr.deinit();
    
    const writer_params = params_arr.writer();
    try writer_params.writeAll("[");
    
    // 地址
    try std.json.stringify(selector, .{}, writer_params);
    
    // 可选的 coin 类型过滤
    if (args.account_coin_type) |coin_type| {
        try writer_params.writeAll(",\"");
        try writer_params.writeAll(coin_type);
        try writer_params.writeAll("\"");
    }
    
    try writer_params.writeAll("]");
    
    const response = try rpc.sendRequestFrom("suix_getCoins", params_arr.items);
    defer rpc.allocator.free(response);
    
    if (args.account_coins_json) {
        try writer.print("{s}\n", .{response});
    } else {
        // 简化的汇总输出
        try shared.printResponse(allocator, writer, response, args.pretty);
    }
}

/// 获取账户对象
pub fn getAccountObjects(
    allocator: std.mem.Allocator,
    rpc: *client.SuiRpcClient,
    args: *const cli.ParsedArgs,
    writer: anytype,
) !void {
    const selector = args.account_selector orelse return error.InvalidCli;
    
    // 构建过滤器
    var filter_opt: ?[]const u8 = null;
    if (args.account_objects_struct_type) |struct_type| {
        filter_opt = struct_type;
    } else if (args.account_objects_package) |pkg| {
        _ = pkg;
        // 构建包过滤器
    }
    
    _ = filter_opt;
    
    var params_arr = std.ArrayList(u8).init(allocator);
    defer params_arr.deinit();
    
    const writer_params = params_arr.writer();
    try writer_params.writeAll("[");
    try std.json.stringify(selector, .{}, writer_params);
    try writer_params.writeAll("]");
    
    const response = try rpc.sendRequestFrom("suix_getOwnedObjects", params_arr.items);
    defer rpc.allocator.free(response);
    
    if (args.account_objects_json) {
        try writer.print("{s}\n", .{response});
    } else {
        try shared.printResponse(allocator, writer, response, args.pretty);
    }
}

// ============================================================
// 测试
// ============================================================

test "listAccounts outputs valid format" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .account_list,
        .has_command = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try listAccounts(allocator, &rpc, &args, output.writer(allocator));
    
    // 验证输出了内容
    try testing.expect(output.items.len > 0);
}

test "getAccountInfo requires selector" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = cli.ParsedArgs{
        .command = .account_info,
        .has_command = true,
    };

    var rpc = try client.SuiRpcClient.init(allocator, "http://example.local");
    defer rpc.deinit();

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    const result = getAccountInfo(allocator, &rpc, &args, output.writer(allocator));
    try testing.expectError(error.InvalidCli, result);
}
