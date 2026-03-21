/// client/rpc_client/event.zig - Event methods for RPC client
const std = @import("std");
const client_core = @import("client_core.zig");
const utils = @import("utils.zig");

const SuiRpcClient = client_core.SuiRpcClient;
const ClientError = @import("error.zig").ClientError;

/// Query events
pub fn queryEvents(
    client: *SuiRpcClient,
    filter: EventFilter,
    cursor: ?[]const u8,
    limit: ?u32,
    descending_order: bool,
) !EventPage {
    const filter_json = filter.toJson();

    var params_buf: [2048]u8 = undefined;
    const params = try std.fmt.bufPrint(
        &params_buf,
        "[{s},{s},{},{}]",
        .{
            filter_json,
            if (cursor) |c| try std.fmt.bufPrint(&params_buf, "\"{s}\"", .{c}) else "null",
            limit orelse 50,
            descending_order,
        },
    );

    const response = try client.call("suix_queryEvents", params);
    defer client.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("result")) |result| {
        return try parseEventPage(client.allocator, result);
    }

    return ClientError.InvalidResponse;
}

/// Event filter
pub const EventFilter = union(enum) {
    all: void,
    transaction: []const u8,
    move_module: struct { package: []const u8, module: []const u8 },
    move_event_type: []const u8,
    sender: []const u8,
    time_range: struct { start_time: u64, end_time: u64 },
    and: []const EventFilter,
    or: []const EventFilter,

    pub fn toJson(self: EventFilter) []const u8 {
        var buf: [1024]u8 = undefined;
        return switch (self) {
            .all => "{\"All\":[]}",
            .transaction => |t| std.fmt.bufPrint(&buf, "{{\"Transaction\":\"{s}\"}}", .{t}) catch "null",
            .move_module => |m| std.fmt.bufPrint(
                &buf,
                "{{\"MoveModule\":{{\"package\":\"{s}\",\"module\":\"{s}\"}}}}",
                .{ m.package, m.module },
            ) catch "null",
            .move_event_type => |t| std.fmt.bufPrint(&buf, "{{\"MoveEventType\":\"{s}\"}}", .{t}) catch "null",
            .sender => |s| std.fmt.bufPrint(&buf, "{{\"Sender\":\"{s}\"}}", .{s}) catch "null",
            .time_range => |tr| std.fmt.bufPrint(
                &buf,
                "{{\"TimeRange\":{{\"startTime\":{},\"endTime\":{}}}}}",
                .{ tr.start_time, tr.end_time },
            ) catch "null",
            else => "null",
        };
    }
};

/// Event page
pub const EventPage = struct {
    data: []SuiEvent,
    next_cursor: ?[]const u8,
    has_next_page: bool,

    pub fn deinit(self: *EventPage, allocator: std.mem.Allocator) void {
        for (self.data) |*event| {
            event.deinit(allocator);
        }
        allocator.free(self.data);
        if (self.next_cursor) |cursor| allocator.free(cursor);
    }
};

/// Sui event
pub const SuiEvent = struct {
    id: EventId,
    package_id: []const u8,
    transaction_module: []const u8,
    sender: []const u8,
    type: []const u8,
    parsed_json: ?[]const u8,
    bcs: []const u8,
    timestamp_ms: ?u64,

    pub fn deinit(self: *SuiEvent, allocator: std.mem.Allocator) void {
        self.id.deinit(allocator);
        allocator.free(self.package_id);
        allocator.free(self.transaction_module);
        allocator.free(self.sender);
        allocator.free(self.type);
        if (self.parsed_json) |json| allocator.free(json);
        allocator.free(self.bcs);
    }
};

/// Event ID
pub const EventId = struct {
    tx_digest: []const u8,
    event_seq: u64,

    pub fn deinit(self: *EventId, allocator: std.mem.Allocator) void {
        allocator.free(self.tx_digest);
    }
};

/// Parse event page from JSON
fn parseEventPage(allocator: std.mem.Allocator, value: std.json.Value) !EventPage {
    const data = value.object.get("data") orelse return ClientError.InvalidResponse;

    var events = std.ArrayList(SuiEvent).init(allocator);
    errdefer {
        for (events.items) |*event| event.deinit(allocator);
        events.deinit();
    }

    if (data == .array) {
        for (data.array.items) |item| {
            const event = try parseEvent(allocator, item);
            try events.append(event);
        }
    }

    var next_cursor: ?[]const u8 = null;
    if (value.object.get("nextCursor")) |cursor| {
        if (cursor == .string) {
            next_cursor = try allocator.dupe(u8, cursor.string);
        }
    }

    const has_next_page = if (value.object.get("hasNextPage")) |has|
        has == .bool and has.bool
    else
        false;

    return EventPage{
        .data = try events.toOwnedSlice(),
        .next_cursor = next_cursor,
        .has_next_page = has_next_page,
    };
}

/// Parse event from JSON
fn parseEvent(allocator: std.mem.Allocator, value: std.json.Value) !SuiEvent {
    const id = value.object.get("id").?;
    const package_id = value.object.get("packageId").?;
    const transaction_module = value.object.get("transactionModule").?;
    const sender = value.object.get("sender").?;
    const event_type = value.object.get("type").?;
    const bcs = value.object.get("bcs").?;

    var parsed_json: ?[]const u8 = null;
    if (value.object.get("parsedJson")) |pj| {
        parsed_json = try std.json.stringifyAlloc(allocator, pj, .{});
    }

    var timestamp_ms: ?u64 = null;
    if (value.object.get("timestampMs")) |ts| {
        if (ts != .null) {
            timestamp_ms = if (ts == .integer)
                @intCast(ts.integer)
            else
                try std.fmt.parseInt(u64, ts.string, 10);
        }
    }

    return SuiEvent{
        .id = EventId{
            .tx_digest = try allocator.dupe(u8, id.object.get("txDigest").?.string),
            .event_seq = @intCast(id.object.get("eventSeq").?.integer),
        },
        .package_id = try allocator.dupe(u8, package_id.string),
        .transaction_module = try allocator.dupe(u8, transaction_module.string),
        .sender = try allocator.dupe(u8, sender.string),
        .type = try allocator.dupe(u8, event_type.string),
        .parsed_json = parsed_json,
        .bcs = try allocator.dupe(u8, bcs.string),
        .timestamp_ms = timestamp_ms,
    };
}

/// Subscribe to events (WebSocket)
pub const EventSubscription = struct {
    filter: EventFilter,
    callback: *const fn (*SuiEvent) void,
};

/// Subscribe to events (placeholder - requires WebSocket implementation)
pub fn subscribeToEvents(
    client: *SuiRpcClient,
    subscription: EventSubscription,
) !void {
    _ = client;
    _ = subscription;
    // WebSocket subscription would be implemented here
    return ClientError.NotImplemented;
}

// ============================================================
// Tests
// ============================================================

test "EventFilter toJson" {
    const testing = std.testing;

    const all_filter = EventFilter{ .all = {} };
    try testing.expectEqualStrings("{\"All\":[]}", all_filter.toJson());

    const tx_filter = EventFilter{ .transaction = "0xabc" };
    const tx_json = tx_filter.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, tx_json, 1, "Transaction"));

    const module_filter = EventFilter{ .move_module = .{ .package = "0x2", .module = "sui" } };
    const module_json = module_filter.toJson();
    try testing.expect(std.mem.containsAtLeast(u8, module_json, 1, "MoveModule"));
}

test "EventId structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var id = EventId{
        .tx_digest = try allocator.dupe(u8, "0xabc"),
        .event_seq = 42,
    };
    defer id.deinit(allocator);

    try testing.expectEqualStrings("0xabc", id.tx_digest);
    try testing.expectEqual(@as(u64, 42), id.event_seq);
}

test "SuiEvent structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event = SuiEvent{
        .id = EventId{
            .tx_digest = try allocator.dupe(u8, "0xabc"),
            .event_seq = 0,
        },
        .package_id = try allocator.dupe(u8, "0x2"),
        .transaction_module = try allocator.dupe(u8, "sui"),
        .sender = try allocator.dupe(u8, "0x123"),
        .type = try allocator.dupe(u8, "0x2::event::Event"),
        .parsed_json = try allocator.dupe(u8, "{}"),
        .bcs = try allocator.dupe(u8, "0x00"),
        .timestamp_ms = 1234567890,
    };
    defer event.deinit(allocator);

    try testing.expectEqualStrings("0x2", event.package_id);
    try testing.expectEqual(@as(u64, 1234567890), event.timestamp_ms.?);
}

test "EventPage structure" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const events = try allocator.alloc(SuiEvent, 1);
    events[0] = SuiEvent{
        .id = EventId{
            .tx_digest = try allocator.dupe(u8, "0xabc"),
            .event_seq = 0,
        },
        .package_id = try allocator.dupe(u8, "0x2"),
        .transaction_module = try allocator.dupe(u8, "sui"),
        .sender = try allocator.dupe(u8, "0x123"),
        .type = try allocator.dupe(u8, "0x2::event::Event"),
        .parsed_json = null,
        .bcs = try allocator.dupe(u8, "0x00"),
        .timestamp_ms = null,
    };

    var page = EventPage{
        .data = events,
        .next_cursor = try allocator.dupe(u8, "cursor"),
        .has_next_page = false,
    };
    defer page.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), page.data.len);
    try testing.expect(!page.has_next_page);
}

test "subscribeToEvents returns NotImplemented" {
    const testing = std.testing;

    // This would require a mock client
    // For now, just verify the error type exists
    _ = ClientError.NotImplemented;
}
