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
    } else if (std.mem.eql(u8, command, "object")) {
        try cmdObject(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "tx")) {
        try cmdTransaction(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "coins")) {
        try cmdCoins(allocator, args[2..]);
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
    std.log.info("  object <object_id>          Get object details", .{});
    std.log.info("  tx <tx_digest>              Get transaction details", .{});
    std.log.info("  coins <address>             List coin objects for address", .{});
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

    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",{{\"options\":{{\"showType\":true}}}},null,50]",
        .{address},
    );
    defer allocator.free(params);

    const response = try rpc_client.call("suix_getOwnedObjects", params);
    defer allocator.free(response);

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

fn cmdObject(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: object <object_id>", .{});
        std.process.exit(1);
    }

    const object_id = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",{{\"showType\":true,\"showOwner\":true,\"showContent\":true}}]",
        .{object_id},
    );
    defer allocator.free(params);

    const response = try rpc_client.call("sui_getObject", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Object ID: {s}", .{object_id});

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |obj_data| {
            if (obj_data.object.get("objectId")) |id| {
                std.log.info("  ID: {s}", .{id.string});
            }
            if (obj_data.object.get("type")) |t| {
                if (t == .string) {
                    std.log.info("  Type: {s}", .{t.string});
                }
            }
            if (obj_data.object.get("version")) |v| {
                const version_num: u64 = if (v == .integer)
                    @intCast(v.integer)
                else
                    std.fmt.parseInt(u64, v.string, 10) catch 0;
                std.log.info("  Version: {d}", .{version_num});
            }
            if (obj_data.object.get("digest")) |d| {
                std.log.info("  Digest: {s}", .{d.string});
            }
            if (result.object.get("owner")) |owner| {
                if (owner.object.get("AddressOwner")) |addr| {
                    std.log.info("  Owner: {s}", .{addr.string});
                } else if (owner.object.get("ObjectOwner")) |addr| {
                    std.log.info("  Owner (Object): {s}", .{addr.string});
                } else if (owner.object.get("Shared") != null) {
                    std.log.info("  Owner: Shared", .{});
                } else if (owner.object.get("Immutable") != null) {
                    std.log.info("  Owner: Immutable", .{});
                }
            }
        } else if (result.object.get("error")) |err| {
            if (err.object.get("code")) |code| {
                std.log.info("  Error: {s}", .{code.string});
            }
        }
    }
}

fn cmdTransaction(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: tx <tx_digest>", .{});
        std.process.exit(1);
    }

    const tx_digest = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",{{\"showInput\":true,\"showEffects\":true,\"showEvents\":true}}]",
        .{tx_digest},
    );
    defer allocator.free(params);

    const response = try rpc_client.call("sui_getTransactionBlock", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Transaction: {s}", .{tx_digest});

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("transaction")) |tx| {
            if (tx.object.get("data")) |data| {
                if (data.object.get("sender")) |sender| {
                    std.log.info("  Sender: {s}", .{sender.string});
                }
                if (data.object.get("gasData")) |gas| {
                    if (gas.object.get("budget")) |budget| {
                        const budget_num: u64 = if (budget == .integer)
                            @intCast(budget.integer)
                        else
                            std.fmt.parseInt(u64, budget.string, 10) catch 0;
                        std.log.info("  Gas Budget: {d} MIST", .{budget_num});
                    }
                }
            }
        }
        if (result.object.get("effects")) |effects| {
            if (effects.object.get("status")) |status| {
                if (status.object.get("status")) |s| {
                    std.log.info("  Status: {s}", .{s.string});
                }
            }
            if (effects.object.get("gasUsed")) |gas| {
                if (gas.object.get("computationCost")) |cost| {
                    const cost_num: u64 = if (cost == .integer)
                        @intCast(cost.integer)
                    else
                        std.fmt.parseInt(u64, cost.string, 10) catch 0;
                    std.log.info("  Gas Used: {d} MIST", .{cost_num});
                }
            }
        }
        if (result.object.get("checkpoint")) |cp| {
            const cp_num: u64 = if (cp == .integer)
                @intCast(cp.integer)
            else
                std.fmt.parseInt(u64, cp.string, 10) catch 0;
            std.log.info("  Checkpoint: {d}", .{cp_num});
        }
        if (result.object.get("timestampMs")) |ts| {
            const ts_num: u64 = if (ts == .integer)
                @intCast(ts.integer)
            else
                std.fmt.parseInt(u64, ts.string, 10) catch 0;
            std.log.info("  Timestamp: {d} ms", .{ts_num});
        }
    }
}

fn cmdCoins(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: coins <address>", .{});
        std.process.exit(1);
    }

    const address = args[0];
    const coin_type = if (args.len >= 2) args[1] else "0x2::sui::SUI";
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",\"{s}\",null,50]",
        .{ address, coin_type },
    );
    defer allocator.free(params);

    const response = try rpc_client.call("suix_getCoins", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Address: {s}", .{address});
    std.log.info("Coin Type: {s}", .{coin_type});

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                std.log.info("Coins: {d}", .{data.array.items.len});

                var total_balance: u64 = 0;

                for (data.array.items, 0..) |item, i| {
                    const coin_object_id = item.object.get("coinObjectId") orelse continue;
                    const balance = item.object.get("balance") orelse continue;
                    const coin_type_str = item.object.get("coinType") orelse continue;

                    const balance_num: u64 = if (balance == .integer)
                        @intCast(balance.integer)
                    else
                        std.fmt.parseInt(u64, balance.string, 10) catch 0;

                    total_balance += balance_num;

                    std.log.info("  {d}. {s}", .{ i + 1, coin_object_id.string });
                    std.log.info("      Balance: {d}", .{balance_num});
                    if (coin_type_str == .string) {
                        std.log.info("      Type: {s}", .{coin_type_str.string});
                    }
                }

                std.log.info("Total Balance: {d}", .{total_balance});

                if (result.object.get("hasNextPage")) |has_next| {
                    if (has_next == .bool and has_next.bool) {
                        if (result.object.get("nextCursor")) |cursor| {
                            if (cursor == .string) {
                                std.log.info("(More coins available, next cursor: {s})", .{cursor.string});
                            }
                        }
                    }
                }
            }
        }
    }
}
