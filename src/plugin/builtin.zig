// Built-in plugins - Example implementations
// These are compiled into the CLI, not dynamically loaded

const std = @import("std");
const api = @import("api.zig");

const Context = api.Context;
const CommandDef = api.CommandDef;
const PluginInfo = api.PluginInfo;
const PluginInterface = api.PluginInterface;
const PluginCapabilities = api.PluginCapabilities;

/// Example: Stats plugin - provides statistics commands
pub const StatsPlugin = struct {
    pub fn getInfo() PluginInfo {
        return .{
            .name = "stats",
            .version = "1.0.0",
            .description = "Statistics and analytics commands",
            .author = "Sui Zig CLI",
            .api_version = api.API_VERSION,
            .capabilities = .{ .commands = true },
        };
    }

    pub fn init(ctx: *Context) !void {
        ctx.log(.info, "Stats plugin initialized");
    }

    pub fn deinit(ctx: *Context) void {
        ctx.log(.info, "Stats plugin shutdown");
    }

    pub fn getCommands() []const CommandDef {
        return &.{
            .{
                .name = "stats.gas",
                .description = "Show gas usage statistics",
                .usage = "stats.gas [address]",
                .handler = cmdGasStats,
            },
            .{
                .name = "stats.activity",
                .description = "Show activity statistics",
                .usage = "stats.activity [address]",
                .handler = cmdActivityStats,
            },
            .{
                .name = "stats.portfolio",
                .description = "Show portfolio summary",
                .usage = "stats.portfolio [address]",
                .handler = cmdPortfolioStats,
            },
        };
    }

    fn cmdGasStats(ctx: *Context, args: []const []const u8) !void {
        _ = args;
        ctx.log(.info, "Gas statistics:");
        ctx.log(.info, "  Total transactions: 0");
        ctx.log(.info, "  Total gas used: 0 MIST");
        ctx.log(.info, "  Average gas per tx: 0 MIST");
    }

    fn cmdActivityStats(ctx: *Context, args: []const []const u8) !void {
        _ = args;
        ctx.log(.info, "Activity statistics:");
        ctx.log(.info, "  Daily transactions: 0");
        ctx.log(.info, "  Weekly transactions: 0");
        ctx.log(.info, "  Monthly transactions: 0");
    }

    fn cmdPortfolioStats(ctx: *Context, args: []const []const u8) !void {
        _ = args;
        ctx.log(.info, "Portfolio summary:");
        ctx.log(.info, "  Total value: 0 SUI");
        ctx.log(.info, "  Number of coins: 0");
        ctx.log(.info, "  Number of NFTs: 0");
    }

    pub fn getInterface() PluginInterface {
        return .{
            .get_info = getInfo,
            .init = init,
            .deinit = deinit,
            .get_commands = getCommands,
        };
    }
};

/// Example: Alert plugin - provides notification hooks
pub const AlertPlugin = struct {
    pub fn getInfo() PluginInfo {
        return .{
            .name = "alert",
            .version = "1.0.0",
            .description = "Alert and notification system",
            .author = "Sui Zig CLI",
            .api_version = api.API_VERSION,
            .capabilities = .{ .hooks = true },
        };
    }

    pub fn init(ctx: *Context) !void {
        ctx.log(.info, "Alert plugin initialized");
    }

    pub fn deinit(ctx: *Context) void {
        ctx.log(.info, "Alert plugin shutdown");
    }

    pub fn registerHooks(register: *const fn (api.HookType, api.HookHandler) void) void {
        register(.post_transaction, onTransaction);
        register(.post_rpc, onRpcResponse);
    }

    fn onTransaction(ctx: *Context, data: ?*anyopaque) !void {
        _ = data;
        ctx.notify("Transaction Complete", "Your transaction has been executed");
    }

    fn onRpcResponse(_ctx: *Context, _data: ?*anyopaque) !void {
        _ = _ctx;
        _ = _data;
        // Check for errors and alert if needed
    }

    pub fn getInterface() PluginInterface {
        return .{
            .get_info = getInfo,
            .init = init,
            .deinit = deinit,
            .register_hooks = registerHooks,
        };
    }
};

/// Example: Export plugin - provides data export commands
pub const ExportPlugin = struct {
    pub fn getInfo() PluginInfo {
        return .{
            .name = "export",
            .version = "1.0.0",
            .description = "Export data to various formats",
            .author = "Sui Zig CLI",
            .api_version = api.API_VERSION,
            .capabilities = .{ .commands = true },
        };
    }

    pub fn init(ctx: *Context) !void {
        ctx.log(.info, "Export plugin initialized");
    }

    pub fn deinit(ctx: *Context) void {
        ctx.log(.info, "Export plugin shutdown");
    }

    pub fn getCommands() []const CommandDef {
        return &.{
            .{
                .name = "export.csv",
                .description = "Export transactions to CSV",
                .usage = "export.csv <address> <file>",
                .handler = cmdExportCsv,
            },
            .{
                .name = "export.json",
                .description = "Export data to JSON",
                .usage = "export.json <address> <file>",
                .handler = cmdExportJson,
            },
        };
    }

    fn cmdExportCsv(ctx: *Context, args: []const []const u8) !void {
        if (args.len < 2) {
            ctx.log(.err, "Usage: export.csv <address> <file>");
            return;
        }
        ctx.log(.info, "Exporting to CSV...");
        ctx.log(.info, args[0]); // Use args to avoid unused error
        ctx.log(.info, args[1]);
    }

    fn cmdExportJson(ctx: *Context, args: []const []const u8) !void {
        if (args.len < 2) {
            ctx.log(.err, "Usage: export.json <address> <file>");
            return;
        }
        ctx.log(.info, "Exporting to JSON...");
        ctx.log(.info, args[0]); // Use args to avoid unused error
        ctx.log(.info, args[1]);
    }

    pub fn getInterface() PluginInterface {
        return .{
            .get_info = getInfo,
            .init = init,
            .deinit = deinit,
            .get_commands = getCommands,
        };
    }
};

/// Get all built-in plugins
pub fn getBuiltinPlugins() []const PluginInterface {
    return &.{
        StatsPlugin.getInterface(),
        AlertPlugin.getInterface(),
        ExportPlugin.getInterface(),
    };
}
