// main_v2_graphql.zig - GraphQL query commands
// Advanced querying with field selection

const std = @import("std");
const Allocator = std.mem.Allocator;
const sui_client = @import("sui_client_zig");
const graphql = sui_client.graphql;

pub fn cmdGraphql(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        printUsage();
        return;
    }

    const action = args[0];

    if (std.mem.eql(u8, action, "object")) {
        try cmdGraphqlObject(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "balance")) {
        try cmdGraphqlBalance(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "objects")) {
        try cmdGraphqlObjects(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "tx")) {
        try cmdGraphqlTx(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "chain")) {
        try cmdGraphqlChain(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "events")) {
        try cmdGraphqlEvents(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "coins")) {
        try cmdGraphqlCoins(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "checkpoints")) {
        try cmdGraphqlCheckpoints(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "validators")) {
        try cmdGraphqlValidators(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "raw")) {
        try cmdGraphqlRaw(allocator, args[1..]);
    } else if (std.mem.eql(u8, action, "build")) {
        try cmdGraphqlBuild(allocator, args[1..]);
    } else {
        std.log.err("Unknown graphql action: {s}", .{action});
        printUsage();
    }
}

fn printUsage() void {
    std.log.info("Usage: graphql <action> [options]", .{});
    std.log.info(" ", .{});
    std.log.info("Actions:", .{});
    std.log.info("  object <id>                 Get object by ID", .{});
    std.log.info("  balance <address> [type]    Get balance for address", .{});
    std.log.info("  objects <owner> [limit]     Query owned objects", .{});
    std.log.info("  tx <digest>                 Get transaction by digest", .{});
    std.log.info("  chain                       Get chain information", .{});
    std.log.info("  events <package> [module]   Query events", .{});
    std.log.info("  coins <owner> [type]        Query coins", .{});
    std.log.info("  checkpoints [limit]         Query checkpoints", .{});
    std.log.info("  validators                  Get validator set", .{});
    std.log.info("  raw <query> [vars]          Execute raw GraphQL query", .{});
    std.log.info("  build                       Interactive query builder", .{});
    std.log.info(" ", .{});
    std.log.info("Examples:", .{});
    std.log.info("  graphql object 0x6          Get Clock object", .{});
    std.log.info("  graphql balance 0x1234      Get SUI balance", .{});
    std.log.info("  graphql objects 0x1234 10   Get 10 owned objects", .{});
}

fn getEndpoint() []const u8 {
    return std.process.getEnvVarOwned(std.heap.page_allocator, "SUI_GRAPHQL_URL") catch
        "https://sui-mainnet.mystenlabs.com/graphql";
}

fn cmdGraphqlObject(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: graphql object <object_id>", .{});
        return;
    }

    const object_id = args[0];

    std.log.info("=== GraphQL: Get Object ===", .{});
    std.log.info("Object ID: {s}", .{object_id});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getObject(object_id) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlBalance(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: graphql balance <address> [coin_type]", .{});
        return;
    }

    const address = args[0];
    const coin_type = if (args.len > 1) args[1] else null;

    std.log.info("=== GraphQL: Get Balance ===", .{});
    std.log.info("Address: {s}", .{address});
    if (coin_type) |ct| {
        std.log.info("Coin Type: {s}", .{ct});
    } else {
        std.log.info("Coin Type: SUI (default)", .{});
    }
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getBalance(address, coin_type) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlObjects(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: graphql objects <owner> [limit]", .{});
        return;
    }

    const owner = args[0];
    const limit = if (args.len > 1)
        try std.fmt.parseInt(u32, args[1], 10)
    else
        10;

    std.log.info("=== GraphQL: Get Objects ===", .{});
    std.log.info("Owner: {s}", .{owner});
    std.log.info("Limit: {d}", .{limit});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getObjects(owner, limit) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlTx(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: graphql tx <digest>", .{});
        return;
    }

    const digest = args[0];

    std.log.info("=== GraphQL: Get Transaction ===", .{});
    std.log.info("Digest: {s}", .{digest});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getTransaction(digest) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlChain(allocator: Allocator, args: []const []const u8) !void {
    _ = args;

    std.log.info("=== GraphQL: Get Chain Info ===", .{});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getChainInfo() catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlEvents(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: graphql events <package> [module] [limit]", .{});
        return;
    }

    const package = args[0];
    const module = if (args.len > 1) args[1] else null;
    const limit = if (args.len > 2)
        try std.fmt.parseInt(u32, args[2], 10)
    else
        10;

    std.log.info("=== GraphQL: Get Events ===", .{});
    std.log.info("Package: {s}", .{package});
    if (module) |m| {
        std.log.info("Module: {s}", .{m});
    }
    std.log.info("Limit: {d}", .{limit});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getEvents(package, module, null, limit) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlCoins(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: graphql coins <owner> [type] [limit]", .{});
        return;
    }

    const owner = args[0];
    const coin_type = if (args.len > 1) args[1] else null;
    const limit = if (args.len > 2)
        try std.fmt.parseInt(u32, args[2], 10)
    else
        10;

    std.log.info("=== GraphQL: Get Coins ===", .{});
    std.log.info("Owner: {s}", .{owner});
    if (coin_type) |ct| {
        std.log.info("Type: {s}", .{ct});
    }
    std.log.info("Limit: {d}", .{limit});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getCoins(owner, coin_type, limit) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlCheckpoints(allocator: Allocator, args: []const []const u8) !void {
    const limit = if (args.len > 0)
        try std.fmt.parseInt(u32, args[0], 10)
    else
        10;

    std.log.info("=== GraphQL: Get Checkpoints ===", .{});
    std.log.info("Limit: {d}", .{limit});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getCheckpoints(null, limit) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlValidators(allocator: Allocator, args: []const []const u8) !void {
    _ = args;

    std.log.info("=== GraphQL: Get Validators ===", .{});
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.getValidators() catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlRaw(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.log.err("Usage: graphql raw <query> [variables]", .{});
        std.log.info("Example: graphql raw 'query ( checkpoint ( sequenceNumber ) )'", .{});
        return;
    }

    const query = args[0];
    const variables = if (args.len > 1) args[1] else null;

    std.log.info("=== GraphQL: Raw Query ===", .{});
    std.log.info("Query: {s}", .{query});
    if (variables) |vars| {
        std.log.info("Variables: {s}", .{vars});
    }
    std.log.info(" ", .{});

    const config = graphql.GraphqlConfig{
        .endpoint = getEndpoint(),
    };

    var client = graphql.GraphqlClient.init(allocator, config);

    const response = client.executeRaw(query, variables) catch |err| {
        std.log.err("Query failed: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(response);

    std.log.info("Response:", .{});
    std.log.info("{s}", .{response});
}

fn cmdGraphqlBuild(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;

    std.log.info("=== GraphQL Query Builder ===", .{});
    std.log.info(" ", .{});
    std.log.info("Interactive query builder coming soon!", .{});
    std.log.info(" ", .{});
    std.log.info("For now, use pre-built queries:", .{});
    std.log.info("  graphql object <id>", .{});
    std.log.info("  graphql balance <address>", .{});
    std.log.info("  graphql objects <owner>", .{});
    std.log.info("  graphql tx <digest>", .{});
    std.log.info("  graphql events <package>", .{});
    std.log.info(" ", .{});
    std.log.info("Or execute raw queries:", .{});
    std.log.info("  graphql raw 'query ( checkpoint ( sequenceNumber ) )'", .{});
}
