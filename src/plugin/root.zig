// Plugin module - Extensible plugin system
// Provides API for plugins and manages plugin lifecycle

const std = @import("std");

pub const api = @import("api.zig");
pub const manager = @import("manager.zig");
pub const builtin = @import("builtin.zig");

// Re-export main types
pub const PluginInfo = api.PluginInfo;
pub const PluginInterface = api.PluginInterface;
pub const PluginCapabilities = api.PluginCapabilities;
pub const PluginManifest = api.PluginManifest;
pub const CommandDef = api.CommandDef;
pub const Context = api.Context;
pub const HostApi = api.HostApi;
pub const HookType = api.HookType;
pub const HookHandler = api.HookHandler;
pub const LogLevel = api.LogLevel;
pub const API_VERSION = api.API_VERSION;

pub const PluginManager = manager.PluginManager;
pub const PluginInstance = manager.PluginInstance;

pub const getBuiltinPlugins = builtin.getBuiltinPlugins;

/// Plugin system configuration
pub const PluginConfig = struct {
    /// Enable plugins
    enabled: bool = true,
    /// Plugins directory
    plugins_dir: []const u8 = "~/.sui/plugins",
    /// Auto-load plugins
    auto_load: bool = true,
    /// Allowed plugin sources
    allowed_sources: []const []const u8 = &.{ "builtin", "official" },
};

/// Initialize plugin system
pub fn init(allocator: std.mem.Allocator, config: PluginConfig) !PluginManager {
    const plugins_dir = try std.fs.path.join(allocator, &.{ std.process.getEnvVarOwned(allocator, "HOME") catch ".", ".sui", "plugins" });
    defer allocator.free(plugins_dir);

    var mgr = PluginManager.init(allocator, plugins_dir);

    // Load built-in plugins
    const builtins = getBuiltinPlugins();
    for (builtins) |iface| {
        const info = iface.get_info();

        // Create data directory for plugin
        const data_dir = try std.fs.path.join(allocator, &.{ plugins_dir, info.name });
        defer allocator.free(data_dir);

        const instance = try PluginInstance.init(
            allocator,
            info,
            iface,
            data_dir,
            &mgr.host_api,
        );

        // Register commands
        if (info.capabilities.commands and iface.get_commands != null) {
            const commands = iface.get_commands.?();
            for (commands) |*cmd| {
                try mgr.registerCommand(cmd);
            }
        }

        // Register hooks
        if (info.capabilities.hooks and iface.register_hooks != null) {
            const S = struct {
                mgr_ptr: *PluginManager,
                pub fn register(hook_type: HookType, handler: HookHandler) void {
                    this.mgr_ptr.registerHook(hook_type, handler) catch {};
                }
                pub var this: @This() = undefined;
            };
            S.this = .{ .mgr_ptr = &mgr };
            iface.register_hooks.?(S.register);
        }

        try mgr.plugins.append(allocator, instance);
    }

    // Activate all plugins
    if (config.auto_load) {
        mgr.activateAll();
    }

    return mgr;
}

test "Plugin system init" {
    const allocator = std.testing.allocator;
    const config = PluginConfig{
        .enabled = true,
        .auto_load = false,
    };

    var mgr = try init(allocator, config);
    defer mgr.deinit();

    // Should have built-in plugins loaded
    try std.testing.expect(mgr.listPlugins().len > 0);
}
