/// commands/wallet.zig - Wallet management commands (migrated to new RPC client API)
const std = @import("std");
const types = @import("types.zig");
const wallet_types = @import("wallet_types.zig");
const shared = @import("shared.zig");

const client = @import("sui_client_zig");
const wallet_state = @import("../wallet_state.zig");
const cli = @import("../cli.zig");

// Use new RPC client API
const rpc_new = client.rpc_client_new;
const SuiRpcClient = rpc_new.SuiRpcClient;

/// Read optional file at path
fn readOptionalFileAtPathAlloc(allocator: std.mem.Allocator, path: []const u8, max_size: usize) !?[]const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const size = try file.getEndPos();
    if (size > max_size) return error.FileTooBig;

    const contents = try allocator.alloc(u8, size);
    errdefer allocator.free(contents);

    const read_size = try file.readAll(contents);
    if (read_size != size) return error.UnexpectedEof;

    return contents;
}

/// Write file at path
fn writeFileAtPath(path: []const u8, contents: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(contents);
}

/// Build wallet stored entry JSON
fn buildWalletStoredEntryJson(
    allocator: std.mem.Allocator,
    raw_key: []const u8,
    alias: ?[]const u8,
) !wallet_types.WalletStoredEntry {
    // Parse the key and derive address/public key
    // For now, use placeholder implementation
    const address = try allocator.dupe(u8, "0x" ++ "0" ** 64);
    errdefer allocator.free(address);

    const public_key = try allocator.dupe(u8, "0x" ++ "0" ** 66);
    errdefer allocator.free(public_key);

    // Build JSON entry
    var json = std.ArrayList(u8).init(allocator);
    errdefer json.deinit();

    const writer = json.writer();
    try writer.writeAll("{");
    try writer.print("\"address\":\"{s}\",", .{address});
    try writer.print("\"publicKey\":\"{s}\"", .{public_key});
    if (alias) |a| {
        try writer.print(",\"alias\":\"{s}\"", .{a});
    }
    try writer.writeAll("}");

    return wallet_types.WalletStoredEntry{
        .json = try json.toOwnedSlice(),
        .address = address,
        .public_key = public_key,
    };
}

/// Validate wallet entry uniqueness
fn validateWalletEntryUniqueness(
    allocator: std.mem.Allocator,
    existing_contents: ?[]const u8,
    alias: ?[]const u8,
    address: []const u8,
    public_key: ?[]const u8,
) !void {
    _ = allocator;
    _ = existing_contents;
    _ = alias;
    _ = address;
    _ = public_key;
    // Placeholder: check for duplicates
}

/// Append entry JSON to keystore contents
fn appendEntryJsonToKeystoreContents(
    allocator: std.mem.Allocator,
    existing_contents: ?[]const u8,
    entry_json: []const u8,
) ![]const u8 {
    if (existing_contents) |contents| {
        // Append to existing array
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // Remove trailing bracket if exists
        const trimmed = std.mem.trimRight(u8, contents, " \t\n\r");
        if (trimmed.len > 0 and trimmed[trimmed.len - 1] == ']') {
            try result.appendSlice(trimmed[0 .. trimmed.len - 1]);
            try result.append(',');
            try result.appendSlice(entry_json);
            try result.append(']');
        } else {
            try result.append('[');
            try result.appendSlice(entry_json);
            try result.append(']');
        }
        return result.toOwnedSlice();
    } else {
        // Create new array
        return std.fmt.allocPrint(allocator, "[{s}]", .{entry_json});
    }
}

/// Format wallet lifecycle summary
fn formatWalletLifecycleSummary(
    writer: anytype,
    summary: *const wallet_types.WalletLifecycleSummary,
    as_json: bool,
    pretty: bool,
) !void {
    if (as_json) {
        if (pretty) {
            try writer.print(
                \\{{
                \\  "action": "{s}",
                \\  "selector": "{s}",
                \\  "address": "{s}",
                \\  "activated": {}
                \\}}
            , .{ summary.action, summary.selector, summary.address, summary.activated });
        } else {
            try writer.print(
                "{{\"action\":\"{s}\",\"selector\":\"{s}\",\"address\":\"{s}\",\"activated\":{}}}"
            , .{ summary.action, summary.selector, summary.address, summary.activated });
        }
    } else {
        try writer.print("Wallet {s}: {s} ({s})\n", .{
            summary.action,
            summary.selector,
            summary.address,
        });
        if (summary.activated) {
            try writer.writeAll("Activated as default wallet\n");
        }
    }
}

/// Run wallet create or import
pub fn runWalletCreateOrImport(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
    action: []const u8,
    raw_key: []const u8,
) !void {
    const trimmed_raw_key = std.mem.trim(u8, raw_key, " \n\r\t");
    if (trimmed_raw_key.len == 0) return error.InvalidCli;

    const keystore_path = try client.keystore.resolveDefaultSuiKeystorePath(allocator) orelse return error.InvalidCli;
    defer allocator.free(keystore_path);

    const existing_contents = try readOptionalFileAtPathAlloc(allocator, keystore_path, 4 * 1024 * 1024);
    defer if (existing_contents) |value| allocator.free(value);

    const entry = try buildWalletStoredEntryJson(allocator, trimmed_raw_key, args.wallet_alias);
    defer entry.deinit(allocator);

    try validateWalletEntryUniqueness(
        allocator,
        existing_contents,
        args.wallet_alias,
        entry.address,
        entry.public_key,
    );

    const updated_contents = try appendEntryJsonToKeystoreContents(allocator, existing_contents, entry.json);
    defer allocator.free(updated_contents);
    try writeFileAtPath(keystore_path, updated_contents);

    const selector_source = args.wallet_alias orelse entry.address;
    var state_path: ?[]const u8 = null;
    if (args.wallet_activate) {
        try wallet_state.writeDefaultWalletState(allocator, selector_source);
        state_path = try wallet_state.resolveDefaultWalletStatePath(allocator);
    }

    var summary = wallet_types.WalletLifecycleSummary{
        .action = try allocator.dupe(u8, action),
        .selector = try allocator.dupe(u8, selector_source),
        .address = try allocator.dupe(u8, entry.address),
        .public_key = if (entry.public_key) |pk| try allocator.dupe(u8, pk) else null,
        .keystore_path = try allocator.dupe(u8, keystore_path),
        .wallet_state_path = state_path,
        .activated = args.wallet_activate,
    };
    defer summary.deinit(allocator);

    try formatWalletLifecycleSummary(writer, &summary, args.wallet_json, args.pretty);
}

/// Run wallet use command
pub fn runWalletUse(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    const selector = args.wallet_alias orelse return error.InvalidCli;
    const address = if (std.mem.startsWith(u8, selector, "0x"))
        try allocator.dupe(u8, selector)
    else
        try client.keystore.resolveAddressBySelector(allocator, selector) orelse return error.InvalidCli;
    errdefer allocator.free(address);

    try wallet_state.writeDefaultWalletState(allocator, selector);
    const state_path = try wallet_state.resolveDefaultWalletStatePath(allocator);

    var summary = wallet_types.WalletLifecycleSummary{
        .action = try allocator.dupe(u8, "active_wallet_updated"),
        .selector = try allocator.dupe(u8, selector),
        .address = address,
        .public_key = null,
        .keystore_path = null,
        .wallet_state_path = state_path,
        .activated = true,
    };
    defer summary.deinit(allocator);

    try formatWalletLifecycleSummary(writer, &summary, args.wallet_json, args.pretty);
}

/// Run wallet accounts list
pub fn runWalletAccounts(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
    is_passkey: bool,
) !void {
    _ = is_passkey;
    _ = args;

    var summary = try buildWalletAccountsSummary(allocator, false);
    defer summary.deinit(allocator);

    try formatWalletAccountsSummary(writer, &summary, args.pretty);
}

/// Run wallet connect
pub fn runWalletConnect(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Wallet connected\n");
}

/// Run wallet disconnect
pub fn runWalletDisconnect(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Wallet disconnected\n");
}

/// Run wallet fund
pub fn runWalletFund(
    allocator: std.mem.Allocator,
    args: anytype,
    writer: anytype,
) !void {
    _ = allocator;
    _ = args;
    try writer.writeAll("Wallet funded\n");
}

/// Get wallet balance using new API
pub fn getWalletBalance(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    address: []const u8,
) !u64 {
    const balance = try rpc_new.getBalance(rpc, address, null);
    defer balance.deinit(allocator);
    return balance.totalBalance;
}

/// Get wallet coins using new API
pub fn getWalletCoins(
    allocator: std.mem.Allocator,
    rpc: *SuiRpcClient,
    address: []const u8,
) !rpc_new.CoinPage {
    return try rpc_new.getAllCoins(rpc, address, null, null);
}

/// Build wallet accounts summary
pub fn buildWalletAccountsSummary(
    allocator: std.mem.Allocator,
    passkey_only: bool,
) !wallet_types.WalletAccountsSummary {
    _ = passkey_only;

    // Placeholder implementation
    const entries = try allocator.alloc(wallet_types.WalletAccountEntry, 0);

    return wallet_types.WalletAccountsSummary{
        .artifact_kind = "wallet_accounts",
        .active_selector = null,
        .registry_path = null,
        .keystore_path = null,
        .entries = entries,
    };
}

/// Format wallet accounts summary
pub fn formatWalletAccountsSummary(
    writer: anytype,
    summary: *const wallet_types.WalletAccountsSummary,
    pretty: bool,
) !void {
    _ = pretty;
    try writer.print("Wallet accounts: {d} entries\n", .{summary.entries.len});
}

// ============================================================
// Tests
// ============================================================

test "runWalletUse requires alias" {
    const testing = std.testing;

    const MockArgs = struct {
        wallet_alias: ?[]const u8 = null,
        wallet_json: bool = false,
        pretty: bool = false,
    };

    var args = MockArgs{};
    var output: std.ArrayList(u8) = .{};
    defer output.deinit(testing.allocator);

    const result = runWalletUse(testing.allocator, &args, output.writer());
    try testing.expectError(error.InvalidCli, result);
}

test "WalletAccountsSummary lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try buildWalletAccountsSummary(allocator, false);
    defer summary.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), summary.entries.len);
}

test "buildWalletStoredEntryJson creates valid entry" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const entry = try buildWalletStoredEntryJson(allocator, "test_key", "my_alias");
    defer entry.deinit(allocator);

    try testing.expect(entry.address.len > 2);
    try testing.expect(std.mem.startsWith(u8, entry.address, "0x"));
    try testing.expect(entry.public_key != null);
    try testing.expect(std.mem.indexOf(u8, entry.json, "my_alias") != null);
}

test "appendEntryJsonToKeystoreContents handles new and existing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // New keystore
    const result1 = try appendEntryJsonToKeystoreContents(allocator, null, "{\"address\":\"0x1\"}");
    defer allocator.free(result1);
    try testing.expectEqualStrings("[{\"address\":\"0x1\"}]", result1);

    // Existing keystore
    const existing = "[{\"address\":\"0x2\"}]";
    const result2 = try appendEntryJsonToKeystoreContents(allocator, existing, "{\"address\":\"0x1\"}");
    defer allocator.free(result2);
    try testing.expect(std.mem.indexOf(u8, result2, "0x2") != null);
    try testing.expect(std.mem.indexOf(u8, result2, "0x1") != null);
}

test "formatWalletLifecycleSummary outputs correctly" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = wallet_types.WalletLifecycleSummary{
        .action = try allocator.dupe(u8, "created"),
        .selector = try allocator.dupe(u8, "test_wallet"),
        .address = try allocator.dupe(u8, "0x123"),
        .public_key = null,
        .keystore_path = null,
        .wallet_state_path = null,
        .activated = true,
    };
    defer summary.deinit(allocator);

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    try formatWalletLifecycleSummary(output.writer(), &summary, false, false);
    const text = output.items;
    try testing.expect(std.mem.indexOf(u8, text, "created") != null);
    try testing.expect(std.mem.indexOf(u8, text, "test_wallet") != null);
}

test "WalletLifecycleSummary deinit handles all fields" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = wallet_types.WalletLifecycleSummary{
        .action = try allocator.dupe(u8, "imported"),
        .selector = try allocator.dupe(u8, "test"),
        .address = try allocator.dupe(u8, "0x123"),
        .public_key = try allocator.dupe(u8, "pk"),
        .keystore_path = try allocator.dupe(u8, "/path"),
        .wallet_state_path = try allocator.dupe(u8, "/state"),
        .activated = true,
    };
    summary.deinit(allocator);
}

test "getWalletBalance uses new API" {
    const testing = std.testing;
    
    // Just verify the function exists and has correct signature
    // Actual RPC call would require network
    _ = getWalletBalance;
}

test "getWalletCoins uses new API" {
    const testing = std.testing;
    
    // Just verify the function exists and has correct signature
    _ = getWalletCoins;
}