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
        printUsage(args[0]);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "balance")) {
        try cmdBalance(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "objects")) {
        try cmdObjects(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help")) {
        printUsage(args[0]);
    } else {
        std.log.err("Unknown command: {s}", .{command});
        printUsage(args[0]);
        std.process.exit(1);
    }
}

fn printUsage(prog_name: []const u8) void {
    std.log.info("Usage: {s} <command> [options]", .{prog_name});
    std.log.info("Commands:", .{});
    std.log.info("  balance <address>           Get SUI balance for address", .{});
    std.log.info("  objects <address>           List owned objects for address", .{});
    std.log.info("  help                        Show this help", .{});
}

fn getRpcUrl() ?[]const u8 {
    return std.process.getEnvVarOwned(std.heap.page_allocator, "SUI_RPC_URL") catch null;
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
    std.log.info("Balance: {d} MIST ({d}.{d} SUI)", .{
        balance,
        balance / 1_000_000_000,
        balance % 1_000_000_000,
    });
}

fn cmdObjects(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: objects <address>", .{});
        std.process.exit(1);
    }

    const address = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    // Query objects with pagination
    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",{{\"options\":{{\"showType\":true}}}},null,50]",
        .{address},
    );
    defer allocator.free(params);

    const response = try rpc_client.call("suix_getOwnedObjects", params);
    defer allocator.free(response);

    // Parse response manually to avoid complex Object struct
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Address: {s}", .{address});

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                std.log.info("Objects: {d}", .{data.array.items.len});

                for (data.array.items, 0..) |item, i| {
                    if (item.object.get("data")) |obj_data| {
                        const object_id = obj_data.object.get("objectId") orelse continue;
                        std.log.info("  {d}. {s}", .{ i + 1, object_id.string });

                        if (obj_data.object.get("type")) |t| {
                            if (t == .string) {
                                std.log.info("      Type: {s}", .{t.string});
                            }
                        }

                        if (obj_data.object.get("version")) |v| {
                            const version_num: u64 = if (v == .integer)
                                @intCast(v.integer)
                            else
                                std.fmt.parseInt(u64, v.string, 10) catch 0;
                            std.log.info("      Version: {d}", .{version_num});
                        }
                    }
                }

                if (result.object.get("hasNextPage")) |has_next| {
                    if (has_next == .bool and has_next.bool) {
                        if (result.object.get("nextCursor")) |cursor| {
                            if (cursor == .string) {
                                std.log.info("  (More objects available, next cursor: {s})", .{cursor.string});
                            }
                        }
                    }
                }
            }
        }
    }
}
