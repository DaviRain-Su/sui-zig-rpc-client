// GraphQL module for Sui
// Advanced querying with field selection

const std = @import("std");

pub const client = @import("client.zig");

// Re-export main types
pub const GraphqlConfig = client.GraphqlConfig;
pub const QueryBuilder = client.QueryBuilder;
pub const PrebuiltQueries = client.PrebuiltQueries;
pub const ResponseParser = client.ResponseParser;
pub const executeQuery = client.executeQuery;

/// GraphQL client instance
pub const GraphqlClient = struct {
    allocator: std.mem.Allocator,
    config: GraphqlConfig,

    pub fn init(allocator: std.mem.Allocator, config: GraphqlConfig) GraphqlClient {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Execute a pre-built query
    pub fn execute(
        self: *const GraphqlClient,
        query_builder: *QueryBuilder,
    ) ![]const u8 {
        const query = try query_builder.build();
        defer self.allocator.free(query);

        return try executeQuery(
            self.allocator,
            self.config.endpoint,
            query,
            self.config.timeout_ms,
        );
    }

    /// Get object by ID
    pub fn getObject(
        self: *const GraphqlClient,
        object_id: []const u8,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getObject(object_id, &builder);
        return try self.execute(&builder);
    }

    /// Get balance for address
    pub fn getBalance(
        self: *const GraphqlClient,
        address: []const u8,
        coin_type: ?[]const u8,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getBalance(address, coin_type, &builder);
        return try self.execute(&builder);
    }

    /// Get objects owned by address
    pub fn getObjects(
        self: *const GraphqlClient,
        owner: []const u8,
        limit: u32,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getObjects(owner, limit, &builder);
        return try self.execute(&builder);
    }

    /// Get transaction by digest
    pub fn getTransaction(
        self: *const GraphqlClient,
        digest: []const u8,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getTransaction(digest, &builder);
        return try self.execute(&builder);
    }

    /// Get chain information
    pub fn getChainInfo(self: *const GraphqlClient) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getChainInfo(&builder);
        return try self.execute(&builder);
    }

    /// Query events
    pub fn getEvents(
        self: *const GraphqlClient,
        package: []const u8,
        module: ?[]const u8,
        event_type: ?[]const u8,
        limit: u32,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getEvents(package, module, event_type, limit, &builder);
        return try self.execute(&builder);
    }

    /// Get coins for address
    pub fn getCoins(
        self: *const GraphqlClient,
        owner: []const u8,
        coin_type: ?[]const u8,
        limit: u32,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getCoins(owner, coin_type, limit, &builder);
        return try self.execute(&builder);
    }

    /// Get checkpoints
    pub fn getCheckpoints(
        self: *const GraphqlClient,
        cursor: ?u64,
        limit: u32,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getCheckpoints(cursor, limit, &builder);
        return try self.execute(&builder);
    }

    /// Get validators
    pub fn getValidators(self: *const GraphqlClient) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try PrebuiltQueries.getValidators(&builder);
        return try self.execute(&builder);
    }

    /// Execute raw query
    pub fn executeRaw(
        self: *const GraphqlClient,
        query: []const u8,
        variables: ?[]const u8,
    ) ![]const u8 {
        var builder = QueryBuilder.init(self.allocator);
        defer builder.deinit();

        try builder.query.appendSlice(self.allocator, query);
        if (variables) |vars| {
            try builder.setVariables(vars);
        }

        return try self.execute(&builder);
    }
};

test "GraphqlClient lifecycle" {
    const allocator = std.testing.allocator;
    const config = GraphqlConfig{};

    const gql_client = GraphqlClient.init(allocator, config);
    _ = gql_client;
}
