// GraphQL Client for Sui
// Supports complex queries with field selection and pagination

const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;

/// GraphQL client configuration
pub const GraphqlConfig = struct {
    endpoint: []const u8 = "https://sui-mainnet.mystenlabs.com/graphql",
    timeout_ms: u32 = 30000,
    max_response_size: usize = 10 * 1024 * 1024, // 10MB
};

/// GraphQL query builder
pub const QueryBuilder = struct {
    allocator: Allocator,
    query: std.ArrayListUnmanaged(u8) = .{},
    variables: std.ArrayListUnmanaged(u8) = .{},
    has_variables: bool = false,

    pub fn init(allocator: Allocator) QueryBuilder {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        self.query.deinit(self.allocator);
        self.variables.deinit(self.allocator);
    }

    /// Start a new query
    pub fn startQuery(self: *QueryBuilder, name: []const u8) !void {
        try self.query.appendSlice(self.allocator, "query ");
        try self.query.appendSlice(self.allocator, name);
        try self.query.appendSlice(self.allocator, " ");
    }

    /// Start a new query with variables
    pub fn startQueryWithVars(self: *QueryBuilder, name: []const u8, vars: []const u8) !void {
        try self.query.appendSlice(self.allocator, "query ");
        try self.query.appendSlice(self.allocator, name);
        try self.query.appendSlice(self.allocator, "(");
        try self.query.appendSlice(self.allocator, vars);
        try self.query.appendSlice(self.allocator, ") ");
    }

    /// Open a field selection
    pub fn openField(self: *QueryBuilder, name: []const u8) !void {
        try self.query.appendSlice(self.allocator, name);
        try self.query.appendSlice(self.allocator, " { ");
    }

    /// Open a field with arguments
    pub fn openFieldWithArgs(self: *QueryBuilder, name: []const u8, args: []const u8) !void {
        try self.query.appendSlice(self.allocator, name);
        try self.query.appendSlice(self.allocator, "(");
        try self.query.appendSlice(self.allocator, args);
        try self.query.appendSlice(self.allocator, ") { ");
    }

    /// Add a scalar field
    pub fn addField(self: *QueryBuilder, name: []const u8) !void {
        try self.query.appendSlice(self.allocator, name);
        try self.query.appendSlice(self.allocator, " ");
    }

    /// Close current field selection
    pub fn closeField(self: *QueryBuilder) !void {
        try self.query.appendSlice(self.allocator, "} ");
    }

    /// Add a fragment spread
    pub fn addFragment(self: *QueryBuilder, name: []const u8) !void {
        try self.query.appendSlice(self.allocator, "...");
        try self.query.appendSlice(self.allocator, name);
        try self.query.appendSlice(self.allocator, " ");
    }

    /// Set variables JSON
    pub fn setVariables(self: *QueryBuilder, json: []const u8) !void {
        self.variables.clearAndFree(self.allocator);
        try self.variables.appendSlice(self.allocator, json);
        self.has_variables = true;
    }

    /// Build final query string
    pub fn build(self: *QueryBuilder) ![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        errdefer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, "{\"query\":\"");

        // Escape the query string
        for (self.query.items) |c| {
            if (c == '"' or c == '\\' or c == '\n' or c == '\r' or c == '\t') {
                try result.append(self.allocator, '\\');
            }
            try result.append(self.allocator, c);
        }

        try result.appendSlice(self.allocator, "\"");

        if (self.has_variables) {
            try result.appendSlice(self.allocator, ",\"variables\":");
            try result.appendSlice(self.allocator, self.variables.items);
        }

        try result.appendSlice(self.allocator, "}");

        return try result.toOwnedSlice(self.allocator);
    }

    /// Get raw query (for debugging)
    pub fn getQuery(self: *QueryBuilder) []const u8 {
        return self.query.items;
    }
};

/// Pre-built queries for common operations
pub const PrebuiltQueries = struct {
    /// Get object with all fields
    pub fn getObject(object_id: []const u8, builder: *QueryBuilder) !void {
        try builder.startQueryWithVars("GetObject", "$id: SuiAddress!");
        try builder.openFieldWithArgs("object", "address: $id");
        try builder.addField("address");
        try builder.openField("asMoveObject");
        try builder.openField("asMovePackage");
        try builder.addField("moduleNames");
        try builder.closeField();
        try builder.openField("contents");
        try builder.addField("type");
        try builder.addField("json");
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();

        var vars_buf: [256]u8 = undefined;
        const vars = try std.fmt.bufPrint(&vars_buf, "{{\"id\":\"{s}\"}}", .{object_id});
        try builder.setVariables(vars);
    }

    /// Get transaction with effects
    pub fn getTransaction(digest: []const u8, builder: *QueryBuilder) !void {
        try builder.startQueryWithVars("GetTransaction", "$digest: String!");
        try builder.openFieldWithArgs("transactionBlock", "digest: $digest");
        try builder.addField("digest");
        try builder.addField("bcs");
        try builder.openField("effects");
        try builder.addField("bcs");
        try builder.openField("gasEffects");
        try builder.addField("gasObject");
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();

        var vars_buf: [256]u8 = undefined;
        const vars = try std.fmt.bufPrint(&vars_buf, "{{\"digest\":\"{s}\"}}", .{digest});
        try builder.setVariables(vars);
    }

    /// Get balance for address
    pub fn getBalance(address: []const u8, coin_type: ?[]const u8, builder: *QueryBuilder) !void {
        try builder.startQueryWithVars("GetBalance", "$owner: SuiAddress!, $type: String");
        try builder.openFieldWithArgs("balance", "owner: $owner, type: $type");
        try builder.addField("coinType");
        try builder.addField("coinObjectCount");
        try builder.addField("totalBalance");
        try builder.closeField();

        var vars_buf: [512]u8 = undefined;
        const vars = if (coin_type) |ct|
            try std.fmt.bufPrint(&vars_buf, "{{\"owner\":\"{s}\",\"type\":\"{s}\"}}", .{ address, ct })
        else
            try std.fmt.bufPrint(&vars_buf, "{{\"owner\":\"{s}\",\"type\":null}}", .{address});
        try builder.setVariables(vars);
    }

    /// Query objects owned by address
    pub fn getObjects(owner: []const u8, limit: u32, builder: *QueryBuilder) !void {
        try builder.startQueryWithVars("GetObjects", "$owner: SuiAddress!, $limit: Int");
        try builder.openFieldWithArgs("objects", "filter: {owner: $owner}, first: $limit");
        try builder.openField("nodes");
        try builder.addField("address");
        try builder.openField("asMoveObject");
        try builder.openField("contents");
        try builder.addField("type");
        try builder.addField("json");
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();

        var vars_buf: [256]u8 = undefined;
        const vars = try std.fmt.bufPrint(&vars_buf, "{{\"owner\":\"{s}\",\"limit\":{d}}}", .{ owner, limit });
        try builder.setVariables(vars);
    }

    /// Query transactions with filters
    pub fn getTransactions(
        sender: ?[]const u8,
        function: ?[]const u8,
        limit: u32,
        builder: *QueryBuilder,
    ) !void {
        try builder.startQueryWithVars("GetTransactions", "$filter: TransactionBlockFilter, $limit: Int");
        try builder.openFieldWithArgs("transactionBlocks", "filter: $filter, first: $limit");
        try builder.openField("nodes");
        try builder.addField("digest");
        try builder.addField("bcs");
        try builder.openField("signatures");
        try builder.addField("base64Sig");
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();

        // Build filter JSON
        var filter_buf: [512]u8 = undefined;
        var filter: []const u8 = undefined;

        if (sender) |s| {
            if (function) |f| {
                filter = try std.fmt.bufPrint(&filter_buf, "{{\"signAddress\":\"{s}\",\"function\":\"{s}\"}}", .{ s, f });
            } else {
                filter = try std.fmt.bufPrint(&filter_buf, "{{\"signAddress\":\"{s}\"}}", .{s});
            }
        } else {
            filter = "{}";
        }

        var vars_buf: [1024]u8 = undefined;
        const vars = try std.fmt.bufPrint(&vars_buf, "{{\"filter\":{s},\"limit\":{d}}}", .{ filter, limit });
        try builder.setVariables(vars);
    }

    /// Get chain information
    pub fn getChainInfo(builder: *QueryBuilder) !void {
        try builder.startQuery("GetChainInfo");
        try builder.openField("chainIdentifier");
        try builder.addField("chain");
        try builder.closeField();
        try builder.openField("protocolConfig");
        try builder.addField("protocolVersion");
        try builder.addField("config");
        try builder.closeField();
        try builder.openField("checkpoint");
        try builder.addField("sequenceNumber");
        try builder.addField("digest");
        try builder.addField("timestamp");
        try builder.closeField();
    }

    /// Query events
    pub fn getEvents(
        package: []const u8,
        module: ?[]const u8,
        event_type: ?[]const u8,
        limit: u32,
        builder: *QueryBuilder,
    ) !void {
        try builder.startQueryWithVars("GetEvents", "$filter: EventFilter, $limit: Int");
        try builder.openFieldWithArgs("events", "filter: $filter, first: $limit");
        try builder.openField("nodes");
        try builder.addField("id");
        try builder.openField("contents");
        try builder.addField("type");
        try builder.addField("json");
        try builder.closeField();
        try builder.openField("transactionBlock");
        try builder.addField("digest");
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();

        var filter_buf: [512]u8 = undefined;
        const filter = if (module) |m|
            if (event_type) |et|
                try std.fmt.bufPrint(&filter_buf, "{{\"emittingModule\":\"{s}::{s}\",\"eventType\":\"{s}\"}}", .{ package, m, et })
            else
                try std.fmt.bufPrint(&filter_buf, "{{\"emittingModule\":\"{s}::{s}\"}}", .{ package, m })
        else
            try std.fmt.bufPrint(&filter_buf, "{{\"emittingPackage\":\"{s}\"}}", .{package});

        var vars_buf: [1024]u8 = undefined;
        const vars = try std.fmt.bufPrint(&vars_buf, "{{\"filter\":{s},\"limit\":{d}}}", .{ filter, limit });
        try builder.setVariables(vars);
    }

    /// Query coins for address
    pub fn getCoins(owner: []const u8, coin_type: ?[]const u8, limit: u32, builder: *QueryBuilder) !void {
        try builder.startQueryWithVars("GetCoins", "$owner: SuiAddress!, $type: String, $limit: Int");
        try builder.openFieldWithArgs("coins", "owner: $owner, type: $type, first: $limit");
        try builder.openField("nodes");
        try builder.addField("coinType");
        try builder.addField("coinObjectCount");
        try builder.addField("totalBalance");
        try builder.closeField();
        try builder.closeField();

        var vars_buf: [512]u8 = undefined;
        const vars = if (coin_type) |ct|
            try std.fmt.bufPrint(&vars_buf, "{{\"owner\":\"{s}\",\"type\":\"{s}\",\"limit\":{d}}}", .{ owner, ct, limit })
        else
            try std.fmt.bufPrint(&vars_buf, "{{\"owner\":\"{s}\",\"type\":null,\"limit\":{d}}}", .{ owner, limit });
        try builder.setVariables(vars);
    }

    /// Query checkpoints
    pub fn getCheckpoints(cursor: ?u64, limit: u32, builder: *QueryBuilder) !void {
        try builder.startQueryWithVars("GetCheckpoints", "$cursor: Int, $limit: Int");
        try builder.openFieldWithArgs("checkpoints", "before: $cursor, first: $limit");
        try builder.openField("nodes");
        try builder.addField("sequenceNumber");
        try builder.addField("digest");
        try builder.addField("timestamp");
        try builder.openField("transactionBlocks");
        try builder.addField("digest");
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();

        var vars_buf: [256]u8 = undefined;
        const vars = if (cursor) |c|
            try std.fmt.bufPrint(&vars_buf, "{{\"cursor\":{d},\"limit\":{d}}}", .{ c, limit })
        else
            try std.fmt.bufPrint(&vars_buf, "{{\"cursor\":null,\"limit\":{d}}}", .{limit});
        try builder.setVariables(vars);
    }

    /// Query validator set
    pub fn getValidators(builder: *QueryBuilder) !void {
        try builder.startQuery("GetValidators");
        try builder.openField("epoch");
        try builder.openField("validatorSet");
        try builder.openField("activeValidators");
        try builder.openField("nodes");
        try builder.addField("name");
        try builder.addField("description");
        try builder.addField("suiAddress");
        try builder.openField("stakingPool");
        try builder.addField("suiBalance");
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();
        try builder.closeField();
    }
};

/// GraphQL response parser
pub const ResponseParser = struct {
    /// Extract data field from response
    pub fn extractData(response: []const u8, allocator: Allocator) !std.json.Value {
        var parser = std.json.Parser.init(allocator, .alloc_if_needed);
        defer parser.deinit();

        var tree = try parser.parse(response);
        errdefer tree.deinit();

        if (tree.root.object.get("data")) |data| {
            return data;
        }

        return error.NoDataField;
    }

    /// Extract errors from response
    pub fn extractErrors(response: []const u8, allocator: Allocator) ?[]std.json.Value {
        var parser = std.json.Parser.init(allocator, .alloc_if_needed);
        defer parser.deinit();

        var tree = parser.parse(response) catch return null;
        defer tree.deinit();

        if (tree.root.object.get("errors")) |errors| {
            if (errors == .array) {
                return errors.array.items;
            }
        }

        return null;
    }

    /// Check if response has errors
    pub fn hasErrors(response: []const u8, allocator: Allocator) bool {
        return extractErrors(response, allocator) != null;
    }
};

/// Execute GraphQL query via HTTP POST
/// Note: This is a mock implementation for demo purposes
pub fn executeQuery(
    allocator: Allocator,
    endpoint: []const u8,
    query: []const u8,
    _timeout_ms: u32,
) ![]const u8 {
    _ = _timeout_ms;
    _ = endpoint;

    // Mock response - in production, this would make actual HTTP request
    const mock_response = try std.fmt.allocPrint(allocator, "{{\"data\":{{\"query\":\"{s}\"}},\"mock\":true}}", .{query[0..@min(query.len, 100)]});

    return mock_response;
}

// Tests
test "QueryBuilder basic query" {
    const allocator = std.testing.allocator;
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();

    try builder.startQuery("TestQuery");
    try builder.openField("object");
    try builder.addField("address");
    try builder.addField("digest");
    try builder.closeField();

    const query = try builder.build();
    defer allocator.free(query);

    try std.testing.expect(std.mem.indexOf(u8, query, "query TestQuery") != null);
    try std.testing.expect(std.mem.indexOf(u8, query, "object") != null);
}

test "PrebuiltQueries getObject" {
    const allocator = std.testing.allocator;
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();

    try PrebuiltQueries.getObject("0x1234", &builder);

    const query = builder.getQuery();
    try std.testing.expect(std.mem.indexOf(u8, query, "GetObject") != null);
    try std.testing.expect(std.mem.indexOf(u8, query, "0x1234") != null);
}

test "PrebuiltQueries getBalance" {
    const allocator = std.testing.allocator;
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();

    try PrebuiltQueries.getBalance("0x5678", null, &builder);

    const query = builder.getQuery();
    try std.testing.expect(std.mem.indexOf(u8, query, "GetBalance") != null);
    try std.testing.expect(std.mem.indexOf(u8, query, "totalBalance") != null);
}
