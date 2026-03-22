// Plugin Manager - Load and manage plugins
// Handles plugin lifecycle and registration

const std = @import("std");
const Allocator = std.mem.Allocator;
const api = @import("api.zig");

const PluginInfo = api.PluginInfo;
const PluginInterface = api.PluginInterface;
const PluginCapabilities = api.PluginCapabilities;
const CommandDef = api.CommandDef;
const Context = api.Context;
const HookType = api.HookType;
const HookHandler = api.HookHandler;

/// Loaded plugin instance
pub const PluginInstance = struct {
    info: PluginInfo,
    interface: PluginInterface,
    context: Context,
    commands: []const CommandDef,
    hooks: std.ArrayListUnmanaged(HookRegistration),
    active: bool,

    const HookRegistration = struct {
        hook_type: HookType,
        handler: HookHandler,
    };

    pub fn init(
        allocator: Allocator,
        info: PluginInfo,
        iface: PluginInterface,
        data_dir: []const u8,
        host_api: *const api.HostApi,
    ) !PluginInstance {
        var instance = PluginInstance{
            .info = info,
            .interface = iface,
            .context = .{
                .allocator = allocator,
                .data_dir = data_dir,
                .config = null,
                .host = host_api,
                .user_data = null,
            },
            .commands = &.{},
            .hooks = .{},
            .active = false,
        };

        // Get commands if supported
        if (info.capabilities.commands and iface.get_commands != null) {
            instance.commands = iface.get_commands.?();
        }

        return instance;
    }

    pub fn deinit(self: *PluginInstance) void {
        if (self.active) {
            self.interface.deinit(&self.context);
        }
        self.hooks.deinit(self.context.allocator);
    }

    pub fn activate(self: *PluginInstance) !void {
        if (self.active) return;
        try self.interface.init(&self.context);
        self.active = true;
    }

    pub fn deactivate(self: *PluginInstance) void {
        if (!self.active) return;
        self.interface.deinit(&self.context);
        self.active = false;
    }
};

/// Plugin manager
pub const PluginManager = struct {
    allocator: Allocator,
    plugins_dir: []const u8,
    plugins: std.ArrayListUnmanaged(PluginInstance),
    host_api: api.HostApi,
    command_map: std.StringHashMapUnmanaged(*const CommandDef),
    hook_registry: HookRegistry,

    const HookRegistry = struct {
        pre_rpc: std.ArrayListUnmanaged(HookHandler),
        post_rpc: std.ArrayListUnmanaged(HookHandler),
        pre_transaction: std.ArrayListUnmanaged(HookHandler),
        post_transaction: std.ArrayListUnmanaged(HookHandler),
        startup: std.ArrayListUnmanaged(HookHandler),
        shutdown: std.ArrayListUnmanaged(HookHandler),

        fn init(_allocator: Allocator) HookRegistry {
            _ = _allocator;
            return .{
                .pre_rpc = .{},
                .post_rpc = .{},
                .pre_transaction = .{},
                .post_transaction = .{},
                .startup = .{},
                .shutdown = .{},
            };
        }

        fn deinit(self: *HookRegistry, allocator: Allocator) void {
            self.pre_rpc.deinit(allocator);
            self.post_rpc.deinit(allocator);
            self.pre_transaction.deinit(allocator);
            self.post_transaction.deinit(allocator);
            self.startup.deinit(allocator);
            self.shutdown.deinit(allocator);
        }

        fn register(self: *HookRegistry, hook_type: HookType, handler: HookHandler, allocator: Allocator) !void {
            switch (hook_type) {
                .pre_rpc => try self.pre_rpc.append(allocator, handler),
                .post_rpc => try self.post_rpc.append(allocator, handler),
                .pre_transaction => try self.pre_transaction.append(allocator, handler),
                .post_transaction => try self.post_transaction.append(allocator, handler),
                .startup => try self.startup.append(allocator, handler),
                .shutdown => try self.shutdown.append(allocator, handler),
            }
        }

        pub fn getHooks(self: *const HookRegistry, hook_type: HookType) []const HookHandler {
            switch (hook_type) {
                .pre_rpc => return self.pre_rpc.items,
                .post_rpc => return self.post_rpc.items,
                .pre_transaction => return self.pre_transaction.items,
                .post_transaction => return self.post_transaction.items,
                .startup => return self.startup.items,
                .shutdown => return self.shutdown.items,
            }
        }
    };

    pub fn init(allocator: Allocator, plugins_dir: []const u8) PluginManager {
        return .{
            .allocator = allocator,
            .plugins_dir = plugins_dir,
            .plugins = .{},
            .host_api = .{},
            .command_map = .{},
            .hook_registry = HookRegistry.init(allocator),
        };
    }

    pub fn deinit(self: *PluginManager) void {
        for (self.plugins.items) |*plugin| {
            plugin.deinit();
        }
        self.plugins.deinit(self.allocator);
        self.command_map.deinit(self.allocator);
        self.hook_registry.deinit(self.allocator);
    }

    /// Set host API
    pub fn setHostApi(self: *PluginManager, host_api: api.HostApi) void {
        self.host_api = host_api;
    }

    /// Load all plugins from directory
    pub fn loadAll(self: *PluginManager) !void {
        const dir = std.fs.cwd().openDir(self.plugins_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                // Plugins directory doesn't exist, create it
                try std.fs.cwd().makePath(self.plugins_dir);
                return;
            }
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                const plugin_path = try std.fs.path.join(self.allocator, &.{ self.plugins_dir, entry.name });
                defer self.allocator.free(plugin_path);

                self.loadPlugin(plugin_path) catch |err| {
                    std.log.warn("Failed to load plugin {s}: {s}", .{ entry.name, @errorName(err) });
                    continue;
                };
            }
        }
    }

    /// Load single plugin from path
    ///
    /// NOTE: Dynamic plugin loading is not yet implemented. The plugin system
    /// currently only supports built-in plugins. Full dynamic loading would require:
    ///
    /// 1. Dynamic library loading (dlopen/LoadLibrary)
    /// 2. Plugin manifest parsing (JSON/TOML)
    /// 3. Symbol resolution for plugin interface
    /// 4. Version compatibility checking
    /// 5. Sandboxing/isolation for security
    ///
    /// Current workaround: Built-in plugins in src/plugin/builtin.zig
    /// Future: Dynamic loading from ~/.sui/plugins/
    pub fn loadPlugin(self: *PluginManager, _path: []const u8) !void {
        _ = self;
        _ = _path;

        // TODO: Implement dynamic plugin loading
        // This requires:
        // - Cross-platform dynamic library loading
        // - Plugin API stability guarantees
        // - Security sandboxing
        // - Hot-reload support
        //
        // For now, use built-in plugins:
        // src/plugin/builtin.zig

        return error.NotImplemented;
    }

    /// Register a command from plugin
    pub fn registerCommand(self: *PluginManager, cmd: *const CommandDef) !void {
        try self.command_map.put(self.allocator, cmd.name, cmd);
    }

    /// Execute a plugin command
    pub fn executeCommand(
        self: *PluginManager,
        name: []const u8,
        args: []const []const u8,
    ) !void {
        const cmd = self.command_map.get(name) orelse {
            return error.CommandNotFound;
        };

        // Find plugin that owns this command
        for (self.plugins.items) |*plugin| {
            for (plugin.commands) |*plugin_cmd| {
                if (std.mem.eql(u8, plugin_cmd.name, name)) {
                    try cmd.handler(&plugin.context, args);
                    return;
                }
            }
        }

        return error.PluginNotFound;
    }

    /// Register a hook
    pub fn registerHook(self: *PluginManager, hook_type: HookType, handler: HookHandler) !void {
        try self.hook_registry.register(hook_type, handler, self.allocator);
    }

    /// Execute hooks of a specific type
    pub fn executeHooks(self: *PluginManager, hook_type: HookType, data: ?*anyopaque) void {
        const hooks = self.hook_registry.getHooks(hook_type);
        for (hooks) |handler| {
            // In a real implementation, we'd need the plugin context
            // For now, skip execution
            _ = handler;
            _ = data;
        }
    }

    /// Get list of loaded plugins
    pub fn listPlugins(self: *const PluginManager) []const PluginInstance {
        return self.plugins.items;
    }

    /// Get plugin by name
    pub fn getPlugin(self: *const PluginManager, name: []const u8) ?*PluginInstance {
        for (self.plugins.items) |*plugin| {
            if (std.mem.eql(u8, plugin.info.name, name)) {
                return plugin;
            }
        }
        return null;
    }

    /// Activate all plugins
    pub fn activateAll(self: *PluginManager) void {
        for (self.plugins.items) |*plugin| {
            plugin.activate() catch |err| {
                std.log.warn("Failed to activate plugin {s}: {s}", .{ plugin.info.name, @errorName(err) });
                continue;
            };
        }
    }

    /// Deactivate all plugins
    pub fn deactivateAll(self: *PluginManager) void {
        for (self.plugins.items) |*plugin| {
            plugin.deactivate();
        }
    }
};

// Tests
test "PluginManager lifecycle" {
    const allocator = std.testing.allocator;
    var manager = PluginManager.init(allocator, "/tmp/test_plugins");
    defer manager.deinit();

    try std.testing.expectEqual(manager.listPlugins().len, 0);
}

test "HookRegistry" {
    const allocator = std.testing.allocator;
    const HookReg = @import("manager.zig").HookRegistry;
    var registry = HookReg.init(allocator);
    defer registry.deinit(allocator);

    const dummy_handler: api.HookHandler = struct {
        fn handler(ctx: *api.Context, data: ?*anyopaque) !void {
            _ = ctx;
            _ = data;
        }
    }.handler;

    try registry.register(.startup, dummy_handler, allocator);
    try std.testing.expectEqual(registry.getHooks(.startup).len, 1);
}
