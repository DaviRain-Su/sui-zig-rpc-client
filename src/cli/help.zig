/// cli/help.zig - Help text generation
const std = @import("std");
const types = @import("types.zig");

/// Print main usage
pub fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: sui-zig-rpc-client [global-options] <command> [options]
        \\
        \\Global Options:
        \\  -h, --help              Show this help message
        \\      --version           Show version information
        \\      --rpc <url>         Set RPC endpoint (default: https://fullnode.mainnet.sui.io:443)
        \\      --timeout-ms <ms>   Request timeout in milliseconds
        \\      --confirm-timeout-ms <ms>  Confirmation timeout
        \\      --poll-ms <ms>      Poll interval for confirmation
        \\      --pretty            Pretty-print JSON output
        \\
        \\Commands:
        \\  help                    Show this help message
        \\  version                 Show version information
        \\  rpc <method> [params]   Send raw JSON-RPC request
        \\
        \\  Wallet Commands:
        \\    wallet create [options]              Create a new wallet
        \\      --alias <name>                     Set wallet alias
        \\      --no-activate                      Don't activate as default
        \\      --json                             Output as JSON
        \\    wallet import <key> [options]        Import a wallet from private key
        \\      --alias <name>                     Set wallet alias
        \\      --json                             Output as JSON
        \\    wallet use <alias> [options]         Set active wallet
        \\      --json                             Output as JSON
        \\    wallet accounts [options]            List wallet accounts
        \\      --json                             Output as JSON
        \\    wallet connect                       Connect wallet
        \\    wallet disconnect                    Disconnect wallet
        \\    wallet fund [options]                Fund wallet
        \\      --amount <amount>                  Fund amount
        \\      --dry-run                          Simulate without executing
        \\
        \\  Account Commands:
        \\    account list [options]               List accounts
        \\      --json                             Output as JSON
        \\    account info [address] [options]     Get account info
        \\      --json                             Output as JSON
        \\    account balance [address] [options]  Get account balance
        \\      --json                             Output as JSON
        \\    account coins [address] [options]    List account coins
        \\      --json                             Output as JSON
        \\    account objects [address] [options]  List account objects
        \\      --json                             Output as JSON
        \\
        \\  Transaction Commands:
        \\    tx simulate [tx-bytes] [options]     Simulate transaction
        \\      --summarize                        Summarize output
        \\    tx dry-run [tx-bytes] [options]      Dry-run transaction
        \\      --summarize                        Summarize output
        \\    tx build [options]                   Build transaction
        \\      --kind <kind>                      Transaction kind (move-call|programmable)
        \\      --package <id>                     Package ID (for move-call)
        \\      --module <name>                    Module name (for move-call)
        \\      --function <name>                  Function name (for move-call)
        \\      --sender <address>                 Transaction sender
        \\      --gas-budget <amount>              Gas budget
        \\      --summarize                        Summarize output
        \\    tx send [tx-bytes] [options]         Send transaction
        \\      --signature <sig>                  Add signature (repeatable)
        \\      --wait                             Wait for confirmation
        \\      --summarize                        Summarize output
        \\      --observe                          Observe execution
        \\    tx payload [tx-bytes] [options]      Build transaction payload
        \\      --signature <sig>                  Add signature (repeatable)
        \\
        \\  Move Commands:
        \\    move package <id> [options]          Get package info
        \\      --summarize                        Summarize output
        \\    move module <package> <module> [options]  Get module info
        \\      --summarize                        Summarize output
        \\    move function <package> <module> <function> [options]  Get function info
        \\      --output <format>                  Output format
        \\      --summarize                        Summarize output
        \\
        \\  Object Commands:
        \\    object get <id> [options]            Get object info
        \\      --show-type                        Show object type
        \\      --show-content                     Show object content
        \\    object dynamic-fields <id> [options] Get dynamic fields
        \\      --limit <n>                        Limit results
        \\
    );
}

/// Print version information
pub fn printVersion(writer: anytype) !void {
    try writer.writeAll("sui-zig-rpc-client 0.1.2\n");
}

/// Print command-specific help
pub fn printCommandHelp(writer: anytype, command: types.Command) !void {
    switch (command) {
        .help => try printUsage(writer),
        .version => try printVersion(writer),

        .wallet_create => try writer.writeAll(
            \\wallet create - Create a new wallet
            \\
            \\Usage: wallet create [options]
            \\
            \\Options:
            \\  --alias <name>      Set wallet alias
            \\  --no-activate       Don't activate as default wallet
            \\  --json              Output as JSON
            \\
        ),

        .wallet_import => try writer.writeAll(
            \\wallet import - Import wallet from private key
            \\
            \\Usage: wallet import <private-key> [options]
            \\
            \\Arguments:
            \\  <private-key>       Private key to import
            \\
            \\Options:
            \\  --alias <name>      Set wallet alias
            \\  --json              Output as JSON
            \\
        ),

        .wallet_use => try writer.writeAll(
            \\wallet use - Set active wallet
            \\
            \\Usage: wallet use <alias> [options]
            \\
            \\Arguments:
            \\  <alias>             Wallet alias or address
            \\
            \\Options:
            \\  --json              Output as JSON
            \\
        ),

        .wallet_accounts => try writer.writeAll(
            \\wallet accounts - List wallet accounts
            \\
            \\Usage: wallet accounts [options]
            \\
            \\Options:
            \\  --json              Output as JSON
            \\
        ),

        .account_list => try writer.writeAll(
            \\account list - List all accounts
            \\
            \\Usage: account list [options]
            \\
            \\Options:
            \\  --json              Output as JSON
            \\
        ),

        .account_info => try writer.writeAll(
            \\account info - Get account information
            \\
            \\Usage: account info [address] [options]
            \\
            \\Arguments:
            \\  [address]           Account address (default: active wallet)
            \\
            \\Options:
            \\  --json              Output as JSON
            \\
        ),

        .account_balance => try writer.writeAll(
            \\account balance - Get account balance
            \\
            \\Usage: account balance [address] [options]
            \\
            \\Arguments:
            \\  [address]           Account address (default: active wallet)
            \\
            \\Options:
            \\  --json              Output as JSON
            \\
        ),

        .tx_simulate => try writer.writeAll(
            \\tx simulate - Simulate transaction
            \\
            \\Usage: tx simulate [tx-bytes] [options]
            \\
            \\Arguments:
            \\  [tx-bytes]          Transaction bytes to simulate
            \\
            \\Options:
            \\  --summarize         Summarize output
            \\
        ),

        .tx_dry_run => try writer.writeAll(
            \\tx dry-run - Dry-run transaction
            \\
            \\Usage: tx dry-run [tx-bytes] [options]
            \\
            \\Arguments:
            \\  [tx-bytes]          Transaction bytes to dry-run
            \\
            \\Options:
            \\  --summarize         Summarize output
            \\
        ),

        .tx_build => try writer.writeAll(
            \\tx build - Build transaction
            \\
            \\Usage: tx build [options]
            \\
            \\Options:
            \\  --kind <kind>       Transaction kind (move-call|programmable)
            \\  --package <id>      Package ID (for move-call)
            \\  --module <name>     Module name (for move-call)
            \\  --function <name>   Function name (for move-call)
            \\  --sender <address>  Transaction sender
            \\  --gas-budget <amt>  Gas budget
            \\  --summarize         Summarize output
            \\
        ),

        .tx_send => try writer.writeAll(
            \\tx send - Send transaction
            \\
            \\Usage: tx send [tx-bytes] [options]
            \\
            \\Arguments:
            \\  [tx-bytes]          Transaction bytes to send
            \\
            \\Options:
            \\  --signature <sig>   Add signature (repeatable)
            \\  --wait              Wait for confirmation
            \\  --summarize         Summarize output
            \\  --observe           Observe execution
            \\
        ),

        .move_package => try writer.writeAll(
            \\move package - Get package information
            \\
            \\Usage: move package <package-id> [options]
            \\
            \\Arguments:
            \\  <package-id>        Package ID
            \\
            \\Options:
            \\  --summarize         Summarize output
            \\
        ),

        .move_module => try writer.writeAll(
            \\move module - Get module information
            \\
            \\Usage: move module <package-id> <module-name> [options]
            \\
            \\Arguments:
            \\  <package-id>        Package ID
            \\  <module-name>       Module name
            \\
            \\Options:
            \\  --summarize         Summarize output
            \\
        ),

        .move_function => try writer.writeAll(
            \\move function - Get function information
            \\
            \\Usage: move function <package-id> <module-name> <function-name> [options]
            \\
            \\Arguments:
            \\  <package-id>        Package ID
            \\  <module-name>       Module name
            \\  <function-name>     Function name
            \\
            \\Options:
            \\  --output <format>   Output format (commands|dry-run-request|send-request|...)
            \\  --summarize         Summarize output
            \\
        ),

        .object_get => try writer.writeAll(
            \\object get - Get object information
            \\
            \\Usage: object get <object-id> [options]
            \\
            \\Arguments:
            \\  <object-id>         Object ID
            \\
            \\Options:
            \\  --show-type         Show object type
            \\  --show-content      Show object content
            \\
        ),

        .object_dynamic_fields => try writer.writeAll(
            \\object dynamic-fields - Get object dynamic fields
            \\
            \\Usage: object dynamic-fields <object-id> [options]
            \\
            \\Arguments:
            \\  <object-id>         Object ID
            \\
            \\Options:
            \\  --limit <n>         Limit results
            \\
        ),

        .rpc => try writer.writeAll(
            \\rpc - Send raw JSON-RPC request
            \\
            \\Usage: rpc <method> [params]
            \\
            \\Arguments:
            \\  <method>            RPC method name
            \\  [params]            JSON parameters (default: [])
            \\
        ),

        else => try writer.print("No detailed help available for command: {s}\n", .{@tagName(command)}),
    }
}

/// Print help for a command category
pub fn printCategoryHelp(writer: anytype, category: types.CommandCategory) !void {
    switch (category) {
        .wallet => try writer.writeAll(
            \\Wallet Commands:
            \\  wallet create [options]              Create a new wallet
            \\  wallet import <key> [options]        Import a wallet
            \\  wallet use <alias> [options]         Set active wallet
            \\  wallet accounts [options]            List accounts
            \\  wallet connect                       Connect wallet
            \\  wallet disconnect                    Disconnect wallet
            \\  wallet fund [options]                Fund wallet
            \\
        ),

        .account => try writer.writeAll(
            \\Account Commands:
            \\  account list [options]               List accounts
            \\  account info [address] [options]     Get account info
            \\  account balance [address] [options]  Get balance
            \\  account coins [address] [options]    List coins
            \\  account objects [address] [options]  List objects
            \\
        ),

        .transaction => try writer.writeAll(
            \\Transaction Commands:
            \\  tx simulate [tx-bytes] [options]     Simulate transaction
            \\  tx dry-run [tx-bytes] [options]      Dry-run transaction
            \\  tx build [options]                   Build transaction
            \\  tx send [tx-bytes] [options]         Send transaction
            \\  tx payload [tx-bytes] [options]      Build payload
            \\
        ),

        .move => try writer.writeAll(
            \\Move Commands:
            \\  move package <id> [options]          Get package info
            \\  move module <pkg> <mod> [options]    Get module info
            \\  move function <pkg> <mod> <fn> [opt] Get function info
            \\
        ),

        .object => try writer.writeAll(
            \\Object Commands:
            \\  object get <id> [options]            Get object info
            \\  object dynamic-fields <id> [options] Get dynamic fields
            \\
        ),

        .query => try writer.writeAll(
            \\Query Commands:
            \\  events [options]                     Query events
            \\
        ),

        .request => try writer.writeAll(
            \\Request Lifecycle Commands:
            \\  request build [options]              Build request
            \\  request inspect [options]            Inspect request
            \\  request dry-run [options]            Dry-run request
            \\  request sponsor [options]            Sponsor request
            \\  request sign [options]               Sign request
            \\  request send [options]               Send request
            \\
        ),

        .utility => try writer.writeAll(
            \\Utility Commands:
            \\  help                                 Show help
            \\  version                              Show version
            \\  rpc <method> [params]                Raw RPC call
            \\
        ),
    }
}

// ============================================================
// Tests
// ============================================================

test "printUsage outputs help text" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try printUsage(output.writer());
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Usage:"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Global Options:"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Wallet Commands:"));
}

test "printVersion outputs version" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try printVersion(output.writer());
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "sui-zig-rpc-client"));
}

test "printCommandHelp for wallet_create" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try printCommandHelp(output.writer(), .wallet_create);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "wallet create"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "--alias"));
}

test "printCommandHelp for tx_build" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try printCommandHelp(output.writer(), .tx_build);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "tx build"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "--kind"));
}

test "printCommandHelp for move_function" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try printCommandHelp(output.writer(), .move_function);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "move function"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "--output"));
}

test "printCategoryHelp for wallet" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try printCategoryHelp(output.writer(), .wallet);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Wallet Commands:"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "wallet create"));
}

test "printCategoryHelp for transaction" {
    const testing = std.testing;
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    try printCategoryHelp(output.writer(), .transaction);
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "Transaction Commands:"));
    try testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "tx send"));
}
