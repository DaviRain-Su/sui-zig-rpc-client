/// main_v2.zig - New main entry point using new RPC client API only
const std = @import("std");
const sui_client = @import("sui_client_zig");

// Use new API only
const SuiRpcClient = sui_client.rpc_client_new.SuiRpcClient;

const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.info("Usage: {s} <command> [options]", .{args[0]});
        std.log.info("Commands: balance", .{});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "balance")) {
        try cmdBalance(allocator, args[2..]);
    } else {
        std.log.err("Unknown command: {s}", .{command});
        std.process.exit(1);
    }
}

fn cmdBalance(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: balance <address>", .{});
        std.process.exit(1);
    }

    const address = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const balance = try sui_client.rpc_client_new.getBalance(
        &rpc_client,
        address,
        null,
    );

    std.log.info("Address: {s}", .{address});
    std.log.info("Balance: {d} MIST", .{balance});
}

fn getRpcUrl() ?[]const u8 {
    return std.process.getEnvVarOwned(std.heap.page_allocator, "SUI_RPC_URL") catch null;
}
