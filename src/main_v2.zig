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
    } else if (std.mem.eql(u8, command, "validators")) {
        try cmdValidators(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "committee")) {
        try cmdCommittee(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "gas-price")) {
        try cmdGasPrice(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "supply")) {
        try cmdSupply(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "events")) {
        try cmdEvents(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "fields")) {
        try cmdFields(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "module")) {
        try cmdModule(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "subscribe")) {
        try cmdSubscribe(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "batch")) {
        try cmdBatch(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "search")) {
        try cmdSearch(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "config")) {
        try cmdConfig(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "history")) {
        try cmdHistory(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "analytics")) {
        try cmdAnalytics(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "compare")) {
        try cmdCompare(allocator, args[2..]);
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
    std.log.info("  validators                  List active validators", .{});
    std.log.info("  committee [epoch]           Get committee info for epoch", .{});
    std.log.info("  gas-price                   Get reference gas price", .{});
    std.log.info("  supply                      Get total SUI supply", .{});
    std.log.info("  events <package> <module>   Query events by module", .{});
    std.log.info("  fields <object_id>          Get dynamic fields of object", .{});
    std.log.info("  module <package> <module>   Get Move module bytecode", .{});
    std.log.info("  subscribe <type>            Subscribe to events (simulated)", .{});
    std.log.info("  batch <file>                Execute batch commands from file", .{});
    std.log.info("  search <address>            Search address summary", .{});
    std.log.info("  config <action>             Manage configuration", .{});
    std.log.info("  history <type> <target>     Query historical data", .{});
    std.log.info("  analytics <type> <address>  Analyze address data", .{});
    std.log.info("  compare <addr1> <addr2>     Compare two addresses", .{});
    std.log.info("  help                        Show this help", .{});
}

fn getRpcUrl() ?[]const u8 {
    return std.process.getEnvVarOwned(std.heap.page_allocator, "SUI_RPC_URL") catch null;
}

fn cmdBalance(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: balance <address> [--format human|json|csv]", .{});
        std.process.exit(1);
    }

    const address = args[0];
    var format: OutputFormat = .human;
    
    // Parse format option
    if (args.len >= 3 and std.mem.eql(u8, args[1], "--format")) {
        if (std.mem.eql(u8, args[2], "json")) {
            format = .json;
        } else if (std.mem.eql(u8, args[2], "csv")) {
            format = .csv;
        } else if (std.mem.eql(u8, args[2], "human")) {
            format = .human;
        }
    }
    
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const balance = try sui_client.rpc_client_new.getBalance(
        &rpc_client,
        address,
        null,
    );

    switch (format) {
        .human => {
            std.log.info("Address: {s}", .{address});
            std.log.info("Balance: {d} MIST ({d}.{d:0>9} SUI)", .{
                balance,
                balance / 1_000_000_000,
                balance % 1_000_000_000,
            });
        },
        .json => {
            std.log.info("{{\"address\":\"{s}\",\"balance_mist\":{d},\"balance_sui\":{d}.{d:0>9}}}", .{
                address,
                balance,
                balance / 1_000_000_000,
                balance % 1_000_000_000,
            });
        },
        .csv => {
            std.log.info("{s},{d},{d}.{d:0>9}", .{
                address,
                balance,
                balance / 1_000_000_000,
                balance % 1_000_000_000,
            });
        },
    }
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
/// Additional commands for main_v2.zig

fn cmdValidators(allocator: Allocator, _: []const []const u8) !void {
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const response = try rpc_client.call("suix_getLatestSuiSystemState", "[]");
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("activeValidators")) |validators| {
            if (validators == .array) {
                std.log.info("Active Validators: {d}", .{validators.array.items.len});

                for (validators.array.items, 0..) |validator, i| {
                    const metadata = validator.object.get("metadata") orelse continue;
                    
                    if (metadata.object.get("name")) |name| {
                        if (name == .string) {
                            std.log.info("  {d}. {s}", .{ i + 1, name.string });
                        }
                    }
                    
                    if (metadata.object.get("suiAddress")) |addr| {
                        std.log.info("      Address: {s}", .{addr.string});
                    }
                    
                    if (validator.object.get("stakingPoolSuiBalance")) |balance| {
                        const balance_num: u64 = if (balance == .integer)
                            @intCast(balance.integer)
                        else
                            std.fmt.parseInt(u64, balance.string, 10) catch 0;
                        std.log.info("      Staking Pool: {d} MIST", .{balance_num});
                    }
                    
                    if (validator.object.get("commissionRate")) |rate| {
                        const rate_num: u64 = if (rate == .integer)
                            @intCast(rate.integer)
                        else
                            std.fmt.parseInt(u64, rate.string, 10) catch 0;
                        std.log.info("      Commission: {d}%", .{rate_num / 100});
                    }
                }
            }
        }
    }
}

fn cmdCommittee(allocator: Allocator, args: []const []const u8) !void {
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const params = if (args.len >= 1)
        try std.fmt.allocPrint(allocator, "[{s}]", .{args[0]})
    else
        "[]";
    defer if (args.len >= 1) allocator.free(params);

    const response = try rpc_client.call("suix_getCommitteeInfo", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("epoch")) |epoch| {
            const epoch_num: u64 = if (epoch == .integer)
                @intCast(epoch.integer)
            else
                std.fmt.parseInt(u64, epoch.string, 10) catch 0;
            std.log.info("Epoch: {d}", .{epoch_num});
        }
        
        if (result.object.get("committeeInfo")) |info| {
            if (info == .array) {
                std.log.info("Committee Members: {d}", .{info.array.items.len});
                
                for (info.array.items) |member| {
                    if (member == .array and member.array.items.len >= 2) {
                        const address = member.array.items[0];
                        const stake = member.array.items[1];
                        
                        const stake_num: u64 = if (stake == .integer)
                            @intCast(stake.integer)
                        else
                            std.fmt.parseInt(u64, stake.string, 10) catch 0;
                        
                        std.log.info("  {s}: {d} MIST", .{ address.string, stake_num });
                    }
                }
            }
        }
    }
}

fn cmdGasPrice(allocator: Allocator, _: []const []const u8) !void {
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const response = try rpc_client.call("suix_getReferenceGasPrice", "[]");
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        const price: u64 = if (result == .integer)
            @intCast(result.integer)
        else
            std.fmt.parseInt(u64, result.string, 10) catch 0;
        std.log.info("Reference Gas Price: {d} MIST", .{price});
    }
}

fn cmdSupply(allocator: Allocator, _: []const []const u8) !void {
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const response = try rpc_client.call("suix_getTotalSupply", "[\"0x2::sui::SUI\"]");
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("value")) |value| {
            const supply: u64 = if (value == .integer)
                @intCast(value.integer)
            else
                std.fmt.parseInt(u64, value.string, 10) catch 0;
            std.log.info("Total SUI Supply: {d} MIST ({d}.{d} SUI)", .{
                supply,
                supply / 1_000_000_000,
                supply % 1_000_000_000,
            });
        }
    }
}
/// Advanced commands for main_v2.zig

fn cmdEvents(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.log.err("Usage: events <package_id> <module_name>", .{});
        std.log.info("Example: events 0x2 coin", .{});
        std.process.exit(1);
    }

    const package_id = args[0];
    const module_name = args[1];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    // Query events by module
    const params = try std.fmt.allocPrint(
        allocator,
        "[{{\"MoveModule\":{{\"package\":\"{s}\",\"module\":\"{s}\"}}}},null,10,null]",
        .{ package_id, module_name },
    );
    defer allocator.free(params);

    const response = try rpc_client.call("suix_queryEvents", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Events for {s}::{s}:", .{ package_id, module_name });

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                std.log.info("Found {d} events", .{data.array.items.len});

                for (data.array.items, 0..) |event, i| {
                    std.log.info("  Event {d}:", .{i + 1});
                    
                    if (event.object.get("txDigest")) |tx| {
                        std.log.info("    Transaction: {s}", .{tx.string});
                    }
                    
                    if (event.object.get("eventType")) |etype| {
                        std.log.info("    Type: {s}", .{etype.string});
                    }
                    
                    if (event.object.get("timestampMs")) |ts| {
                        const ts_num: u64 = if (ts == .integer)
                            @intCast(ts.integer)
                        else
                            std.fmt.parseInt(u64, ts.string, 10) catch 0;
                        std.log.info("    Timestamp: {d} ms", .{ts_num});
                    }
                    
                    if (event.object.get("parsedJson")) |json| {
                        // Print a summary of the event data
                        if (json == .object) {
                            var key_count: usize = 0;
                            for (json.object.keys()) |key| {
                                if (key_count < 3) {
                                    std.log.info("    Data[{s}]: ...", .{key});
                                }
                                key_count += 1;
                            }
                            if (key_count > 3) {
                                std.log.info("    ... and {d} more fields", .{key_count - 3});
                            }
                        }
                    }
                }

                if (result.object.get("hasNextPage")) |has_next| {
                    if (has_next == .bool and has_next.bool) {
                        std.log.info("(More events available)", .{});
                    }
                }
            } else {
                std.log.info("No events found", .{});
            }
        }
    }
}

fn cmdFields(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: fields <object_id>", .{});
        std.process.exit(1);
    }

    const object_id = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",null,50]",
        .{object_id},
    );
    defer allocator.free(params);

    const response = try rpc_client.call("suix_getDynamicFields", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Dynamic Fields for {s}:", .{object_id});

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                std.log.info("Found {d} dynamic fields", .{data.array.items.len});

                for (data.array.items, 0..) |field, i| {
                    std.log.info("  Field {d}:", .{i + 1});
                    
                    if (field.object.get("name")) |name| {
                        if (name.object.get("type")) |t| {
                            std.log.info("    Type: {s}", .{t.string});
                        }
                        if (name.object.get("value")) |v| {
                            switch (v) {
                                .string => |s| std.log.info("    Name: {s}", .{s}),
                                .integer => |n| std.log.info("    Name: {d}", .{n}),
                                else => std.log.info("    Name: (complex)", .{}),
                            }
                        }
                    }
                    
                    if (field.object.get("objectType")) |otype| {
                        std.log.info("    Object Type: {s}", .{otype.string});
                    }
                    
                    if (field.object.get("objectId")) |id| {
                        std.log.info("    Object ID: {s}", .{id.string});
                    }
                }

                if (result.object.get("hasNextPage")) |has_next| {
                    if (has_next == .bool and has_next.bool) {
                        std.log.info("(More fields available)", .{});
                    }
                }
            } else {
                std.log.info("No dynamic fields found", .{});
            }
        }
    }
}

fn cmdModule(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.log.err("Usage: module <package_id> <module_name>", .{});
        std.log.info("Example: module 0x2 coin", .{});
        std.process.exit(1);
    }

    const package_id = args[0];
    const module_name = args[1];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",\"{s}\"]",
        .{ package_id, module_name },
    );
    defer allocator.free(params);

    const response = try rpc_client.call("sui_getNormalizedMoveModule", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    std.log.info("Module {s}::{s}:", .{ package_id, module_name });

    if (parsed.value.object.get("result")) |result| {
        // Show structs
        if (result.object.get("structs")) |structs| {
            if (structs == .object) {
                const struct_count = structs.object.count();
                std.log.info("  Structs: {d}", .{struct_count});
                
                var it = structs.object.iterator();
                var i: usize = 0;
                while (it.next()) |entry| : (i += 1) {
                    if (i < 5) {
                        std.log.info("    - {s}", .{entry.key_ptr.*});
                    }
                }
                if (struct_count > 5) {
                    std.log.info("    ... and {d} more", .{struct_count - 5});
                }
            }
        }

        // Show functions
        if (result.object.get("exposedFunctions")) |funcs| {
            if (funcs == .object) {
                const func_count = funcs.object.count();
                std.log.info("  Functions: {d}", .{func_count});
                
                var it = funcs.object.iterator();
                var i: usize = 0;
                while (it.next()) |entry| : (i += 1) {
                    if (i < 5) {
                        std.log.info("    - {s}", .{entry.key_ptr.*});
                    }
                }
                if (func_count > 5) {
                    std.log.info("    ... and {d} more", .{func_count - 5});
                }
            }
        }
    }
}
/// Extra advanced commands for main_v2.zig

fn cmdSubscribe(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: subscribe <type>", .{});
        std.log.info("Types:", .{});
        std.log.info("  events <package> <module>  Poll for new events", .{});
        std.log.info("  checkpoints                Poll for new checkpoints", .{});
        std.log.info("  transactions <address>     Poll for new transactions", .{});
        std.process.exit(1);
    }

    const sub_type = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    if (std.mem.eql(u8, sub_type, "events")) {
        if (args.len < 3) {
            std.log.err("Usage: subscribe events <package> <module>", .{});
            std.process.exit(1);
        }

        const package_id = args[1];
        const module_name = args[2];

        std.log.info("Subscribing to events for {s}::{s}...", .{ package_id, module_name });
        std.log.info("(Press Ctrl+C to stop)", .{});
        std.log.info("", .{});

        var last_seen: ?[]const u8 = null;
        defer if (last_seen) |ls| allocator.free(ls);

        var poll_count: u32 = 0;
        while (poll_count < 10) : (poll_count += 1) {
            const params = try std.fmt.allocPrint(
                allocator,
                "[{{\"MoveModule\":{{\"package\":\"{s}\",\"module\":\"{s}\"}}}},null,10,null]",
                .{ package_id, module_name },
            );
            defer allocator.free(params);

            const response = try rpc_client.call("suix_queryEvents", params);
            defer allocator.free(response);

            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
            defer parsed.deinit();

            if (parsed.value.object.get("result")) |result| {
                if (result.object.get("data")) |data| {
                    if (data == .array and data.array.items.len > 0) {
                        // Check for new events
                        const first_event = data.array.items[0];
                        if (first_event.object.get("txDigest")) |tx| {
                            const tx_str = tx.string;
                            
                            if (last_seen == null or !std.mem.eql(u8, last_seen.?, tx_str)) {
                                if (last_seen) |ls| allocator.free(ls);
                                last_seen = try allocator.dupe(u8, tx_str);

                                std.log.info("New event detected!", .{});
                                std.log.info("  Transaction: {s}", .{tx_str});
                                
                                if (first_event.object.get("timestampMs")) |ts| {
                                    const ts_num: u64 = if (ts == .integer)
                                        @intCast(ts.integer)
                                    else
                                        std.fmt.parseInt(u64, ts.string, 10) catch 0;
                                    std.log.info("  Timestamp: {d} ms", .{ts_num});
                                }
                                std.log.info("", .{});
                            }
                        }
                    }
                }
            }

            // Wait before polling again
            std.Thread.sleep(2 * std.time.ns_per_s);
        }

        std.log.info("Subscription ended after {d} polls", .{poll_count});

    } else if (std.mem.eql(u8, sub_type, "checkpoints")) {
        std.log.info("Subscribing to new checkpoints...", .{});
        std.log.info("(Press Ctrl+C to stop)", .{});
        std.log.info("", .{});

        var last_checkpoint: u64 = 0;
        var poll_count: u32 = 0;

        while (poll_count < 20) : (poll_count += 1) {
            const response = try rpc_client.call("sui_getLatestCheckpointSequenceNumber", "[]");
            defer allocator.free(response);

            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
            defer parsed.deinit();

            if (parsed.value.object.get("result")) |result| {
                const current: u64 = if (result == .integer)
                    @intCast(result.integer)
                else
                    std.fmt.parseInt(u64, result.string, 10) catch 0;

                if (current > last_checkpoint) {
                    if (last_checkpoint > 0) {
                        const new_count = current - last_checkpoint;
                        std.log.info("New checkpoint: {d} (+{d})", .{ current, new_count });
                    } else {
                        std.log.info("Current checkpoint: {d}", .{current});
                    }
                    last_checkpoint = current;
                }
            }

            std.Thread.sleep(1 * std.time.ns_per_s);
        }

        std.log.info("Subscription ended after {d} polls", .{poll_count});

    } else if (std.mem.eql(u8, sub_type, "transactions")) {
        if (args.len < 2) {
            std.log.err("Usage: subscribe transactions <address>", .{});
            std.process.exit(1);
        }

        const address = args[1];
        std.log.info("Subscribing to transactions for {s}...", .{address});
        std.log.info("(Press Ctrl+C to stop)", .{});
        std.log.info("", .{});

        var last_count: usize = 0;
        var poll_count: u32 = 0;

        while (poll_count < 10) : (poll_count += 1) {
            const params = try std.fmt.allocPrint(
                allocator,
                "[\"{s}\",null,1,descending]",
                .{address},
            );
            defer allocator.free(params);

            const response = try rpc_client.call("suix_queryTransactionBlocks", params);
            defer allocator.free(response);

            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
            defer parsed.deinit();

            if (parsed.value.object.get("result")) |result| {
                if (result.object.get("data")) |data| {
                    if (data == .array) {
                        const current_count = data.array.items.len;
                        
                        if (current_count > 0 and current_count != last_count) {
                            if (last_count > 0) {
                                std.log.info("New transaction detected!", .{});
                                if (data.array.items[0].object.get("digest")) |digest| {
                                    std.log.info("  Digest: {s}", .{digest.string});
                                }
                            }
                            last_count = current_count;
                        }
                    }
                }
            }

            std.Thread.sleep(3 * std.time.ns_per_s);
        }

        std.log.info("Subscription ended after {d} polls", .{poll_count});

    } else {
        std.log.err("Unknown subscription type: {s}", .{sub_type});
        std.process.exit(1);
    }
}

fn cmdBatch(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: batch <command_file>", .{});
        std.log.info("File format: one command per line", .{});
        std.log.info("Example file:", .{});
        std.log.info("  balance 0xADDRESS1", .{});
        std.log.info("  balance 0xADDRESS2", .{});
        std.log.info("  objects 0xADDRESS1", .{});
        std.process.exit(1);
    }

    const file_path = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    // Read command file
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.log.err("Failed to open file: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.log.err("Failed to read file: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    defer allocator.free(content);

    std.log.info("Executing batch commands from {s}...", .{file_path});
    std.log.info("", .{});

    var lines = std.mem.splitSequence(u8, content, "\n");
    var line_num: u32 = 0;
    var success_count: u32 = 0;
    var fail_count: u32 = 0;

    while (lines.next()) |line| {
        line_num += 1;
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        
        // Skip empty lines and comments
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "#")) {
            continue;
        }

        std.log.info("[{d}] Executing: {s}", .{ line_num, trimmed });

        // Parse command line
        var parts = std.mem.splitSequence(u8, trimmed, " ");
        var cmd_parts: [10][]const u8 = undefined;
        var part_count: usize = 0;

        while (parts.next()) |part| {
            if (part_count < 10) {
                cmd_parts[part_count] = part;
                part_count += 1;
            }
        }

        if (part_count == 0) continue;

        const cmd = cmd_parts[0];
        const cmd_args = cmd_parts[1..part_count];

        // Execute command
        var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
        
        if (std.mem.eql(u8, cmd, "balance")) {
            if (cmd_args.len >= 1) {
                cmdBalance(allocator, cmd_args) catch |err| {
                    std.log.err("  Error: {s}", .{@errorName(err)});
                    fail_count += 1;
                    continue;
                };
                success_count += 1;
            }
        } else if (std.mem.eql(u8, cmd, "objects")) {
            if (cmd_args.len >= 1) {
                cmdObjects(allocator, cmd_args) catch |err| {
                    std.log.err("  Error: {s}", .{@errorName(err)});
                    fail_count += 1;
                    continue;
                };
                success_count += 1;
            }
        } else if (std.mem.eql(u8, cmd, "gas")) {
            if (cmd_args.len >= 1) {
                cmdGas(allocator, cmd_args) catch |err| {
                    std.log.err("  Error: {s}", .{@errorName(err)});
                    fail_count += 1;
                    continue;
                };
                success_count += 1;
            }
        } else {
            std.log.warn("  Unknown command: {s}", .{cmd});
            fail_count += 1;
        }

        rpc_client.deinit();
        std.log.info("", .{});
    }

    std.log.info("Batch execution complete:", .{});
    std.log.info("  Successful: {d}", .{success_count});
    std.log.info("  Failed: {d}", .{fail_count});
}

fn cmdSearch(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: search <address>", .{});
        std.log.info("Search for objects and transactions by address", .{});
        std.process.exit(1);
    }

    const address = args[0];
    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";

    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    std.log.info("Searching for address: {s}", .{address});
    std.log.info("", .{});

    // Search 1: Get balance
    std.log.info("=== Balance ===", .{});
    const balance = sui_client.rpc_client_new.getBalance(
        &rpc_client,
        address,
        null,
    ) catch |err| {
        std.log.info("  Error: {s}", .{@errorName(err)});
        return;
    };
    std.log.info("  {d} MIST ({d}.{d} SUI)", .{
        balance,
        balance / 1_000_000_000,
        balance % 1_000_000_000,
    });

    // Search 2: Get objects count
    std.log.info("", .{});
    std.log.info("=== Objects ===", .{});
    const params = try std.fmt.allocPrint(
        allocator,
        "[\"{s}\",null,null,1]",
        .{address},
    );
    defer allocator.free(params);

    const response = try rpc_client.call("suix_getOwnedObjects", params);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                std.log.info("  {d} objects owned", .{data.array.items.len});
                
                if (result.object.get("hasNextPage")) |has_next| {
                    if (has_next == .bool and has_next.bool) {
                        std.log.info("  (More objects available)", .{});
                    }
                }
            }
        }
    }

    std.log.info("", .{});
    std.log.info("Use 'objects {s}' to list all objects", .{address});
}
/// Configuration and output formatting for main_v2.zig

const OutputFormat = enum {
    human,
    json,
    csv,
};

const Config = struct {
    rpc_url: []const u8,
    default_address: ?[]const u8,
    output_format: OutputFormat,
    verbose: bool,

    fn default(allocator: Allocator) Config {
        return .{
            .rpc_url = allocator.dupe(u8, "https://fullnode.mainnet.sui.io:443") catch unreachable,
            .default_address = null,
            .output_format = .human,
            .verbose = false,
        };
    }

    fn deinit(self: *Config, allocator: Allocator) void {
        allocator.free(self.rpc_url);
        if (self.default_address) |addr| allocator.free(addr);
    }
};

var global_config: ?Config = null;

fn getConfig(allocator: Allocator) !*Config {
    if (global_config == null) {
        global_config = try loadConfig(allocator);
    }
    return &global_config.?;
}

fn loadConfig(allocator: Allocator) !Config {
    // Try to load from config file
    const config_path = getConfigPath() orelse return Config.default(allocator);
    
    const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return Config.default(allocator);
        }
        return err;
    };
    defer file.close();
    
    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.log.warn("Failed to read config: {s}", .{@errorName(err)});
        return Config.default(allocator);
    };
    defer allocator.free(content);
    
    var config = Config.default(allocator);
    
    // Simple key=value parser
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "#")) {
            continue;
        }
        
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
            
            if (std.mem.eql(u8, key, "rpc_url")) {
                allocator.free(config.rpc_url);
                config.rpc_url = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "default_address")) {
                if (config.default_address) |addr| allocator.free(addr);
                config.default_address = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "output_format")) {
                if (std.mem.eql(u8, value, "json")) {
                    config.output_format = .json;
                } else if (std.mem.eql(u8, value, "csv")) {
                    config.output_format = .csv;
                } else {
                    config.output_format = .human;
                }
            } else if (std.mem.eql(u8, key, "verbose")) {
                config.verbose = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
            }
        }
    }
    
    return config;
}

fn getConfigPath() ?[]const u8 {
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "SUI_ZIG_CONFIG")) |path| {
        return path;
    } else |_| {}
    
    const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch return null;
    defer std.heap.page_allocator.free(home);
    
    return std.fs.path.join(std.heap.page_allocator, &[_][]const u8{
        home, ".config", "sui-zig", "config",
    }) catch null;
}

fn saveConfig(_: Allocator, config: Config) !void {
    const config_path = getConfigPath() orelse {
        std.log.err("Could not determine config path", .{});
        return;
    };
    defer std.heap.page_allocator.free(config_path);
    
    // Ensure directory exists
    const config_dir = std.fs.path.dirname(config_path).?;
    std.fs.cwd().makePath(config_dir) catch |err| {
        std.log.err("Failed to create config directory: {s}", .{@errorName(err)});
        return;
    };
    
    const file = try std.fs.cwd().createFile(config_path, .{});
    defer file.close();
    
    // Write config content
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    
    try writer.print("# Sui Zig RPC Client Configuration\n", .{});
    try writer.print("# Generated automatically\n\n", .{});
    try writer.print("rpc_url=\"{s}\"\n", .{config.rpc_url});
    if (config.default_address) |addr| {
        try writer.print("default_address=\"{s}\"\n", .{addr});
    }
    try writer.print("output_format=\"{s}\"\n", .{@tagName(config.output_format)});
    try writer.print("verbose={s}\n", .{if (config.verbose) "true" else "false"});
    
    const written = fbs.getWritten();
    try file.writeAll(written);
    
    std.log.info("Config saved to {s}", .{config_path});
}

fn cmdConfig(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: config <action>", .{});
        std.log.info("Actions:", .{});
        std.log.info("  show                    Show current config", .{});
        std.log.info("  set <key> <value>       Set config value", .{});
        std.log.info("  get <key>               Get config value", .{});
        std.log.info("  init                    Create default config", .{});
        std.log.info("", .{});
        std.log.info("Config keys:", .{});
        std.log.info("  rpc_url                 RPC endpoint URL", .{});
        std.log.info("  default_address         Default wallet address", .{});
        std.log.info("  output_format           human|json|csv", .{});
        std.log.info("  verbose                 true|false", .{});
        std.process.exit(1);
    }
    
    const action = args[0];
    
    if (std.mem.eql(u8, action, "show")) {
        var config = try loadConfig(allocator);
        defer config.deinit(allocator);
        
        std.log.info("Current configuration:", .{});
        std.log.info("  rpc_url: {s}", .{config.rpc_url});
        std.log.info("  default_address: {s}", .{config.default_address orelse "(none)"});
        std.log.info("  output_format: {s}", .{@tagName(config.output_format)});
        std.log.info("  verbose: {s}", .{if (config.verbose) "true" else "false"});
        
        if (getConfigPath()) |path| {
            defer std.heap.page_allocator.free(path);
            std.log.info("  config_file: {s}", .{path});
        }
        
    } else if (std.mem.eql(u8, action, "set")) {
        if (args.len < 3) {
            std.log.err("Usage: config set <key> <value>", .{});
            std.process.exit(1);
        }
        
        var config = try loadConfig(allocator);
        defer config.deinit(allocator);
        
        const key = args[1];
        const value = args[2];
        
        if (std.mem.eql(u8, key, "rpc_url")) {
            allocator.free(config.rpc_url);
            config.rpc_url = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "default_address")) {
            if (config.default_address) |addr| allocator.free(addr);
            config.default_address = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "output_format")) {
            if (std.mem.eql(u8, value, "json")) {
                config.output_format = .json;
            } else if (std.mem.eql(u8, value, "csv")) {
                config.output_format = .csv;
            } else if (std.mem.eql(u8, value, "human")) {
                config.output_format = .human;
            } else {
                std.log.err("Invalid output format: {s}", .{value});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, key, "verbose")) {
            config.verbose = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
        } else {
            std.log.err("Unknown config key: {s}", .{key});
            std.process.exit(1);
        }
        
        try saveConfig(allocator, config);
        std.log.info("Set {s} = {s}", .{ key, value });
        
    } else if (std.mem.eql(u8, action, "get")) {
        if (args.len < 2) {
            std.log.err("Usage: config get <key>", .{});
            std.process.exit(1);
        }
        
        var config = try loadConfig(allocator);
        defer config.deinit(allocator);
        
        const key = args[1];
        
        if (std.mem.eql(u8, key, "rpc_url")) {
            std.log.info("{s}", .{config.rpc_url});
        } else if (std.mem.eql(u8, key, "default_address")) {
            std.log.info("{s}", .{config.default_address orelse ""});
        } else if (std.mem.eql(u8, key, "output_format")) {
            std.log.info("{s}", .{@tagName(config.output_format)});
        } else if (std.mem.eql(u8, key, "verbose")) {
            std.log.info("{s}", .{if (config.verbose) "true" else "false"});
        } else {
            std.log.err("Unknown config key: {s}", .{key});
            std.process.exit(1);
        }
        
    } else if (std.mem.eql(u8, action, "init")) {
        var config = Config.default(allocator);
        defer config.deinit(allocator);
        try saveConfig(allocator, config);
        std.log.info("Created default config file", .{});
        
    } else {
        std.log.err("Unknown action: {s}", .{action});
        std.process.exit(1);
    }
}

// Output formatting helpers
fn printJsonBalance(writer: anytype, address: []const u8, balance: u64) !void {
    try writer.print("{{" +
        "\"address\":\"{s}\"," +
        "\"balance\":{d}," +
        "\"balance_sui\":{d}.{d:0>9}" +
        "}}\n", .{
        address,
        balance,
        balance / 1_000_000_000,
        balance % 1_000_000_000,
    });
}

fn printCsvBalance(writer: anytype, address: []const u8, balance: u64) !void {
    try writer.print("{s},{d},{d}.{d:0>9}\n", .{
        address,
        balance,
        balance / 1_000_000_000,
        balance % 1_000_000_000,
    });
}

fn printHumanBalance(address: []const u8, balance: u64) void {
    std.log.info("Address: {s}", .{address});
    std.log.info("Balance: {d} MIST ({d}.{d:0>9} SUI)", .{
        balance,
        balance / 1_000_000_000,
        balance % 1_000_000_000,
    });
}

fn printJsonObject(writer: anytype, obj: ObjectInfo) !void {
    try writer.print("{{" +
        "\"id\":\"{s}\"," +
        "\"type\":\"{s}\"," +
        "\"version\":{d}," +
        "\"digest\":\"{s}\"" +
        "}}\n", .{
        obj.id,
        obj.type,
        obj.version,
        obj.digest,
    });
}

fn printCsvObject(writer: anytype, obj: ObjectInfo) !void {
    try writer.print("{s},{s},{d},{s}\n", .{
        obj.id,
        obj.type,
        obj.version,
        obj.digest,
    });
}

fn printHumanObject(obj: ObjectInfo, index: usize) void {
    std.log.info("  {d}. {s}", .{ index, obj.id });
    std.log.info("      Type: {s}", .{obj.type});
    std.log.info("      Version: {d}, Digest: {s}", .{ obj.version, obj.digest });
}

const ObjectInfo = struct {
    id: []const u8,
    type: []const u8,
    version: u64,
    digest: []const u8,
};
/// History and analytics commands for main_v2.zig

fn cmdHistory(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.log.err("Usage: history <type> <address_or_id>", .{});
        std.log.info("Types:", .{});
        std.log.info("  transactions <address> [limit]  Query transaction history", .{});
        std.log.info("  checkpoints [limit]             Query recent checkpoints", .{});
        std.log.info("  epochs [limit]                  Query epoch history", .{});
        std.process.exit(1);
    }

    const history_type = args[0];
    const target = args[1];
    const limit = if (args.len >= 3) std.fmt.parseInt(u32, args[2], 10) catch 10 else 10;

    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";
    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    if (std.mem.eql(u8, history_type, "transactions")) {
        std.log.info("Transaction history for {s} (limit: {d}):", .{ target, limit });
        std.log.info("", .{});

        // Query transactions for address
        const params = try std.fmt.allocPrint(
            allocator,
            "[{{\"FromAddress\":\"{s}\"}},null,{d},descending]",
            .{ target, limit },
        );
        defer allocator.free(params);

        const response = try rpc_client.call("suix_queryTransactionBlocks", params);
        defer allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
        defer parsed.deinit();

        if (parsed.value.object.get("result")) |result| {
            if (result.object.get("data")) |data| {
                if (data == .array) {
                    std.log.info("Found {d} transactions:", .{data.array.items.len});
                    std.log.info("", .{});

                    for (data.array.items, 0..) |tx, i| {
                        std.log.info("Transaction {d}:", .{i + 1});

                        if (tx.object.get("digest")) |digest| {
                            std.log.info("  Digest: {s}", .{digest.string});
                        }

                        if (tx.object.get("checkpoint")) |cp| {
                            const cp_num: u64 = if (cp == .integer)
                                @intCast(cp.integer)
                            else
                                std.fmt.parseInt(u64, cp.string, 10) catch 0;
                            std.log.info("  Checkpoint: {d}", .{cp_num});
                        }

                        if (tx.object.get("timestampMs")) |ts| {
                            const ts_num: u64 = if (ts == .integer)
                                @intCast(ts.integer)
                            else
                                std.fmt.parseInt(u64, ts.string, 10) catch 0;
                            std.log.info("  Timestamp: {d} ms", .{ts_num});
                        }

                        if (tx.object.get("effects")) |effects| {
                            if (effects.object.get("status")) |status| {
                                if (status.object.get("status")) |s| {
                                    std.log.info("  Status: {s}", .{s.string});
                                }
                            }
                        }

                        std.log.info("", .{});
                    }

                    if (result.object.get("hasNextPage")) |has_next| {
                        if (has_next == .bool and has_next.bool) {
                            std.log.info("(More transactions available)", .{});
                        }
                    }
                } else {
                    std.log.info("No transactions found", .{});
                }
            }
        }
    } else if (std.mem.eql(u8, history_type, "checkpoints")) {
        std.log.info("Recent checkpoints (limit: {d}):", .{limit});
        std.log.info("", .{});

        // Get latest checkpoint number
        const latest_response = try rpc_client.call("sui_getLatestCheckpointSequenceNumber", "[]");
        defer allocator.free(latest_response);

        const latest_parsed = try std.json.parseFromSlice(std.json.Value, allocator, latest_response, .{});
        defer latest_parsed.deinit();

        const latest: u64 = if (latest_parsed.value.object.get("result")) |result|
            if (result == .integer) @intCast(result.integer) else std.fmt.parseInt(u64, result.string, 10) catch 0
        else
            0;

        // Query recent checkpoints
        var count: u32 = 0;
        var seq: u64 = latest;
        while (count < limit and seq > 0) : (count += 1) {
            const params = try std.fmt.allocPrint(allocator, "[{d}]", .{seq});
            defer allocator.free(params);

            const response = try rpc_client.call("sui_getCheckpoint", params);
            defer allocator.free(response);

            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
            defer parsed.deinit();

            if (parsed.value.object.get("result")) |result| {
                std.log.info("Checkpoint {d}:", .{seq});

                if (result.object.get("digest")) |digest| {
                    std.log.info("  Digest: {s}", .{digest.string});
                }

                if (result.object.get("epoch")) |epoch| {
                    const epoch_num: u64 = if (epoch == .integer)
                        @intCast(epoch.integer)
                    else
                        std.fmt.parseInt(u64, epoch.string, 10) catch 0;
                    std.log.info("  Epoch: {d}", .{epoch_num});
                }

                if (result.object.get("timestampMs")) |ts| {
                    const ts_num: u64 = if (ts == .integer)
                        @intCast(ts.integer)
                    else
                        std.fmt.parseInt(u64, ts.string, 10) catch 0;
                    std.log.info("  Timestamp: {d} ms", .{ts_num});
                }

                if (result.object.get("transactions")) |txs| {
                    if (txs == .array) {
                        std.log.info("  Transactions: {d}", .{txs.array.items.len});
                    }
                }

                std.log.info("", .{});
            }

            seq -= 1;
        }
    } else if (std.mem.eql(u8, history_type, "epochs")) {
        std.log.info("Epoch history (limit: {d}):", .{limit});
        std.log.info("", .{});

        // Get current epoch
        const epoch_response = try rpc_client.call("sui_getEpoch", "[]");
        defer allocator.free(epoch_response);

        const epoch_parsed = try std.json.parseFromSlice(std.json.Value, allocator, epoch_response, .{});
        defer epoch_parsed.deinit();

        const current_epoch: u64 = if (epoch_parsed.value.object.get("result")) |result|
            if (result.object.get("epoch")) |e|
                if (e == .integer) @intCast(e.integer) else std.fmt.parseInt(u64, e.string, 10) catch 0
            else
                0
        else
            0;

        std.log.info("Current epoch: {d}", .{current_epoch});
        std.log.info("", .{});

        // Query recent epochs
        var count: u32 = 0;
        var epoch: u64 = current_epoch;
        while (count < limit and epoch > 0) : (count += 1) {
            const params = try std.fmt.allocPrint(allocator, "[{d}]", .{epoch});
            defer allocator.free(params);

            const response = try rpc_client.call("sui_getCommittee", params);
            defer allocator.free(response);

            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
            defer parsed.deinit();

            if (parsed.value.object.get("result")) |result| {
                std.log.info("Epoch {d}:", .{epoch});

                if (result.object.get("validators")) |validators| {
                    if (validators == .object) {
                        std.log.info("  Validators: {d}", .{validators.object.count()});
                    }
                }

                std.log.info("", .{});
            }

            epoch -= 1;
        }
    } else {
        std.log.err("Unknown history type: {s}", .{history_type});
        std.process.exit(1);
    }
}

fn cmdAnalytics(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.log.err("Usage: analytics <type> <address>", .{});
        std.log.info("Types:", .{});
        std.log.info("  portfolio <address>      Analyze token portfolio", .{});
        std.log.info("  activity <address>       Analyze transaction activity", .{});
        std.log.info("  gas <address>            Analyze gas usage", .{});
        std.process.exit(1);
    }

    const analytics_type = args[0];
    const address = args[1];

    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";
    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    if (std.mem.eql(u8, analytics_type, "portfolio")) {
        std.log.info("Portfolio analysis for {s}:", .{address});
        std.log.info("", .{});

        // Get all coins
        const params = try std.fmt.allocPrint(
            allocator,
            "[\"{s}\",null,null,50]",
            .{address},
        );
        defer allocator.free(params);

        const response = try rpc_client.call("suix_getAllCoins", params);
        defer allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
        defer parsed.deinit();

        var total_sui: u64 = 0;
        var coin_count: u32 = 0;
        var coin_types: u32 = 0;

        if (parsed.value.object.get("result")) |result| {
            if (result.object.get("data")) |data| {
                if (data == .array) {
                    for (data.array.items) |coin| {
                        coin_count += 1;

                        if (coin.object.get("balance")) |bal| {
                            const balance: u64 = if (bal == .integer)
                                @intCast(bal.integer)
                            else
                                std.fmt.parseInt(u64, bal.string, 10) catch 0;

                            if (coin.object.get("coinType")) |coin_type| {
                                if (std.mem.eql(u8, coin_type.string, "0x2::sui::SUI")) {
                                    total_sui += balance;
                                } else {
                                    coin_types += 1;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Get balance for comparison
        const balance = sui_client.rpc_client_new.getBalance(
            &rpc_client,
            address,
            null,
        ) catch 0;

        std.log.info("=== Portfolio Summary ===", .{});
        std.log.info("Total SUI Balance: {d} MIST ({d}.{d:0>9} SUI)", .{
            balance,
            balance / 1_000_000_000,
            balance % 1_000_000_000,
        });
        std.log.info("Coin Objects: {d}", .{coin_count});
        std.log.info("Non-SUI Token Types: {d}", .{coin_types});

        if (balance > 0) {
            const avg_balance = balance / coin_count;
            std.log.info("Average Balance per Coin: {d} MIST", .{avg_balance});
        }

    } else if (std.mem.eql(u8, analytics_type, "activity")) {
        std.log.info("Activity analysis for {s}:", .{address});
        std.log.info("", .{});

        // Query recent transactions
        const params = try std.fmt.allocPrint(
            allocator,
            "[{{\"FromAddress\":\"{s}\"}},null,20,descending]",
            .{address},
        );
        defer allocator.free(params);

        const response = try rpc_client.call("suix_queryTransactionBlocks", params);
        defer allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
        defer parsed.deinit();

        var tx_count: u32 = 0;
        var success_count: u32 = 0;
        var fail_count: u32 = 0;
        var oldest_ts: u64 = 0;
        var newest_ts: u64 = 0;

        if (parsed.value.object.get("result")) |result| {
            if (result.object.get("data")) |data| {
                if (data == .array) {
                    tx_count = @intCast(data.array.items.len);

                    for (data.array.items) |tx| {
                        // Check status
                        if (tx.object.get("effects")) |effects| {
                            if (effects.object.get("status")) |status| {
                                if (status.object.get("status")) |s| {
                                    if (std.mem.eql(u8, s.string, "success")) {
                                        success_count += 1;
                                    } else {
                                        fail_count += 1;
                                    }
                                }
                            }
                        }

                        // Track timestamps
                        if (tx.object.get("timestampMs")) |ts| {
                            const ts_num: u64 = if (ts == .integer)
                                @intCast(ts.integer)
                            else
                                std.fmt.parseInt(u64, ts.string, 10) catch 0;

                            if (newest_ts == 0) newest_ts = ts_num;
                            oldest_ts = ts_num;
                        }
                    }
                }
            }
        }

        std.log.info("=== Activity Summary ===", .{});
        std.log.info("Total Transactions: {d}", .{tx_count});
        std.log.info("Successful: {d}", .{success_count});
        std.log.info("Failed: {d}", .{fail_count});

        if (tx_count > 0) {
            const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(tx_count)) * 100.0;
            std.log.info("Success Rate: {d:.1}%", .{@as(u32, @intFromFloat(success_rate))});
        }

        if (newest_ts > oldest_ts) {
            const time_span = newest_ts - oldest_ts;
            const days = time_span / (24 * 60 * 60 * 1000);
            std.log.info("Activity Span: {d} days", .{days});

            if (days > 0) {
                const tx_per_day = @as(f64, @floatFromInt(tx_count)) / @as(f64, @floatFromInt(days));
                std.log.info("Avg Transactions/Day: {d:.1}", .{tx_per_day});
            }
        }

    } else if (std.mem.eql(u8, analytics_type, "gas")) {
        std.log.info("Gas usage analysis for {s}:", .{address});
        std.log.info("", .{});

        // Get gas objects to analyze
        const params = try std.fmt.allocPrint(
            allocator,
            "[\"{s}\",null,null,10]",
            .{address},
        );
        defer allocator.free(params);

        const response = try rpc_client.call("suix_getOwnedObjects", params);
        defer allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
        defer parsed.deinit();

        var gas_objects: u32 = 0;
        var total_gas_balance: u64 = 0;

        if (parsed.value.object.get("result")) |result| {
            if (result.object.get("data")) |data| {
                if (data == .array) {
                    for (data.array.items) |item| {
                        if (item.object.get("data")) |obj_data| {
                            // Check if it's a gas object (SUI coin)
                            if (obj_data.object.get("type")) |t| {
                                if (t == .string and std.mem.eql(u8, t.string, "0x2::coin::Coin<0x2::sui::SUI>")) {
                                    gas_objects += 1;
                                    if (obj_data.object.get("content")) |content| {
                                        if (content.object.get("fields")) |fields| {
                                            if (fields.object.get("balance")) |bal| {
                                                const balance: u64 = if (bal == .integer)
                                                    @intCast(bal.integer)
                                                else
                                                    std.fmt.parseInt(u64, bal.string, 10) catch 0;
                                                total_gas_balance += balance;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        const gas_price: u64 = 1000; // Default reference gas price

        std.log.info("=== Gas Analysis ===", .{});
        std.log.info("Gas Objects: {d}", .{gas_objects});
        std.log.info("Total Gas Balance: {d} MIST", .{total_gas_balance});
        std.log.info("Reference Gas Price: {d} MIST (estimated)", .{gas_price});
        std.log.info("", .{});
        std.log.info("Estimated Simple Transfer Cost: ~{d} MIST", .{gas_price * 2000});
        std.log.info("Estimated Complex Tx Cost: ~{d} MIST", .{gas_price * 10000});
    } else {
        std.log.err("Unknown analytics type: {s}", .{analytics_type});
        std.process.exit(1);
    }
}

fn cmdCompare(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.log.err("Usage: compare <address1> <address2>", .{});
        std.log.info("Compare two addresses across various metrics", .{});
        std.process.exit(1);
    }

    const addr1 = args[0];
    const addr2 = args[1];

    const rpc_url = getRpcUrl() orelse "https://fullnode.mainnet.sui.io:443";
    var rpc_client = try SuiRpcClient.init(allocator, rpc_url);
    defer rpc_client.deinit();

    std.log.info("Comparing addresses:", .{});
    std.log.info("  A: {s}", .{addr1});
    std.log.info("  B: {s}", .{addr2});
    std.log.info("", .{});

    // Compare balances
    const balance1 = sui_client.rpc_client_new.getBalance(
        &rpc_client,
        addr1,
        null,
    ) catch 0;

    const balance2 = sui_client.rpc_client_new.getBalance(
        &rpc_client,
        addr2,
        null,
    ) catch 0;

    std.log.info("=== Balance Comparison ===", .{});
    std.log.info("A: {d}.{d:0>9} SUI", .{ balance1 / 1_000_000_000, balance1 % 1_000_000_000 });
    std.log.info("B: {d}.{d:0>9} SUI", .{ balance2 / 1_000_000_000, balance2 % 1_000_000_000 });

    if (balance1 > balance2) {
        const diff = balance1 - balance2;
        std.log.info("A has {d}.{d:0>9} SUI more than B", .{ diff / 1_000_000_000, diff % 1_000_000_000 });
    } else if (balance2 > balance1) {
        const diff = balance2 - balance1;
        std.log.info("B has {d}.{d:0>9} SUI more than A", .{ diff / 1_000_000_000, diff % 1_000_000_000 });
    } else {
        std.log.info("Both have equal balance", .{});
    }

    // Compare object counts
    const params1 = try std.fmt.allocPrint(allocator, "[\"{s}\",null,null,1]", .{addr1});
    defer allocator.free(params1);

    const response1 = try rpc_client.call("suix_getOwnedObjects", params1);
    defer allocator.free(response1);

    const parsed1 = try std.json.parseFromSlice(std.json.Value, allocator, response1, .{});
    defer parsed1.deinit();

    const params2 = try std.fmt.allocPrint(allocator, "[\"{s}\",null,null,1]", .{addr2});
    defer allocator.free(params2);

    const response2 = try rpc_client.call("suix_getOwnedObjects", params2);
    defer allocator.free(response2);

    const parsed2 = try std.json.parseFromSlice(std.json.Value, allocator, response2, .{});
    defer parsed2.deinit();

    var count1: u32 = 0;
    var count2: u32 = 0;

    if (parsed1.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                count1 = @intCast(data.array.items.len);
            }
        }
    }

    if (parsed2.value.object.get("result")) |result| {
        if (result.object.get("data")) |data| {
            if (data == .array) {
                count2 = @intCast(data.array.items.len);
            }
        }
    }

    std.log.info("", .{});
    std.log.info("=== Object Count Comparison ===", .{});
    std.log.info("A: {d} objects", .{count1});
    std.log.info("B: {d} objects", .{count2});

    if (count1 > count2) {
        std.log.info("A has {d} more objects than B", .{count1 - count2});
    } else if (count2 > count1) {
        std.log.info("B has {d} more objects than A", .{count2 - count1});
    } else {
        std.log.info("Both have equal object count", .{});
    }
}
