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
    } else if (std.mem.eql(u8, command, "checkpoint")) {
        try cmdCheckpoint(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "epoch")) {
        try cmdEpoch(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "gas")) {
        try cmdGas(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "chain")) {
        try cmdChain(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "transfer")) {
        try cmdTransfer(allocator, args[2..]);
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
    std.log.info("  coins <address> [type]      List coin objects for address", .{});
    std.log.info("  checkpoint [id]             Get checkpoint info (latest if no id)", .{});
    std.log.info("  epoch                       Get current epoch info", .{});
    std.log.info("  gas <address>               Get gas objects for address", .{});
    std.log.info("  chain                       Get chain identifier", .{});
    std.log.info("  transfer <from> <to> <amt>  Build transfer transaction (dry-run)", .{});
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

fn cmdCheckpoint(allocator: Allocator, args: []const []const u8) !void {
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const params = if (args.len >= 1)
        try std.fmt.allocPrint(allocator, "[{s}]", .{args[0]})
    else
        "[]";
    defer if (args.len >= 1) allocator.free(params);

    const response = try rpc_client.call("sui_getLatestCheckpointSequenceNumber", "[]");
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        const seq_num: u64 = if (result == .integer)
            @intCast(result.integer)
        else
            std.fmt.parseInt(u64, result.string, 10) catch 0;
        std.log.info("Latest Checkpoint: {d}", .{seq_num});
    }
}

fn cmdEpoch(allocator: Allocator, _: []const []const u8) !void {
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const response = try rpc_client.call("suix_getLatestSuiSystemState", "[]");
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("epoch")) |epoch| {
            const epoch_num: u64 = if (epoch == .integer)
                @intCast(epoch.integer)
            else
                std.fmt.parseInt(u64, epoch.string, 10) catch 0;
            std.log.info("Current Epoch: {d}", .{epoch_num});
        }
        if (result.object.get("epochDurationMs")) |duration| {
            const duration_num: u64 = if (duration == .integer)
                @intCast(duration.integer)
            else
                std.fmt.parseInt(u64, duration.string, 10) catch 0;
            std.log.info("Epoch Duration: {d} ms", .{duration_num});
        }
        if (result.object.get("epochStartTimestampMs")) |start| {
            const start_num: u64 = if (start == .integer)
                @intCast(start.integer)
            else
                std.fmt.parseInt(u64, start.string, 10) catch 0;
            std.log.info("Epoch Start: {d} ms", .{start_num});
        }
        if (result.object.get("protocolVersion")) |protocol| {
            const protocol_num: u64 = if (protocol == .integer)
                @intCast(protocol.integer)
            else
                std.fmt.parseInt(u64, protocol.string, 10) catch 0;
            std.log.info("Protocol Version: {d}", .{protocol_num});
        }
    }
}

fn cmdGas(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: gas <address>", .{});
        std.process.exit(1);
    }

    const address = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    // Use suix_getCoins with SUI type to get gas objects
    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",\"0x2::sui::SUI\",null,50]",
        .{address},
    );
    defer allocator.free(params);

    const response = try rpc_client.call("suix_getCoins", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Address: {s}", .{address});

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                std.log.info("Gas Objects (SUI): {d}", .{data.array.items.len});

                for (data.array.items, 0..) |item, i| {
                    const coin_object_id = item.object.get("coinObjectId") orelse continue;
                    const balance = item.object.get("balance") orelse continue;

                    const balance_num: u64 = if (balance == .integer)
                        @intCast(balance.integer)
                    else
                        std.fmt.parseInt(u64, balance.string, 10) catch 0;

                    std.log.info("  {d}. {s}", .{ i + 1, coin_object_id.string });
                    std.log.info("      Balance: {d} MIST", .{balance_num});
                }
            }
        }
    }
}

fn cmdChain(allocator: Allocator, _: []const []const u8) !void {
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const response = try rpc_client.call("sui_getChainIdentifier", "[]");
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result == .string) {
            std.log.info("Chain Identifier: {s}", .{result.string});
        }
    }
}

fn cmdTransfer(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.log.err("Usage: transfer <from_address> <to_address> <amount_mist> [--export]", .{});
        std.log.info("Options:", .{});
        std.log.info("  --export    Export transaction for Sui CLI instead of dry-run", .{});
        std.log.info("", .{});
        std.log.info("Example:", .{});
        std.log.info("  sui-zig-rpc-client-v2 transfer 0xFROM 0xTO 1000000 --export", .{});
        std.log.info("  sui client execute-signed-tx --tx-data $(cat tx.json)", .{});
        std.process.exit(1);
    }

    const from = args[0];
    const to = args[1];
    const amount = try std.fmt.parseInt(u64, args[2], 10);
    const export_mode = args.len > 3 and std.mem.eql(u8, args[3], "--export");

    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    std.log.info("Building transfer transaction:", .{});
    std.log.info("  From: {s}", .{from});
    std.log.info("  To: {s}", .{to});
    std.log.info("  Amount: {d} MIST ({d}.{d} SUI)", .{
        amount,
        amount / 1_000_000_000,
        amount % 1_000_000_000,
    });

    // Step 1: Get gas coins for the sender
    const gas_params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",\"0x2::sui::SUI\",null,10]",
        .{from},
    );
    defer allocator.free(gas_params);

    const gas_response = try rpc_client.call("suix_getCoins", gas_params);
    defer allocator.free(gas_response);

    const gas_parsed = try std.json.parseFromSlice(std.json.Value, allocator, gas_response, .{});
    defer gas_parsed.deinit();

    var gas_coin_id: ?[]const u8 = null;
    var gas_balance: u64 = 0;

    if (gas_parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array and data.array.items.len > 0) {
                const first_coin = data.array.items[0];
                if (first_coin.object.get("coinObjectId")) |id| {
                    gas_coin_id = id.string;
                }
                if (first_coin.object.get("balance")) |bal| {
                    gas_balance = if (bal == .integer)
                        @intCast(bal.integer)
                    else
                        std.fmt.parseInt(u64, bal.string, 10) catch 0;
                }
            }
        }
    }

    if (gas_coin_id) |id| {
        std.log.info("  Gas Coin: {s} (balance: {d} MIST)", .{ id, gas_balance });
    } else {
        std.log.err("  Error: No gas coins found for sender", .{});
        return;
    }

    if (export_mode) {
        // Export mode: Generate Sui CLI compatible command
        std.log.info("", .{});
        std.log.info("=== Sui CLI Command ===", .{});
        std.log.info("sui client pay \\", .{});
        std.log.info("  --input-coins {s} \\", .{gas_coin_id.?});
        std.log.info("  --recipients {s} \\", .{to});
        std.log.info("  --amounts {d} \\", .{amount});
        std.log.info("  --gas-budget 5000000 \\", .{});
        std.log.info("  --sender {s}", .{from});
        std.log.info("", .{});
        std.log.info("Or use the simpler transfer command:", .{});
        std.log.info("sui client transfer-sui \\", .{});
        std.log.info("  --to {s} \\", .{to});
        std.log.info("  --sui-coin-object-id {s} \\", .{gas_coin_id.?});
        std.log.info("  --gas-budget 5000000 \\", .{});
        std.log.info("  --amount {d}", .{amount});
    } else {
        // Dry-run mode
        std.log.info("  PTB Structure:", .{});
        std.log.info("    Version: 1", .{});
        std.log.info("    Sender: {s}", .{from});
        std.log.info("    Gas Data:", .{});
        std.log.info("      Payment: {s}", .{gas_coin_id.?});
        std.log.info("      Budget: 5000000 MIST", .{});
        std.log.info("    Inputs:", .{});
        std.log.info("      0: Amount = {d} MIST", .{amount});
        std.log.info("      1: Recipient = {s}", .{to});
        std.log.info("    Commands:", .{});
        std.log.info("      0: TransferObjects([Input(0)], Input(1))", .{});

        std.log.info("", .{});
        std.log.info("Note: This is a dry-run demonstration.", .{});
        std.log.info("Use --export to get the Sui CLI command for actual execution.", .{});
    }
}
