/// Caching RPC Client for Sui
/// Wraps SuiRpcClient with intelligent caching to reduce network calls
const std = @import("std");
const Allocator = std.mem.Allocator;
const SuiRpcClient = @import("client_core.zig").SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

// ============================================================================
// Generic Cache Implementation
// ============================================================================

/// Cache entry with TTL
pub fn CacheEntry(T: type) type {
    return struct {
        data: T,
        timestamp: i64,
        ttl_ms: i64,

        const Self = @This();

        pub fn isExpired(self: Self) bool {
            const now = std.time.milliTimestamp();
            return now - self.timestamp > self.ttl_ms;
        }
    };
}

/// Generic cache with TTL support
pub fn Cache(comptime K: type, comptime V: type) type {
    return struct {
        allocator: Allocator,
        map: std.HashMap(K, CacheEntry(V), getContext(K), std.hash_map.default_max_load_percentage),
        default_ttl_ms: i64,
        max_entries: usize,

        const Self = @This();

        pub fn init(allocator: Allocator, default_ttl_ms: i64, max_entries: usize) Self {
            return .{
                .allocator = allocator,
                .map = std.HashMap(K, CacheEntry(V), getContext(K), std.hash_map.default_max_load_percentage).init(allocator),
                .default_ttl_ms = default_ttl_ms,
                .max_entries = max_entries,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        /// Get value from cache
        pub fn get(self: *Self, key: K) ?V {
            const entry = self.map.get(key) orelse return null;

            if (entry.isExpired()) {
                _ = self.map.remove(key);
                return null;
            }

            return entry.data;
        }

        /// Put value into cache
        pub fn put(self: *Self, key: K, value: V) !void {
            if (self.map.count() >= self.max_entries) {
                try self.evictOldest();
            }

            const entry = CacheEntry(V){
                .data = value,
                .timestamp = std.time.milliTimestamp(),
                .ttl_ms = self.default_ttl_ms,
            };

            try self.map.put(key, entry);
        }

        /// Remove entry from cache
        pub fn remove(self: *Self, key: K) void {
            _ = self.map.remove(key);
        }

        /// Clear all entries
        pub fn clear(self: *Self) void {
            self.map.clearRetainingCapacity();
        }

        /// Get cache stats
        pub fn stats(self: *Self) struct { entries: usize, capacity: usize } {
            return .{
                .entries = self.map.count(),
                .capacity = self.max_entries,
            };
        }

        /// Evict oldest entries
        fn evictOldest(self: *Self) !void {
            var oldest_key: ?K = null;
            var oldest_time: i64 = std.math.maxInt(i64);

            var iter = self.map.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.timestamp < oldest_time) {
                    oldest_time = entry.value_ptr.timestamp;
                    oldest_key = entry.key_ptr.*;
                }
            }

            if (oldest_key) |key| {
                _ = self.map.remove(key);
            }
        }
    };
}

/// Get hash context for a type
fn getContext(comptime K: type) type {
    return struct {
        pub fn hash(_: @This(), k: K) u64 {
            return std.hash_map.getAutoHashFn(K, @This())(.{}, k);
        }

        pub fn eql(_: @This(), a: K, b: K) bool {
            return std.hash_map.getAutoEqlFn(K, @This())(.{}, a, b);
        }
    };
}

// ============================================================================
// Caching RPC Client
// ============================================================================

/// Cached RPC Client
pub const CachingSuiRpcClient = struct {
    allocator: Allocator,
    inner: *SuiRpcClient,

    // Caches with different TTLs
    object_cache: Cache([]const u8, []const u8),
    balance_cache: Cache([]const u8, []const u8),
    owned_objects_cache: Cache([]const u8, []const u8),
    transaction_cache: Cache([]const u8, []const u8),
    gas_price_cache: Cache([]const u8, u64),

    // Cache statistics
    hits: u64,
    misses: u64,

    const Self = @This();

    // TTL configurations (milliseconds)
    const OBJECT_TTL = 30_000; // 30 seconds
    const BALANCE_TTL = 10_000; // 10 seconds
    const OWNED_OBJECTS_TTL = 15_000; // 15 seconds
    const TRANSACTION_TTL = 300_000; // 5 minutes
    const GAS_PRICE_TTL = 60_000; // 1 minute

    const MAX_CACHE_ENTRIES = 1000;

    pub fn init(allocator: Allocator, inner: *SuiRpcClient) Self {
        return .{
            .allocator = allocator,
            .inner = inner,
            .object_cache = Cache([]const u8, []const u8).init(allocator, OBJECT_TTL, MAX_CACHE_ENTRIES),
            .balance_cache = Cache([]const u8, []const u8).init(allocator, BALANCE_TTL, MAX_CACHE_ENTRIES),
            .owned_objects_cache = Cache([]const u8, []const u8).init(allocator, OWNED_OBJECTS_TTL, MAX_CACHE_ENTRIES),
            .transaction_cache = Cache([]const u8, []const u8).init(allocator, TRANSACTION_TTL, MAX_CACHE_ENTRIES),
            .gas_price_cache = Cache([]const u8, u64).init(allocator, GAS_PRICE_TTL, MAX_CACHE_ENTRIES),
            .hits = 0,
            .misses = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all cached strings
        var obj_iter = self.object_cache.map.iterator();
        while (obj_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }

        var bal_iter = self.balance_cache.map.iterator();
        while (bal_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }

        var owned_iter = self.owned_objects_cache.map.iterator();
        while (owned_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }

        var tx_iter = self.transaction_cache.map.iterator();
        while (tx_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }

        var gas_iter = self.gas_price_cache.map.iterator();
        while (gas_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.object_cache.deinit();
        self.balance_cache.deinit();
        self.owned_objects_cache.deinit();
        self.transaction_cache.deinit();
        self.gas_price_cache.deinit();
    }

    /// Get object with caching
    pub fn getObject(self: *Self, object_id: []const u8) ![]const u8 {
        // Check cache first
        if (self.object_cache.get(object_id)) |cached| {
            self.hits += 1;
            return self.allocator.dupe(u8, cached);
        }

        self.misses += 1;

        // Fetch from network
        const response = try self.inner.call("sui_getObject", try std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{object_id}));
        defer self.allocator.free(response);

        // Parse and cache
        const result = try self.allocator.dupe(u8, response);

        const key = try self.allocator.dupe(u8, object_id);
        self.object_cache.put(key, result) catch {
            self.allocator.free(key);
            // Don't fail if caching fails, just return the result
        };

        return try self.allocator.dupe(u8, response);
    }

    /// Get balance with caching
    pub fn getBalance(self: *Self, address: []const u8, coin_type: ?[]const u8) !u64 {
        const cache_key = if (coin_type) |ct|
            try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ address, ct })
        else
            try self.allocator.dupe(u8, address);
        defer self.allocator.free(cache_key);

        // Check cache
        if (self.balance_cache.get(cache_key)) |cached| {
            self.hits += 1;
            const parsed = try std.json.parseFromSlice(u64, self.allocator, cached, .{});
            defer parsed.deinit();
            return parsed.value;
        }

        self.misses += 1;

        // Fetch from network (using query module)
        const query = @import("query.zig");
        const balance = try query.getBalance(self.inner, address, coin_type);

        // Cache result
        const balance_json = try std.fmt.allocPrint(self.allocator, "{d}", .{balance});
        defer self.allocator.free(balance_json);

        const key = try self.allocator.dupe(u8, cache_key);
        const value = try self.allocator.dupe(u8, balance_json);
        self.balance_cache.put(key, value) catch {
            self.allocator.free(key);
            self.allocator.free(value);
        };

        return balance;
    }

    /// Get owned objects with caching
    pub fn getOwnedObjects(self: *Self, address: []const u8) ![]const u8 {
        // Check cache
        if (self.owned_objects_cache.get(address)) |cached| {
            self.hits += 1;
            return self.allocator.dupe(u8, cached);
        }

        self.misses += 1;

        // Fetch from network
        const response = try self.inner.call("suix_getOwnedObjects", try std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{address}));
        defer self.allocator.free(response);

        // Cache result
        const result = try self.allocator.dupe(u8, response);

        const key = try self.allocator.dupe(u8, address);
        self.owned_objects_cache.put(key, result) catch {
            self.allocator.free(key);
        };

        return try self.allocator.dupe(u8, response);
    }

    /// Get transaction with caching
    pub fn getTransaction(self: *Self, digest: []const u8) ![]const u8 {
        // Check cache
        if (self.transaction_cache.get(digest)) |cached| {
            self.hits += 1;
            return self.allocator.dupe(u8, cached);
        }

        self.misses += 1;

        // Fetch from network
        const response = try self.inner.call("sui_getTransactionBlock", try std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{digest}));
        defer self.allocator.free(response);

        // Cache result
        const result = try self.allocator.dupe(u8, response);

        const key = try self.allocator.dupe(u8, digest);
        self.transaction_cache.put(key, result) catch {
            self.allocator.free(key);
        };

        return try self.allocator.dupe(u8, response);
    }

    /// Get reference gas price with caching
    pub fn getReferenceGasPrice(self: *Self) !u64 {
        const cache_key = "gas_price";

        // Check cache
        if (self.gas_price_cache.get(cache_key)) |cached| {
            self.hits += 1;
            return cached;
        }

        self.misses += 1;

        // Fetch from network
        const query = @import("query.zig");
        const price = try query.getReferenceGasPrice(self.inner);

        // Cache result
        const key = try self.allocator.dupe(u8, cache_key);
        self.gas_price_cache.put(key, price) catch {
            self.allocator.free(key);
        };

        return price;
    }

    /// Clear all caches
    pub fn clearCache(self: *Self) void {
        self.object_cache.clear();
        self.balance_cache.clear();
        self.owned_objects_cache.clear();
        self.transaction_cache.clear();
        self.gas_price_cache.clear();
        self.hits = 0;
        self.misses = 0;
    }

    /// Get cache statistics
    pub fn getStats(self: *const Self) struct {
        hits: u64,
        misses: u64,
        hit_rate: f64,
        object_cache_size: usize,
        balance_cache_size: usize,
        owned_objects_cache_size: usize,
        transaction_cache_size: usize,
        gas_price_cache_size: usize,
    } {
        const total = self.hits + self.misses;
        const hit_rate = if (total > 0)
            @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total)) * 100.0
        else
            0.0;

        return .{
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = hit_rate,
            .object_cache_size = self.object_cache.map.count(),
            .balance_cache_size = self.balance_cache.map.count(),
            .owned_objects_cache_size = self.owned_objects_cache.map.count(),
            .transaction_cache_size = self.transaction_cache.map.count(),
            .gas_price_cache_size = self.gas_price_cache.map.count(),
        };
    }

    /// Print cache statistics
    pub fn printStats(self: *const Self) void {
        const stats = self.getStats();

        std.log.info("═══════════════════════════════════════════════════════════════", .{});
        std.log.info("                    Cache Statistics", .{});
        std.log.info("═══════════════════════════════════════════════════════════════", .{});
        std.log.info("  Cache Hits:   {d}", .{stats.hits});
        std.log.info("  Cache Misses: {d}", .{stats.misses});
        std.log.info("  Hit Rate:     {d:.1}%", .{stats.hit_rate});
        std.log.info("", .{});
        std.log.info("  Object Cache:       {d} entries", .{stats.object_cache_size});
        std.log.info("  Balance Cache:      {d} entries", .{stats.balance_cache_size});
        std.log.info("  Owned Objects:      {d} entries", .{stats.owned_objects_cache_size});
        std.log.info("  Transaction Cache:  {d} entries", .{stats.transaction_cache_size});
        std.log.info("  Gas Price Cache:    {d} entries", .{stats.gas_price_cache_size});
        std.log.info("═══════════════════════════════════════════════════════════════", .{});
    }
};

// Test functions
test "CachingSuiRpcClient init/deinit" {
    const allocator = std.testing.allocator;

    // Create a mock inner client (would be real in production)
    var inner_client = SuiRpcClient.init(allocator, "https://testnet.sui.io");
    defer inner_client.deinit();

    var caching_client = CachingSuiRpcClient.init(allocator, &inner_client);
    defer caching_client.deinit();

    const stats = caching_client.getStats();
    try std.testing.expectEqual(stats.hits, 0);
    try std.testing.expectEqual(stats.misses, 0);
}

test "Cache statistics calculation" {
    const allocator = std.testing.allocator;

    var inner_client = SuiRpcClient.init(allocator, "https://testnet.sui.io");
    defer inner_client.deinit();

    var client = CachingSuiRpcClient.init(allocator, &inner_client);
    defer client.deinit();

    client.hits = 75;
    client.misses = 25;

    const stats = client.getStats();
    try std.testing.expectEqual(stats.hits, 75);
    try std.testing.expectEqual(stats.misses, 25);
    try std.testing.expect(stats.hit_rate >= 74.9 and stats.hit_rate <= 75.1);
}
