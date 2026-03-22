// Plugin API - Interface for plugins to interact with CLI
// Defines the contract between host and plugins

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Plugin API version
pub const API_VERSION: u32 = 1;

/// Plugin capabilities flags
pub const PluginCapabilities = packed struct {
    commands: bool = false,
    hooks: bool = false,
    rpc_intercept: bool = false,
    ui_extensions: bool = false,
    _reserved: u28 = 0,
};

/// Plugin metadata
pub const PluginInfo = struct {
    /// Plugin name
    name: []const u8,
    /// Plugin version (semver)
    version: []const u8,
    /// Plugin description
    description: []const u8,
    /// Author
    author: []const u8,
    /// API version required
    api_version: u32,
    /// Capabilities
    capabilities: PluginCapabilities,
};

/// Command definition
pub const CommandDef = struct {
    /// Command name
    name: []const u8,
    /// Command description
    description: []const u8,
    /// Usage example
    usage: []const u8,
    /// Handler function pointer
    handler: *const fn (ctx: *Context, args: []const []const u8) anyerror!void,
};

/// Hook types
pub const HookType = enum {
    /// Called before RPC request
    pre_rpc,
    /// Called after RPC response
    post_rpc,
    /// Called before transaction
    pre_transaction,
    /// Called after transaction
    post_transaction,
    /// Called on CLI startup
    startup,
    /// Called on CLI shutdown
    shutdown,
};

/// Hook handler function type
pub const HookHandler = *const fn (ctx: *Context, data: ?*anyopaque) anyerror!void;

/// Plugin context - passed to all plugin functions
pub const Context = struct {
    /// Allocator for plugin use
    allocator: Allocator,
    /// Plugin data directory
    data_dir: []const u8,
    /// Plugin configuration
    config: ?std.json.Value,
    /// Host API functions
    host: *const HostApi,
    /// Plugin-private data
    user_data: ?*anyopaque,

    /// Log message through host
    pub fn log(ctx: *const Context, level: LogLevel, message: []const u8) void {
        ctx.host.log.?(ctx, level, message);
    }

    /// Get RPC client
    pub fn getRpcClient(ctx: *const Context) ?*anyopaque {
        return ctx.host.get_rpc_client.?(ctx);
    }

    /// Execute RPC call
    pub fn rpcCall(
        ctx: *const Context,
        method: []const u8,
        params: []const u8,
    ) ![]const u8 {
        return ctx.host.rpc_call.?(ctx, method, params);
    }

    /// Get configuration value
    pub fn getConfig(ctx: *const Context, key: []const u8) ?[]const u8 {
        return ctx.host.get_config.?(ctx, key);
    }

    /// Set configuration value
    pub fn setConfig(ctx: *const Context, key: []const u8, value: []const u8) !void {
        return ctx.host.set_config.?(ctx, key, value);
    }

    /// Show notification
    pub fn notify(ctx: *const Context, title: []const u8, message: []const u8) void {
        ctx.host.notify.?(ctx, title, message);
    }
};

/// Log levels
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};

/// Host API - functions provided by CLI to plugins
pub const HostApi = struct {
    /// Log a message
    log: ?*const fn (ctx: *const Context, level: LogLevel, message: []const u8) void = null,
    /// Get RPC client instance
    get_rpc_client: ?*const fn (ctx: *const Context) ?*anyopaque = null,
    /// Execute RPC call
    rpc_call: ?*const fn (
        ctx: *const Context,
        method: []const u8,
        params: []const u8,
    ) anyerror![]const u8 = null,
    /// Get configuration
    get_config: ?*const fn (ctx: *const Context, key: []const u8) ?[]const u8 = null,
    /// Set configuration
    set_config: ?*const fn (ctx: *const Context, key: []const u8, value: []const u8) anyerror!void = null,
    /// Show notification
    notify: ?*const fn (ctx: *const Context, title: []const u8, message: []const u8) void = null,
};

/// Plugin interface - implemented by plugins
pub const PluginInterface = struct {
    /// Get plugin info
    get_info: *const fn () PluginInfo,
    /// Initialize plugin
    init: *const fn (ctx: *Context) anyerror!void,
    /// Shutdown plugin
    deinit: *const fn (ctx: *Context) void,
    /// Get commands (if capabilities.commands is true)
    get_commands: ?*const fn () []const CommandDef = null,
    /// Register hooks (if capabilities.hooks is true)
    register_hooks: ?*const fn (register: *const fn (HookType, HookHandler) void) void = null,
};

/// Plugin manifest (loaded from JSON)
pub const PluginManifest = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    entry: []const u8, // Entry point file
    capabilities: PluginCapabilities,
    dependencies: ?[][]const u8 = null,
    config_schema: ?std.json.Value = null,

    pub fn fromJson(allocator: Allocator, json: []const u8) !PluginManifest {
        var parser = std.json.Parser.init(allocator, .alloc_if_needed);
        defer parser.deinit();

        var tree = try parser.parse(json);
        defer tree.deinit();

        const root = tree.root.object;

        return .{
            .name = root.get("name").?.string,
            .version = root.get("version").?.string,
            .description = root.get("description").?.string,
            .author = root.get("author").?.string,
            .entry = root.get("entry").?.string,
            .capabilities = .{}, // Parse from JSON
            .dependencies = null,
            .config_schema = null,
        };
    }
};

// Export C-compatible functions for dynamic loading
/// Plugin must export this function
pub export fn sui_plugin_get_api_version() u32 {
    return API_VERSION;
}

/// Plugin must export this function
pub export fn sui_plugin_get_interface() *const PluginInterface {
    // This is a placeholder - actual plugins will implement this
    return undefined;
}
