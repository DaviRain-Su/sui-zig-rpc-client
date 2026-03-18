const std = @import("std");

pub const OwnedMoveParameterSummary = struct {
    signature: []u8,
    lowering_kind: ?[]const u8 = null,
    placeholder_json: ?[]u8 = null,
    omitted_from_explicit_args: bool = false,

    pub fn deinit(self: *OwnedMoveParameterSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.signature);
        if (self.placeholder_json) |value| allocator.free(value);
    }
};

pub const OwnedMoveTypeParameter = struct {
    abilities: [][]const u8,
    is_phantom: bool = false,

    pub fn deinit(self: *OwnedMoveTypeParameter, allocator: std.mem.Allocator) void {
        for (self.abilities) |value| allocator.free(value);
        allocator.free(self.abilities);
    }
};

pub const OwnedMoveFunctionSummary = struct {
    package_id: ?[]u8 = null,
    module_name: ?[]u8 = null,
    function_name: ?[]u8 = null,
    visibility: ?[]u8 = null,
    is_entry: bool = false,
    type_parameters: []OwnedMoveTypeParameter,
    parameters: []OwnedMoveParameterSummary,
    returns: []OwnedMoveParameterSummary,
    call_template: ?OwnedMoveFunctionCallTemplate = null,

    pub fn deinit(self: *OwnedMoveFunctionSummary, allocator: std.mem.Allocator) void {
        if (self.package_id) |value| allocator.free(value);
        if (self.module_name) |value| allocator.free(value);
        if (self.function_name) |value| allocator.free(value);
        if (self.visibility) |value| allocator.free(value);
        for (self.type_parameters) |*item| item.deinit(allocator);
        allocator.free(self.type_parameters);
        for (self.parameters) |*item| item.deinit(allocator);
        allocator.free(self.parameters);
        for (self.returns) |*item| item.deinit(allocator);
        allocator.free(self.returns);
        if (self.call_template) |*value| value.deinit(allocator);
    }
};

pub const OwnedMoveFunctionCallTemplate = struct {
    type_args_json: []u8,
    args_json: []u8,
    move_call_command_json: []u8,

    pub fn deinit(self: *OwnedMoveFunctionCallTemplate, allocator: std.mem.Allocator) void {
        allocator.free(self.type_args_json);
        allocator.free(self.args_json);
        allocator.free(self.move_call_command_json);
    }
};

pub const OwnedMoveModuleSummary = struct {
    package_id: ?[]u8 = null,
    module_name: ?[]u8 = null,
    file_format_version: ?u64 = null,
    friend_count: usize = 0,
    struct_names: [][]const u8,
    exposed_function_names: [][]const u8,

    pub fn deinit(self: *OwnedMoveModuleSummary, allocator: std.mem.Allocator) void {
        if (self.package_id) |value| allocator.free(value);
        if (self.module_name) |value| allocator.free(value);
        for (self.struct_names) |value| allocator.free(value);
        allocator.free(self.struct_names);
        for (self.exposed_function_names) |value| allocator.free(value);
        allocator.free(self.exposed_function_names);
    }
};

pub const OwnedMovePackageModuleSummary = struct {
    module_name: []u8,
    struct_count: usize = 0,
    exposed_function_count: usize = 0,

    pub fn deinit(self: *OwnedMovePackageModuleSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.module_name);
    }
};

pub const OwnedMovePackageSummary = struct {
    package_id: ?[]u8 = null,
    modules: []OwnedMovePackageModuleSummary,

    pub fn deinit(self: *OwnedMovePackageSummary, allocator: std.mem.Allocator) void {
        if (self.package_id) |value| allocator.free(value);
        for (self.modules) |*module| module.deinit(allocator);
        allocator.free(self.modules);
    }
};

fn extractRootResult(value: std.json.Value) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get("result") orelse value;
}

fn parseOptionalU64(value: ?std.json.Value) ?u64 {
    const current = value orelse return null;
    return switch (current) {
        .integer => |number| if (number >= 0) @intCast(number) else null,
        .string => |text| std.fmt.parseInt(u64, text, 10) catch null,
        else => null,
    };
}

fn dupeOptionalStringField(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    comptime names: []const []const u8,
) !?[]u8 {
    inline for (names) |name| {
        if (object.get(name)) |value| {
            if (value != .string) return null;
            return try allocator.dupe(u8, value.string);
        }
    }
    return null;
}

fn appendMoveTypeText(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    value: std.json.Value,
) !void {
    switch (value) {
        .string => |text| try output.writer(allocator).print("{s}", .{text}),
        .integer => |number| try output.writer(allocator).print("{d}", .{number}),
        .object => |object| {
            if (object.get("Reference")) |inner| {
                try output.writer(allocator).writeAll("&");
                return try appendMoveTypeText(allocator, output, inner);
            }
            if (object.get("MutableReference")) |inner| {
                try output.writer(allocator).writeAll("&mut ");
                return try appendMoveTypeText(allocator, output, inner);
            }
            if (object.get("Vector")) |inner| {
                try output.writer(allocator).writeAll("vector<");
                try appendMoveTypeText(allocator, output, inner);
                try output.writer(allocator).writeAll(">");
                return;
            }
            if (object.get("TypeParameter")) |inner| {
                switch (inner) {
                    .integer => |number| try output.writer(allocator).print("T{d}", .{number}),
                    .string => |text| try output.writer(allocator).print("{s}", .{text}),
                    else => return error.InvalidResponse,
                }
                return;
            }
            if (object.get("Struct")) |struct_value| {
                if (struct_value != .object) return error.InvalidResponse;
                const address_value = struct_value.object.get("address") orelse return error.InvalidResponse;
                const module_value = struct_value.object.get("module") orelse return error.InvalidResponse;
                const name_value = struct_value.object.get("name") orelse return error.InvalidResponse;
                if (address_value != .string or module_value != .string or name_value != .string) return error.InvalidResponse;

                try output.writer(allocator).print(
                    "{s}::{s}::{s}",
                    .{ address_value.string, module_value.string, name_value.string },
                );

                const type_params_value = struct_value.object.get("typeArguments") orelse
                    struct_value.object.get("type_arguments") orelse
                    struct_value.object.get("typeParams") orelse
                    struct_value.object.get("type_params");
                if (type_params_value) |type_params| {
                    if (type_params != .array) return error.InvalidResponse;
                    if (type_params.array.items.len != 0) {
                        try output.writer(allocator).writeAll("<");
                        for (type_params.array.items, 0..) |item, index| {
                            if (index != 0) try output.writer(allocator).writeAll(", ");
                            try appendMoveTypeText(allocator, output, item);
                        }
                        try output.writer(allocator).writeAll(">");
                    }
                }
                return;
            }
            return error.InvalidResponse;
        },
        else => return error.InvalidResponse,
    }
}

fn moveTypeText(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) ![]u8 {
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    try appendMoveTypeText(allocator, &output, value);
    return output.toOwnedSlice(allocator);
}

fn parseAbilityNames(
    allocator: std.mem.Allocator,
    value: ?std.json.Value,
) ![][]const u8 {
    const current = value orelse return try allocator.alloc([]const u8, 0);
    if (current != .array) return error.InvalidResponse;

    const items = try allocator.alloc([]const u8, current.array.items.len);
    errdefer allocator.free(items);

    for (current.array.items, 0..) |item, index| {
        if (item != .string) return error.InvalidResponse;
        items[index] = try allocator.dupe(u8, item.string);
    }

    return items;
}

fn sortStringSlices(values: [][]const u8) void {
    var i: usize = 1;
    while (i < values.len) : (i += 1) {
        const current = values[i];
        var j = i;
        while (j > 0 and std.mem.order(u8, current, values[j - 1]) == .lt) : (j -= 1) {
            values[j] = values[j - 1];
        }
        values[j] = current;
    }
}

fn sortPackageModules(values: []OwnedMovePackageModuleSummary) void {
    var i: usize = 1;
    while (i < values.len) : (i += 1) {
        const current = values[i];
        var j = i;
        while (j > 0 and std.mem.order(u8, current.module_name, values[j - 1].module_name) == .lt) : (j -= 1) {
            values[j] = values[j - 1];
        }
        values[j] = current;
    }
}

fn collectObjectKeys(
    allocator: std.mem.Allocator,
    value: ?std.json.Value,
) ![][]const u8 {
    const current = value orelse return try allocator.alloc([]const u8, 0);
    if (current != .object) return error.InvalidResponse;

    const items = try allocator.alloc([]const u8, current.object.count());
    errdefer allocator.free(items);

    var index: usize = 0;
    var iterator = current.object.iterator();
    while (iterator.next()) |entry| : (index += 1) {
        items[index] = try allocator.dupe(u8, entry.key_ptr.*);
    }
    sortStringSlices(items);
    return items;
}

pub fn extractMoveFunctionSummary(
    allocator: std.mem.Allocator,
    response_json: []const u8,
    package_id: []const u8,
    module_name: []const u8,
    function_name: []const u8,
) !OwnedMoveFunctionSummary {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    const parameters_value = result.object.get("parameters") orelse return error.InvalidResponse;
    if (parameters_value != .array) return error.InvalidResponse;
    const returns_value = result.object.get("return") orelse result.object.get("returns") orelse return error.InvalidResponse;
    if (returns_value != .array) return error.InvalidResponse;
    const type_parameters_value = result.object.get("typeParameters") orelse result.object.get("type_parameters") orelse return error.InvalidResponse;
    if (type_parameters_value != .array) return error.InvalidResponse;

    const type_parameters = try allocator.alloc(OwnedMoveTypeParameter, type_parameters_value.array.items.len);
    errdefer allocator.free(type_parameters);
    for (type_parameters_value.array.items, 0..) |item, index| {
        type_parameters[index] = switch (item) {
            .object => .{
                .abilities = try parseAbilityNames(
                    allocator,
                    item.object.get("abilities") orelse item.object.get("constraints"),
                ),
                .is_phantom = if (item.object.get("isPhantom") orelse item.object.get("is_phantom")) |flag|
                    switch (flag) {
                        .bool => |value| value,
                        else => false,
                    }
                else
                    false,
            },
            .array => .{
                .abilities = try parseAbilityNames(allocator, item),
                .is_phantom = false,
            },
            else => return error.InvalidResponse,
        };
    }

    const parameters = try allocator.alloc(OwnedMoveParameterSummary, parameters_value.array.items.len);
    errdefer allocator.free(parameters);
    for (parameters_value.array.items, 0..) |item, index| {
        parameters[index] = .{
            .signature = try moveTypeText(allocator, item),
        };
    }

    const returns = try allocator.alloc(OwnedMoveParameterSummary, returns_value.array.items.len);
    errdefer allocator.free(returns);
    for (returns_value.array.items, 0..) |item, index| {
        returns[index] = .{
            .signature = try moveTypeText(allocator, item),
        };
    }

    return .{
        .package_id = try allocator.dupe(u8, package_id),
        .module_name = try allocator.dupe(u8, module_name),
        .function_name = try allocator.dupe(u8, function_name),
        .visibility = try dupeOptionalStringField(allocator, result.object, &.{ "visibility", "Visibility" }),
        .is_entry = if (result.object.get("isEntry") orelse result.object.get("is_entry")) |flag|
            switch (flag) {
                .bool => |value| value,
                else => false,
            }
        else
            false,
        .type_parameters = type_parameters,
        .parameters = parameters,
        .returns = returns,
    };
}

pub fn extractMoveModuleSummary(
    allocator: std.mem.Allocator,
    response_json: []const u8,
    package_id: []const u8,
    module_name: []const u8,
) !OwnedMoveModuleSummary {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    const struct_names = try collectObjectKeys(allocator, result.object.get("structs"));
    errdefer {
        for (struct_names) |value| allocator.free(value);
        allocator.free(struct_names);
    }
    const exposed_function_names = try collectObjectKeys(
        allocator,
        result.object.get("exposedFunctions") orelse result.object.get("exposed_functions"),
    );
    errdefer {
        for (exposed_function_names) |value| allocator.free(value);
        allocator.free(exposed_function_names);
    }

    return .{
        .package_id = try allocator.dupe(u8, package_id),
        .module_name = try allocator.dupe(u8, module_name),
        .file_format_version = parseOptionalU64(result.object.get("fileFormatVersion") orelse result.object.get("file_format_version")),
        .friend_count = if (result.object.get("friends")) |friends|
            switch (friends) {
                .array => friends.array.items.len,
                else => 0,
            }
        else
            0,
        .struct_names = struct_names,
        .exposed_function_names = exposed_function_names,
    };
}

pub fn extractMovePackageSummary(
    allocator: std.mem.Allocator,
    response_json: []const u8,
    package_id: []const u8,
) !OwnedMovePackageSummary {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_json, .{});
    defer parsed.deinit();

    const result = extractRootResult(parsed.value) orelse return error.InvalidResponse;
    if (result != .object) return error.InvalidResponse;

    const modules = try allocator.alloc(OwnedMovePackageModuleSummary, result.object.count());
    errdefer allocator.free(modules);

    var index: usize = 0;
    var iterator = result.object.iterator();
    while (iterator.next()) |entry| : (index += 1) {
        if (entry.value_ptr.* != .object) return error.InvalidResponse;
        const module_object = entry.value_ptr.*.object;
        modules[index] = .{
            .module_name = try allocator.dupe(u8, entry.key_ptr.*),
            .struct_count = if (module_object.get("structs")) |structs|
                switch (structs) {
                    .object => structs.object.count(),
                    else => 0,
                }
            else
                0,
            .exposed_function_count = if (module_object.get("exposedFunctions") orelse module_object.get("exposed_functions")) |functions|
                switch (functions) {
                    .object => functions.object.count(),
                    else => 0,
                }
            else
                0,
        };
    }
    sortPackageModules(modules);

    return .{
        .package_id = try allocator.dupe(u8, package_id),
        .modules = modules,
    };
}

test "extractMoveFunctionSummary parses normalized function responses" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractMoveFunctionSummary(
        allocator,
        \\{"result":{"visibility":"Public","isEntry":true,"typeParameters":[{"abilities":["drop","store"],"isPhantom":true}],"parameters":[{"MutableReference":{"Struct":{"address":"0x2","module":"pool","name":"Pool","typeParams":[]}}},"U64",{"TypeParameter":0}],"return":[{"Vector":"U8"}]}}
    ,
        "0x2",
        "pool",
        "swap",
    );
    defer summary.deinit(allocator);

    try testing.expectEqualStrings("0x2", summary.package_id.?);
    try testing.expectEqualStrings("pool", summary.module_name.?);
    try testing.expectEqualStrings("swap", summary.function_name.?);
    try testing.expectEqualStrings("Public", summary.visibility.?);
    try testing.expect(summary.is_entry);
    try testing.expectEqual(@as(usize, 1), summary.type_parameters.len);
    try testing.expect(summary.type_parameters[0].is_phantom);
    try testing.expectEqualStrings("drop", summary.type_parameters[0].abilities[0]);
    try testing.expectEqualStrings("&mut 0x2::pool::Pool", summary.parameters[0].signature);
    try testing.expectEqualStrings("U64", summary.parameters[1].signature);
    try testing.expectEqualStrings("T0", summary.parameters[2].signature);
    try testing.expectEqualStrings("vector<U8>", summary.returns[0].signature);
    try testing.expect(summary.parameters[0].placeholder_json == null);
    try testing.expect(summary.call_template == null);
}

test "extractMoveModuleSummary collects sorted struct and function names" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractMoveModuleSummary(
        allocator,
        \\{"result":{"fileFormatVersion":"6","friends":[{},{}],"structs":{"Position":{},"Pool":{}},"exposedFunctions":{"swap":{},"add_liquidity":{}}}}
    ,
        "0xpackage",
        "pool",
    );
    defer summary.deinit(allocator);

    try testing.expectEqualStrings("0xpackage", summary.package_id.?);
    try testing.expectEqualStrings("pool", summary.module_name.?);
    try testing.expectEqual(@as(?u64, 6), summary.file_format_version);
    try testing.expectEqual(@as(usize, 2), summary.friend_count);
    try testing.expectEqualStrings("Pool", summary.struct_names[0]);
    try testing.expectEqualStrings("Position", summary.struct_names[1]);
    try testing.expectEqualStrings("add_liquidity", summary.exposed_function_names[0]);
    try testing.expectEqualStrings("swap", summary.exposed_function_names[1]);
}

test "extractMovePackageSummary collects sorted module counts" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var summary = try extractMovePackageSummary(
        allocator,
        \\{"result":{"position":{"structs":{"Position":{}},"exposedFunctions":{"open_position":{}}},"pool":{"structs":{"Pool":{},"Tick":{}},"exposedFunctions":{"swap":{},"add_liquidity":{}}}}}
    ,
        "0xpackage",
    );
    defer summary.deinit(allocator);

    try testing.expectEqualStrings("0xpackage", summary.package_id.?);
    try testing.expectEqual(@as(usize, 2), summary.modules.len);
    try testing.expectEqualStrings("pool", summary.modules[0].module_name);
    try testing.expectEqual(@as(usize, 2), summary.modules[0].struct_count);
    try testing.expectEqual(@as(usize, 2), summary.modules[0].exposed_function_count);
    try testing.expectEqualStrings("position", summary.modules[1].module_name);
    try testing.expectEqual(@as(usize, 1), summary.modules[1].struct_count);
    try testing.expectEqual(@as(usize, 1), summary.modules[1].exposed_function_count);
}
