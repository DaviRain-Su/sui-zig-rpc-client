const std = @import("std");

pub const InspectStatus = enum {
    success,
    failure,
    unknown,
};

pub const OwnedInspectInsights = struct {
    status: InspectStatus = .unknown,
    error_message: ?[]u8 = null,
    results_count: usize = 0,
    events_count: usize = 0,

    pub fn deinit(self: *OwnedInspectInsights, allocator: std.mem.Allocator) void {
        if (self.error_message) |value| allocator.free(value);
    }
};

fn extractRootResult(value: std.json.Value) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get("result") orelse value;
}

pub fn extractInspectInsights(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !OwnedInspectInsights {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    var status: InspectStatus = .unknown;
    var error_message: ?[]u8 = null;

    if (result.object.get("effects")) |effects_value| {
        if (effects_value == .object) {
            if (effects_value.object.get("status")) |status_value| {
                if (status_value == .object) {
                    if (status_value.object.get("status")) |kind_value| {
                        if (kind_value == .string) {
                            if (std.mem.eql(u8, kind_value.string, "success")) {
                                status = .success;
                            } else if (std.mem.eql(u8, kind_value.string, "failure")) {
                                status = .failure;
                            }
                        }
                    }
                    if (status_value.object.get("error")) |error_value| {
                        if (error_value == .string) {
                            error_message = try allocator.dupe(u8, error_value.string);
                        }
                    }
                }
            }
        }
    }

    if (status == .unknown) {
        if (result.object.get("error")) |error_value| {
            switch (error_value) {
                .string => {
                    status = .failure;
                    error_message = try allocator.dupe(u8, error_value.string);
                },
                .object => {
                    if (error_value.object.get("message")) |message_value| {
                        if (message_value == .string) {
                            status = .failure;
                            error_message = try allocator.dupe(u8, message_value.string);
                        }
                    }
                },
                else => {},
            }
        }
    }

    return .{
        .status = status,
        .error_message = error_message,
        .results_count = if (result.object.get("results")) |results_value|
            switch (results_value) {
                .array => |array| array.items.len,
                else => 0,
            }
        else
            0,
        .events_count = if (result.object.get("events")) |events_value|
            switch (events_value) {
                .array => |array| array.items.len,
                else => 0,
            }
        else
            0,
    };
}

test "extractInspectInsights parses dev-inspect success envelopes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var insights = try extractInspectInsights(allocator,
        \\{"result":{"effects":{"status":{"status":"success"}},"events":[{"type":"A"},{"type":"B"}],"results":[{"returnValues":[]}]}}
    );
    defer insights.deinit(allocator);

    try testing.expectEqual(InspectStatus.success, insights.status);
    try testing.expect(insights.error_message == null);
    try testing.expectEqual(@as(usize, 1), insights.results_count);
    try testing.expectEqual(@as(usize, 2), insights.events_count);
}

test "extractInspectInsights parses dev-inspect failures" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var insights = try extractInspectInsights(allocator,
        \\{"result":{"effects":{"status":{"status":"failure","error":"move abort"}},"results":[],"events":[]}}
    );
    defer insights.deinit(allocator);

    try testing.expectEqual(InspectStatus.failure, insights.status);
    try testing.expectEqualStrings("move abort", insights.error_message.?);
    try testing.expectEqual(@as(usize, 0), insights.results_count);
    try testing.expectEqual(@as(usize, 0), insights.events_count);
}
