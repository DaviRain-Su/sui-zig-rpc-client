const std = @import("std");
const tx_builder = @import("./tx_builder.zig");

pub const default_sui_keystore_path = ".sui/sui_config/sui.keystore";
pub var test_keystore_path_override: ?[]const u8 = null;

pub const SignerPreparation = struct {
    signer_selectors: []const []const u8 = &.{},
    from_keystore: bool = false,
    infer_sender_from_signers: bool = true,
};

pub const PreparedProgrammaticRequest = struct {
    request: tx_builder.ProgrammaticTxRequest,
    combined_signatures: std.ArrayListUnmanaged([]const u8) = .{},
    owned_signatures: std.ArrayListUnmanaged([]const u8) = .{},
    owned_sender: ?[]const u8 = null,

    pub fn deinit(self: *PreparedProgrammaticRequest, allocator: std.mem.Allocator) void {
        if (self.owned_sender) |value| allocator.free(value);
        for (self.owned_signatures.items) |value| allocator.free(value);
        self.combined_signatures.deinit(allocator);
        self.owned_signatures.deinit(allocator);
    }
};

pub const AccountEntryKind = enum {
    raw_string,
    object,
    unsupported,
};

pub const OwnedAccountEntry = struct {
    index: usize,
    kind: AccountEntryKind,
    selector: ?[]u8 = null,
    alias: ?[]u8 = null,
    name: ?[]u8 = null,
    address: ?[]u8 = null,
    sui_address: ?[]u8 = null,
    public_key: ?[]u8 = null,

    pub fn deinit(self: *OwnedAccountEntry, allocator: std.mem.Allocator) void {
        if (self.selector) |value| allocator.free(value);
        if (self.alias) |value| allocator.free(value);
        if (self.name) |value| allocator.free(value);
        if (self.address) |value| allocator.free(value);
        if (self.sui_address) |value| allocator.free(value);
        if (self.public_key) |value| allocator.free(value);
    }
};

pub const OwnedAccountEntries = struct {
    accounts: []OwnedAccountEntry,

    pub fn deinit(self: *OwnedAccountEntries, allocator: std.mem.Allocator) void {
        for (self.accounts) |*entry| entry.deinit(allocator);
        allocator.free(self.accounts);
    }
};

pub const AccountQuery = union(enum) {
    list,
    info: []const u8,
};

pub const AccountQueryResult = union(enum) {
    list: OwnedAccountEntries,
    info: OwnedAccountEntry,

    pub fn deinit(self: *AccountQueryResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .list => |*value| value.deinit(allocator),
            .info => |*value| value.deinit(allocator),
        }
    }
};

pub const OwnedSignatureList = struct {
    items: [][]const u8,

    pub fn deinit(self: *OwnedSignatureList, allocator: std.mem.Allocator) void {
        for (self.items) |item| allocator.free(item);
        allocator.free(self.items);
    }
};

const sui_transaction_intent = [_]u8{ 0, 0, 0 };
const ed25519_flag: u8 = 0x00;

const RawKeyMaterial = struct {
    scheme_flag: u8,
    seed: [32]u8,
    public_key: [32]u8,
};

fn expandTildePath(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    if (path.len == 0 or std.mem.eql(u8, path, "~")) return null;
    if (!std.mem.startsWith(u8, path, "~/")) {
        return try allocator.dupe(u8, path);
    }

    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    const expanded = try std.fs.path.join(allocator, &.{ home_dir, path[2..] });
    defer allocator.free(expanded);
    return try allocator.dupe(u8, expanded);
}

fn defaultSuiKeystorePath(allocator: std.mem.Allocator) !?[]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(home_dir);

    return try std.fs.path.join(allocator, &.{ home_dir, default_sui_keystore_path });
}

pub fn resolveDefaultSuiKeystorePath(allocator: std.mem.Allocator) !?[]const u8 {
    if (test_keystore_path_override) |override_path| {
        if (override_path.len == 0) return null;
        return try allocator.dupe(u8, override_path);
    }

    const env_or_default_keystore_path = std.process.getEnvVarOwned(allocator, "SUI_KEYSTORE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try defaultSuiKeystorePath(allocator),
        else => return err,
    };
    if (env_or_default_keystore_path == null) return null;
    const keystore_path = env_or_default_keystore_path.?;
    defer allocator.free(keystore_path);
    if (keystore_path.len == 0) return null;

    return try expandTildePath(allocator, keystore_path);
}

fn encodeBase64Owned(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return encoded;
}

fn parseRawKeyMaterial(raw_key: []const u8) !RawKeyMaterial {
    const trimmed = std.mem.trim(u8, raw_key, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(trimmed) catch return error.InvalidCli;
    if (decoded_len != 33) return error.InvalidCli;

    var decoded: [33]u8 = undefined;
    try std.base64.standard.Decoder.decode(&decoded, trimmed);

    const scheme_flag = decoded[0];
    if (scheme_flag != ed25519_flag) return error.UnsupportedSignatureScheme;

    const seed: [32]u8 = decoded[1..].*;
    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);
    return .{
        .scheme_flag = scheme_flag,
        .seed = seed,
        .public_key = keypair.public_key.toBytes(),
    };
}

fn deriveAddressFromRawKeyString(allocator: std.mem.Allocator, raw_key: []const u8) ![]u8 {
    const material = try parseRawKeyMaterial(raw_key);

    var hasher = std.crypto.hash.blake2.Blake2b256.init(.{});
    hasher.update(&.{material.scheme_flag});
    hasher.update(&material.public_key);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    const hex = std.fmt.bytesToHex(digest, .lower);
    return try std.fmt.allocPrint(allocator, "0x{s}", .{hex[0..]});
}

fn maybeDeriveAddressFromRawKeyString(
    allocator: std.mem.Allocator,
    raw_key: []const u8,
) !?[]u8 {
    return deriveAddressFromRawKeyString(allocator, raw_key) catch |err| switch (err) {
        error.InvalidCli, error.UnsupportedSignatureScheme => null,
        else => return err,
    };
}

fn maybeDerivePublicKeyFromRawKeyString(
    allocator: std.mem.Allocator,
    raw_key: []const u8,
) !?[]u8 {
    const material = parseRawKeyMaterial(raw_key) catch |err| switch (err) {
        error.InvalidCli, error.UnsupportedSignatureScheme => return null,
        else => return err,
    };

    var full_public_key: [33]u8 = undefined;
    full_public_key[0] = material.scheme_flag;
    full_public_key[1..].* = material.public_key;
    return try encodeBase64Owned(allocator, &full_public_key);
}

fn signTransactionBytesWithRawKey(
    allocator: std.mem.Allocator,
    raw_key: []const u8,
    tx_bytes_base64: []const u8,
) ![]u8 {
    const material = try parseRawKeyMaterial(raw_key);

    const tx_bytes_len = std.base64.standard.Decoder.calcSizeForSlice(tx_bytes_base64) catch return error.InvalidCli;
    const tx_bytes = try allocator.alloc(u8, tx_bytes_len);
    defer allocator.free(tx_bytes);
    try std.base64.standard.Decoder.decode(tx_bytes, tx_bytes_base64);

    var digest_hasher = std.crypto.hash.blake2.Blake2b256.init(.{});
    digest_hasher.update(&sui_transaction_intent);
    digest_hasher.update(tx_bytes);

    var digest: [32]u8 = undefined;
    digest_hasher.final(&digest);

    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(material.seed);
    const signature = try keypair.sign(&digest, null);
    const signature_bytes = signature.toBytes();

    var sui_signature: [97]u8 = undefined;
    sui_signature[0] = material.scheme_flag;
    sui_signature[1 .. 1 + signature_bytes.len].* = signature_bytes;
    sui_signature[1 + signature_bytes.len ..].* = material.public_key;

    return try encodeBase64Owned(allocator, &sui_signature);
}

fn parseKeyFromArray(
    allocator: std.mem.Allocator,
    contents: []const u8,
    selector: ?[]const u8,
) !?[]const u8 {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .array) return null;
    const need_selector = if (selector) |value| value.len > 0 else false;
    const selector_index = if (selector) |value| std.fmt.parseInt(usize, value, 10) catch null else null;

    for (parsed.value.array.items, 0..) |entry, index| {
        if (selector_index) |target_index| {
            if (index != target_index) continue;
        }

        if (entry == .string) {
            const raw_key = entry.string;
            if (raw_key.len == 0) continue;
            if (!need_selector or
                selector_index != null or
                std.mem.eql(u8, raw_key, selector.?) or
                try derivedSelectorMatchesRawKeyString(allocator, raw_key, selector.?))
            {
                return try allocator.dupe(u8, raw_key);
            }
            continue;
        }

        if (entry != .object) continue;
        const obj = entry.object;
        const candidate_key = rawKeyField(obj);
        if (candidate_key == null or candidate_key.?.len == 0) continue;

        if (!need_selector or selector_index != null or std.mem.eql(u8, candidate_key.?, selector.?)) {
            return try allocator.dupe(u8, candidate_key.?);
        }
        if (stringField(obj, "alias")) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (stringField(obj, "name")) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (addressField(obj)) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (publicKeyField(obj)) |value| {
            if (std.mem.eql(u8, value, selector.?)) return try allocator.dupe(u8, candidate_key.?);
        }
        if (try derivedSelectorMatchesObjectEntry(allocator, obj, selector.?)) {
            return try allocator.dupe(u8, candidate_key.?);
        }
    }

    return null;
}

pub fn parseFirstKey(allocator: std.mem.Allocator, contents: []const u8) !?[]const u8 {
    return parseKeyFromArray(allocator, contents, null);
}

pub fn parseKeyBySelector(allocator: std.mem.Allocator, contents: []const u8, selector: []const u8) !?[]const u8 {
    return parseKeyFromArray(allocator, contents, selector);
}

pub fn resolveSelectedKeyFromDefaultKeystore(allocator: std.mem.Allocator, selector: []const u8) !?[]const u8 {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return null;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(contents);

    return try parseKeyBySelector(allocator, contents, selector);
}

pub fn resolveFirstKeyFromDefaultKeystore(allocator: std.mem.Allocator) !?[]const u8 {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return null;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(contents);

    return try parseFirstKey(allocator, contents);
}

fn stringField(obj: std.json.ObjectMap, key_name: []const u8) ?[]const u8 {
    if (obj.get(key_name)) |value| {
        if (value == .string and value.string.len > 0) return value.string;
    }
    return null;
}

fn rawKeyField(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "privateKey")) |value| return value;
    if (stringField(obj, "private_key")) |value| return value;
    if (stringField(obj, "secretKey")) |value| return value;
    if (stringField(obj, "secret_key")) |value| return value;
    if (stringField(obj, "secret")) |value| return value;
    if (stringField(obj, "key")) |value| return value;
    if (stringField(obj, "value")) |value| return value;
    return null;
}

fn publicKeyField(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "publicKey")) |value| return value;
    if (stringField(obj, "public_key")) |value| return value;
    if (stringField(obj, "pubKey")) |value| return value;
    if (stringField(obj, "pub_key")) |value| return value;
    if (stringField(obj, "pub")) |value| return value;
    return null;
}

fn suiAddressField(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "suiAddress")) |value| return value;
    if (stringField(obj, "sui_address")) |value| return value;
    return null;
}

fn accountAddressField(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "accountAddress")) |value| return value;
    if (stringField(obj, "account_address")) |value| return value;
    return null;
}

fn walletAddressField(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "walletAddress")) |value| return value;
    if (stringField(obj, "wallet_address")) |value| return value;
    return null;
}

fn selectorFromObject(obj: std.json.ObjectMap) ?[]const u8 {
    return rawKeyField(obj);
}

fn addressField(obj: std.json.ObjectMap) ?[]const u8 {
    if (stringField(obj, "address")) |value| return value;
    if (accountAddressField(obj)) |value| return value;
    if (walletAddressField(obj)) |value| return value;
    return suiAddressField(obj);
}

fn maybeDeriveAddressFromSelectorString(
    allocator: std.mem.Allocator,
    selector: ?[]const u8,
) !?[]u8 {
    const value = selector orelse return null;
    return try maybeDeriveAddressFromRawKeyString(allocator, value);
}

fn maybeDerivePublicKeyFromSelectorString(
    allocator: std.mem.Allocator,
    selector: ?[]const u8,
) !?[]u8 {
    const value = selector orelse return null;
    return try maybeDerivePublicKeyFromRawKeyString(allocator, value);
}

fn derivedSelectorMatchesObjectEntry(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    selector: []const u8,
) !bool {
    if (try maybeDeriveAddressFromSelectorString(allocator, selectorFromObject(obj))) |derived_address| {
        defer allocator.free(derived_address);
        if (std.mem.eql(u8, derived_address, selector)) return true;
    }
    if (try maybeDerivePublicKeyFromSelectorString(allocator, selectorFromObject(obj))) |derived_public_key| {
        defer allocator.free(derived_public_key);
        if (std.mem.eql(u8, derived_public_key, selector)) return true;
    }
    return false;
}

fn derivedSelectorMatchesRawKeyString(
    allocator: std.mem.Allocator,
    raw_key: []const u8,
    selector: []const u8,
) !bool {
    if (try maybeDeriveAddressFromRawKeyString(allocator, raw_key)) |derived_address| {
        defer allocator.free(derived_address);
        if (std.mem.eql(u8, derived_address, selector)) return true;
    }
    if (try maybeDerivePublicKeyFromRawKeyString(allocator, raw_key)) |derived_public_key| {
        defer allocator.free(derived_public_key);
        if (std.mem.eql(u8, derived_public_key, selector)) return true;
    }
    return false;
}

fn dupeOptionalString(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    const slice = value orelse return null;
    return try allocator.dupe(u8, slice);
}

fn summarizeEntry(
    allocator: std.mem.Allocator,
    index: usize,
    entry: std.json.Value,
) !OwnedAccountEntry {
    return switch (entry) {
        .string => |value| blk: {
            var result = OwnedAccountEntry{
                .index = index,
                .kind = .raw_string,
            };
            errdefer result.deinit(allocator);
            result.selector = try allocator.dupe(u8, value);
            result.address = try maybeDeriveAddressFromRawKeyString(allocator, value);
            result.public_key = try maybeDerivePublicKeyFromRawKeyString(allocator, value);
            break :blk result;
        },
        .object => |obj| blk: {
            var result = OwnedAccountEntry{
                .index = index,
                .kind = .object,
            };
            errdefer result.deinit(allocator);

            const selector = selectorFromObject(obj);
            result.selector = try dupeOptionalString(allocator, selector);
            result.alias = try dupeOptionalString(allocator, stringField(obj, "alias"));
            result.name = try dupeOptionalString(allocator, stringField(obj, "name"));
            result.address = try dupeOptionalString(
                allocator,
                stringField(obj, "address") orelse accountAddressField(obj) orelse walletAddressField(obj),
            );
            result.sui_address = try dupeOptionalString(allocator, suiAddressField(obj));
            result.public_key = try dupeOptionalString(allocator, publicKeyField(obj));

            if (result.address == null and result.sui_address == null) {
                result.address = try maybeDeriveAddressFromSelectorString(allocator, selector);
            }
            if (result.public_key == null) {
                result.public_key = try maybeDerivePublicKeyFromSelectorString(allocator, selector);
            }

            break :blk result;
        },
        else => .{
            .index = index,
            .kind = .unsupported,
        },
    };
}

pub fn listAccountEntriesFromContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
) !OwnedAccountEntries {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) {
        return .{ .accounts = try allocator.alloc(OwnedAccountEntry, 0) };
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return error.InvalidCli;
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;

    const accounts = try allocator.alloc(OwnedAccountEntry, parsed.value.array.items.len);
    errdefer allocator.free(accounts);

    for (parsed.value.array.items, 0..) |entry, index| {
        accounts[index] = try summarizeEntry(allocator, index, entry);
    }

    return .{ .accounts = accounts };
}

pub fn listAccountEntriesFromDefaultKeystore(
    allocator: std.mem.Allocator,
) !OwnedAccountEntries {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return error.InvalidCli;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCli,
        else => return err,
    };
    defer allocator.free(contents);

    return try listAccountEntriesFromContents(allocator, contents);
}

pub fn getAccountEntryFromContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
    selector: []const u8,
) !?OwnedAccountEntry {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return error.InvalidCli;
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;

    if (findEntryIndexBySelector(parsed.value.array.items, selector)) |index| {
        return try summarizeEntry(allocator, index, parsed.value.array.items[index]);
    }

    for (parsed.value.array.items, 0..) |entry, index| {
        switch (entry) {
            .string => |value| {
                if (try derivedSelectorMatchesRawKeyString(allocator, value, selector)) {
                    return try summarizeEntry(allocator, index, entry);
                }
            },
            .object => |obj| {
                if (try derivedSelectorMatchesObjectEntry(allocator, obj, selector)) {
                    return try summarizeEntry(allocator, index, entry);
                }
            },
            else => {},
        }
    }

    return null;
}

pub fn getAccountEntryFromDefaultKeystore(
    allocator: std.mem.Allocator,
    selector: []const u8,
) !?OwnedAccountEntry {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return error.InvalidCli;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCli,
        else => return err,
    };
    defer allocator.free(contents);

    return try getAccountEntryFromContents(allocator, contents, selector);
}

pub fn runAccountQueryFromContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
    query: AccountQuery,
) !?AccountQueryResult {
    return switch (query) {
        .list => .{ .list = try listAccountEntriesFromContents(allocator, contents) },
        .info => |selector| if (try getAccountEntryFromContents(allocator, contents, selector)) |entry|
            .{ .info = entry }
        else
            null,
    };
}

pub fn runAccountQueryFromDefaultKeystore(
    allocator: std.mem.Allocator,
    query: AccountQuery,
) !?AccountQueryResult {
    return switch (query) {
        .list => .{ .list = try listAccountEntriesFromDefaultKeystore(allocator) },
        .info => |selector| if (try getAccountEntryFromDefaultKeystore(allocator, selector)) |entry|
            .{ .info = entry }
        else
            null,
    };
}

fn findEntryBySelector(entries: []const std.json.Value, selector: []const u8) ?std.json.Value {
    const index = findEntryIndexBySelector(entries, selector) orelse return null;
    return entries[index];
}

fn findEntryIndexBySelector(entries: []const std.json.Value, selector: []const u8) ?usize {
    const index_selector = std.fmt.parseInt(usize, selector, 10) catch null;
    if (index_selector) |target| {
        if (target >= entries.len) return null;
        return target;
    }

    for (entries, 0..) |entry, index| {
        switch (entry) {
            .string => |value| {
                if (std.mem.eql(u8, value, selector)) return index;
            },
            .object => |obj| {
                if (selectorFromObject(obj)) |value| {
                    if (std.mem.eql(u8, value, selector)) return index;
                }
                if (stringField(obj, "alias")) |value| {
                    if (std.mem.eql(u8, value, selector)) return index;
                }
                if (stringField(obj, "name")) |value| {
                    if (std.mem.eql(u8, value, selector)) return index;
                }
                if (addressField(obj)) |value| {
                    if (std.mem.eql(u8, value, selector)) return index;
                }
                if (publicKeyField(obj)) |value| {
                    if (std.mem.eql(u8, value, selector)) return index;
                }
            },
            else => {},
        }
    }

    return null;
}

pub fn resolveAddressFromKeystoreContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
    selector: []const u8,
) !?[]const u8 {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .array or parsed.value.array.items.len == 0) return null;

    const found = blk: {
        if (findEntryBySelector(parsed.value.array.items, selector)) |value| break :blk value;
        for (parsed.value.array.items) |entry| {
            switch (entry) {
                .string => |value| {
                    if (try derivedSelectorMatchesRawKeyString(allocator, value, selector)) break :blk entry;
                },
                .object => |obj| {
                    if (try derivedSelectorMatchesObjectEntry(allocator, obj, selector)) break :blk entry;
                },
                else => {},
            }
        }
        return null;
    };
    return switch (found) {
        .string => |value| try deriveAddressFromRawKeyString(allocator, value),
        .object => |obj| if (addressField(obj)) |value|
            try allocator.dupe(u8, value)
        else
            try maybeDeriveAddressFromSelectorString(allocator, selectorFromObject(obj)),
        else => null,
    };
}

pub fn resolveFirstAddressFromKeystoreContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
) !?[]const u8 {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return null;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .array or parsed.value.array.items.len == 0) return null;

    for (parsed.value.array.items) |entry| {
        switch (entry) {
            .string => |value| {
                if (try maybeDeriveAddressFromRawKeyString(allocator, value)) |address| return address;
            },
            .object => |obj| {
                if (addressField(obj)) |value| return try allocator.dupe(u8, value);
                if (try maybeDeriveAddressFromSelectorString(allocator, selectorFromObject(obj))) |address| return address;
            },
            else => {},
        }
    }

    return null;
}

pub fn resolveAddressBySelector(allocator: std.mem.Allocator, selector: []const u8) !?[]const u8 {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return null;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(contents);

    return try resolveAddressFromKeystoreContents(allocator, contents, selector);
}

pub fn resolveFirstAddressFromDefaultKeystore(allocator: std.mem.Allocator) !?[]const u8 {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return null;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(contents);

    return try resolveFirstAddressFromKeystoreContents(allocator, contents);
}

pub fn signTransactionBytesFromContents(
    allocator: std.mem.Allocator,
    tx_bytes_base64: []const u8,
    contents: []const u8,
    preparation: SignerPreparation,
) !OwnedSignatureList {
    const trimmed = std.mem.trim(u8, contents, " \n\r\t");
    if (trimmed.len == 0) return error.InvalidCli;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return error.InvalidCli;
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidCli;

    var items = std.ArrayList([]const u8){};
    defer items.deinit(allocator);

    if (preparation.signer_selectors.len > 0) {
        for (preparation.signer_selectors) |selector| {
            if (selector.len == 0) continue;
            const raw_key = try parseKeyBySelector(allocator, contents, selector) orelse return error.InvalidCli;
            defer allocator.free(raw_key);
            const signature = try signTransactionBytesWithRawKey(allocator, raw_key, tx_bytes_base64);
            try items.append(allocator, signature);
        }
    } else if (preparation.from_keystore) {
        const raw_key = try parseFirstKey(allocator, contents) orelse return error.InvalidCli;
        defer allocator.free(raw_key);
        const signature = try signTransactionBytesWithRawKey(allocator, raw_key, tx_bytes_base64);
        try items.append(allocator, signature);
    }

    return .{ .items = try items.toOwnedSlice(allocator) };
}

pub fn signTransactionBytesFromDefaultKeystore(
    allocator: std.mem.Allocator,
    tx_bytes_base64: []const u8,
    preparation: SignerPreparation,
) !OwnedSignatureList {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return error.InvalidCli;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCli,
        else => return err,
    };
    defer allocator.free(contents);

    return try signTransactionBytesFromContents(allocator, tx_bytes_base64, contents, preparation);
}

fn resolveSenderFromContents(
    allocator: std.mem.Allocator,
    contents: []const u8,
    selector: []const u8,
) !?struct {
    value: []const u8,
    owned: bool,
} {
    if (selector.len == 0) return null;
    if (std.mem.startsWith(u8, selector, "0x")) {
        return .{ .value = selector, .owned = false };
    }

    if (try resolveAddressFromKeystoreContents(allocator, contents, selector)) |value| {
        return .{ .value = value, .owned = true };
    }
    return null;
}

fn signaturesContain(signatures: []const []const u8, value: []const u8) bool {
    for (signatures) |signature| {
        if (std.mem.eql(u8, signature, value)) return true;
    }
    return false;
}

pub fn prepareProgrammaticRequestFromContents(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    contents: []const u8,
    preparation: SignerPreparation,
) !PreparedProgrammaticRequest {
    var prepared = PreparedProgrammaticRequest{ .request = base_request };
    errdefer prepared.deinit(allocator);

    if (base_request.sender) |sender| {
        if (sender.len > 0) {
            const resolved_sender = try resolveSenderFromContents(allocator, contents, sender) orelse return error.InvalidCli;
            if (resolved_sender.owned) prepared.owned_sender = resolved_sender.value;
            prepared.request.sender = resolved_sender.value;
        }
    } else if (preparation.infer_sender_from_signers and preparation.signer_selectors.len > 0) {
        var has_resolver_input = false;
        for (preparation.signer_selectors) |selector| {
            if (selector.len == 0) continue;
            has_resolver_input = true;
            const resolved_sender = try resolveSenderFromContents(allocator, contents, selector) orelse continue;
            if (resolved_sender.owned) prepared.owned_sender = resolved_sender.value;
            prepared.request.sender = resolved_sender.value;
            break;
        }
        if (has_resolver_input and prepared.request.sender == null) return error.InvalidCli;
    } else if (preparation.from_keystore) {
        if (try resolveFirstAddressFromKeystoreContents(allocator, contents)) |value| {
            prepared.owned_sender = value;
            prepared.request.sender = value;
        }
    }

    if (preparation.signer_selectors.len == 0 and (!preparation.from_keystore or base_request.signatures.len > 0)) {
        return prepared;
    }

    if (base_request.signatures.len > 0) {
        try prepared.combined_signatures.appendSlice(allocator, base_request.signatures);
    }

    if (preparation.signer_selectors.len > 0) {
        for (preparation.signer_selectors) |selector| {
            if (selector.len == 0) continue;
            const selector_key = try parseKeyBySelector(allocator, contents, selector) orelse return error.InvalidCli;
            if (signaturesContain(prepared.combined_signatures.items, selector_key)) {
                allocator.free(selector_key);
                continue;
            }
            try prepared.combined_signatures.append(allocator, selector_key);
            try prepared.owned_signatures.append(allocator, selector_key);
        }
    } else if (preparation.from_keystore and prepared.combined_signatures.items.len == 0) {
        const key = try parseFirstKey(allocator, contents) orelse return error.InvalidCli;
        try prepared.combined_signatures.append(allocator, key);
        try prepared.owned_signatures.append(allocator, key);
    }

    prepared.request.signatures = prepared.combined_signatures.items;
    return prepared;
}

pub fn prepareProgrammaticRequestFromDefaultKeystore(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    preparation: SignerPreparation,
) !PreparedProgrammaticRequest {
    const keystore_path = try resolveDefaultSuiKeystorePath(allocator);
    if (keystore_path == null) return error.InvalidCli;
    defer allocator.free(keystore_path.?);

    const contents = std.fs.cwd().readFileAlloc(allocator, keystore_path.?, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.InvalidCli,
        else => return err,
    };
    defer allocator.free(contents);

    return try prepareProgrammaticRequestFromContents(allocator, base_request, contents, preparation);
}

pub fn prepareResolvedProgrammaticRequestFromContents(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    contents: []const u8,
    preparation: SignerPreparation,
) !tx_builder.PreparedProgrammaticTxRequest {
    var prepared = try prepareProgrammaticRequestFromContents(allocator, base_request, contents, preparation);
    defer prepared.deinit(allocator);
    return try prepared.request.prepare(allocator);
}

pub fn prepareResolvedProgrammaticRequestFromDefaultKeystore(
    allocator: std.mem.Allocator,
    base_request: tx_builder.ProgrammaticTxRequest,
    preparation: SignerPreparation,
) !tx_builder.PreparedProgrammaticTxRequest {
    var prepared = try prepareProgrammaticRequestFromDefaultKeystore(allocator, base_request, preparation);
    defer prepared.deinit(allocator);
    return try prepared.request.prepare(allocator);
}

test "prepareProgrammaticRequestFromContents resolves sender and signatures from signers" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xbuilder", prepared.request.sender.?);
    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}

test "prepareProgrammaticRequestFromContents appends first key when requested" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .from_keystore = true },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}

test "prepareProgrammaticRequestFromContents infers sender from first keystore address" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .command_items = &.{
                    "{\"kind\":\"TransferObjects\",\"objects\":[\"0xcoin\"],\"address\":\"0xreceiver\"}",
                },
            },
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .from_keystore = true },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqualStrings("0xbuilder", prepared.request.sender.?);
    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}

test "prepareProgrammaticRequestFromContents preserves existing signatures without duplication" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
            .signatures = &.{"sig-base"},
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer prepared.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-base", prepared.request.signatures[0]);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[1]);
}

test "prepareResolvedProgrammaticRequestFromContents normalizes commands and signer-backed data" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prepared = try prepareResolvedProgrammaticRequestFromContents(
        allocator,
        .{
            .source = .{
                .move_call = .{
                    .package_id = "0x2",
                    .module = "counter",
                    .function_name = "increment",
                    .type_args = "[]",
                    .arguments = "[\"0xabc\"]",
                },
            },
        },
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .signer_selectors = &.{"builder"} },
    );
    defer prepared.deinit(allocator);

    try testing.expect(prepared.request.source.commands_json != null);
    try testing.expectEqualStrings("0xbuilder", prepared.request.sender.?);
    try testing.expectEqual(@as(usize, 1), prepared.request.signatures.len);
    try testing.expectEqualStrings("sig-builder", prepared.request.signatures[0]);
}

test "resolveAddressFromKeystoreContents derives addresses from raw key entries" {
    const testing = std.testing;

    const seed = [_]u8{0x11} ** 32;
    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);

    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    var hasher = std.crypto.hash.blake2.Blake2b256.init(.{});
    hasher.update(&.{ed25519_flag});
    const public_key = keypair.public_key.toBytes();
    hasher.update(&public_key);
    var address_bytes: [32]u8 = undefined;
    hasher.final(&address_bytes);

    const expected_address = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&address_bytes)});
    defer testing.allocator.free(expected_address);

    const contents = try std.fmt.allocPrint(testing.allocator, "[\"{s}\"]", .{encoded_key});
    defer testing.allocator.free(contents);

    const resolved = try resolveAddressFromKeystoreContents(testing.allocator, contents, encoded_key) orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(resolved);
    try testing.expectEqualStrings(expected_address, resolved);

    var listed = try listAccountEntriesFromContents(testing.allocator, contents);
    defer listed.deinit(testing.allocator);
    try testing.expectEqualStrings(expected_address, listed.accounts[0].address.?);
}

test "signTransactionBytesFromContents signs transaction bytes from raw key entries" {
    const testing = std.testing;

    const seed = [_]u8{0x42} ** 32;
    const keypair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);

    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const contents = try std.fmt.allocPrint(testing.allocator, "[\"{s}\"]", .{encoded_key});
    defer testing.allocator.free(contents);

    const tx_bytes = try encodeBase64Owned(testing.allocator, &[_]u8{ 1, 2, 3, 4 });
    defer testing.allocator.free(tx_bytes);

    var signed = try signTransactionBytesFromContents(
        testing.allocator,
        tx_bytes,
        contents,
        .{ .signer_selectors = &.{encoded_key} },
    );
    defer signed.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), signed.items.len);

    const signature_len = try std.base64.standard.Decoder.calcSizeForSlice(signed.items[0]);
    try testing.expectEqual(@as(usize, 97), signature_len);

    var signature_bytes: [97]u8 = undefined;
    try std.base64.standard.Decoder.decode(&signature_bytes, signed.items[0]);
    try testing.expectEqual(ed25519_flag, signature_bytes[0]);

    var tx_decoded: [4]u8 = undefined;
    try std.base64.standard.Decoder.decode(&tx_decoded, tx_bytes);

    var digest_hasher = std.crypto.hash.blake2.Blake2b256.init(.{});
    digest_hasher.update(&sui_transaction_intent);
    digest_hasher.update(&tx_decoded);
    var digest: [32]u8 = undefined;
    digest_hasher.final(&digest);

    const signature = std.crypto.sign.Ed25519.Signature.fromBytes(signature_bytes[1..65].*);
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(signature_bytes[65..97].*);
    try signature.verify(&digest, public_key);

    try testing.expectEqualSlices(u8, &keypair.public_key.toBytes(), &signature_bytes[65..97]);
}

test "listAccountEntriesFromContents summarizes mixed keystore entries" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var accounts = try listAccountEntriesFromContents(
        allocator,
        \\[
        \\  "raw-selector",
        \\  {
        \\    "alias":"builder",
        \\    "privateKey":"sig-builder",
        \\    "address":"0xbuilder",
        \\    "publicKey":"pub-builder"
        \\  }
        \\]
    );
    defer accounts.deinit(allocator);

    try testing.expectEqual(@as(usize, 2), accounts.accounts.len);
    try testing.expectEqual(AccountEntryKind.raw_string, accounts.accounts[0].kind);
    try testing.expectEqualStrings("raw-selector", accounts.accounts[0].selector.?);
    try testing.expectEqual(AccountEntryKind.object, accounts.accounts[1].kind);
    try testing.expectEqualStrings("sig-builder", accounts.accounts[1].selector.?);
    try testing.expectEqualStrings("builder", accounts.accounts[1].alias.?);
    try testing.expectEqualStrings("0xbuilder", accounts.accounts[1].address.?);
    try testing.expectEqualStrings("pub-builder", accounts.accounts[1].public_key.?);
}

test "listAccountEntriesFromContents derives address and public key for object entries with raw keys" {
    const testing = std.testing;

    const seed = [_]u8{0x21} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const expected_address = try deriveAddressFromRawKeyString(testing.allocator, encoded_key);
    defer testing.allocator.free(expected_address);
    const expected_public_key = (try maybeDerivePublicKeyFromRawKeyString(testing.allocator, encoded_key)).?;
    defer testing.allocator.free(expected_public_key);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[{{\"alias\":\"derived\",\"privateKey\":\"{s}\"}}]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    var accounts = try listAccountEntriesFromContents(testing.allocator, contents);
    defer accounts.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), accounts.accounts.len);
    try testing.expectEqual(AccountEntryKind.object, accounts.accounts[0].kind);
    try testing.expectEqualStrings("derived", accounts.accounts[0].alias.?);
    try testing.expectEqualStrings(expected_address, accounts.accounts[0].address.?);
    try testing.expectEqualStrings(expected_public_key, accounts.accounts[0].public_key.?);
}

test "getAccountEntryFromContents resolves aliases and indexes" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const contents =
        \\[
        \\  {"alias":"first","privateKey":"sig-first","address":"0xfirst"},
        \\  {"alias":"second","privateKey":"sig-second","address":"0xsecond"}
        \\]
    ;

    var by_alias = (try getAccountEntryFromContents(allocator, contents, "second")).?;
    defer by_alias.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), by_alias.index);
    try testing.expectEqualStrings("sig-second", by_alias.selector.?);
    try testing.expectEqualStrings("0xsecond", by_alias.address.?);

    var by_index = (try getAccountEntryFromContents(allocator, contents, "0")).?;
    defer by_index.deinit(allocator);
    try testing.expectEqual(@as(usize, 0), by_index.index);
    try testing.expectEqualStrings("sig-first", by_index.selector.?);
}

test "object keystore entries can be selected by derived address" {
    const testing = std.testing;

    const seed = [_]u8{0x22} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const derived_address = try deriveAddressFromRawKeyString(testing.allocator, encoded_key);
    defer testing.allocator.free(derived_address);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[{{\"privateKey\":\"{s}\"}}]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    const resolved_address = try resolveAddressFromKeystoreContents(testing.allocator, contents, derived_address) orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(resolved_address);
    try testing.expectEqualStrings(derived_address, resolved_address);

    const selected_key = try parseKeyBySelector(testing.allocator, contents, derived_address) orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_key);
    try testing.expectEqualStrings(encoded_key, selected_key);

    var entry = (try getAccountEntryFromContents(testing.allocator, contents, derived_address)).?;
    defer entry.deinit(testing.allocator);
    try testing.expectEqualStrings(derived_address, entry.address.?);
}

test "raw string keystore entries can be selected by derived address and public key" {
    const testing = std.testing;

    const seed = [_]u8{0x23} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const derived_address = try deriveAddressFromRawKeyString(testing.allocator, encoded_key);
    defer testing.allocator.free(derived_address);
    const derived_public_key = (try maybeDerivePublicKeyFromRawKeyString(testing.allocator, encoded_key)).?;
    defer testing.allocator.free(derived_public_key);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[\"{s}\"]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    const selected_by_address = try parseKeyBySelector(testing.allocator, contents, derived_address) orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_by_address);
    try testing.expectEqualStrings(encoded_key, selected_by_address);

    const selected_by_public_key = try parseKeyBySelector(testing.allocator, contents, derived_public_key) orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_by_public_key);
    try testing.expectEqualStrings(encoded_key, selected_by_public_key);

    const resolved_address = try resolveAddressFromKeystoreContents(testing.allocator, contents, derived_address) orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(resolved_address);
    try testing.expectEqualStrings(derived_address, resolved_address);

    var entry = (try getAccountEntryFromContents(testing.allocator, contents, derived_public_key)).?;
    defer entry.deinit(testing.allocator);
    try testing.expectEqualStrings(derived_address, entry.address.?);
    try testing.expectEqualStrings(derived_public_key, entry.public_key.?);
}

test "listAccountEntriesFromContents supports snake_case object metadata" {
    const testing = std.testing;

    const seed = [_]u8{0x24} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[{{\"alias\":\"snake\",\"private_key\":\"{s}\",\"sui_address\":\"0xsnake\",\"public_key\":\"pub-snake\"}}]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    var accounts = try listAccountEntriesFromContents(testing.allocator, contents);
    defer accounts.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), accounts.accounts.len);
    try testing.expectEqualStrings(encoded_key, accounts.accounts[0].selector.?);
    try testing.expectEqualStrings("0xsnake", accounts.accounts[0].sui_address.?);
    try testing.expectEqualStrings("pub-snake", accounts.accounts[0].public_key.?);
}

test "snake_case object keystore entries can be selected by public key" {
    const testing = std.testing;

    const seed = [_]u8{0x25} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[{{\"private_key\":\"{s}\",\"public_key\":\"pub-snake\",\"sui_address\":\"0xsnake-public\"}}]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    const selected_key = try parseKeyBySelector(testing.allocator, contents, "pub-snake") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_key);
    try testing.expectEqualStrings(encoded_key, selected_key);

    var entry = (try getAccountEntryFromContents(testing.allocator, contents, "pub-snake")).?;
    defer entry.deinit(testing.allocator);
    try testing.expectEqualStrings("pub-snake", entry.public_key.?);
    try testing.expectEqualStrings("0xsnake-public", entry.sui_address.?);

    const resolved_address = try resolveAddressFromKeystoreContents(testing.allocator, contents, "pub-snake") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(resolved_address);
    try testing.expectEqualStrings("0xsnake-public", resolved_address);
}

test "listAccountEntriesFromContents supports alternate object metadata aliases" {
    const testing = std.testing;

    const seed = [_]u8{0x26} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[{{\"alias\":\"alt\",\"secret_key\":\"{s}\",\"account_address\":\"0xalt-address\",\"pub_key\":\"pub-alt\"}}]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    var accounts = try listAccountEntriesFromContents(testing.allocator, contents);
    defer accounts.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), accounts.accounts.len);
    try testing.expectEqualStrings(encoded_key, accounts.accounts[0].selector.?);
    try testing.expectEqualStrings("0xalt-address", accounts.accounts[0].address.?);
    try testing.expectEqualStrings("pub-alt", accounts.accounts[0].public_key.?);
}

test "alternate object keystore entries can be selected by account address and pub key" {
    const testing = std.testing;

    const seed = [_]u8{0x27} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[{{\"secretKey\":\"{s}\",\"accountAddress\":\"0xaccount-alt\",\"pubKey\":\"pub-alt-select\"}}]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    const selected_by_address = try parseKeyBySelector(testing.allocator, contents, "0xaccount-alt") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_by_address);
    try testing.expectEqualStrings(encoded_key, selected_by_address);

    const selected_by_public_key = try parseKeyBySelector(testing.allocator, contents, "pub-alt-select") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_by_public_key);
    try testing.expectEqualStrings(encoded_key, selected_by_public_key);

    var entry = (try getAccountEntryFromContents(testing.allocator, contents, "pub-alt-select")).?;
    defer entry.deinit(testing.allocator);
    try testing.expectEqualStrings("0xaccount-alt", entry.address.?);
    try testing.expectEqualStrings("pub-alt-select", entry.public_key.?);

    const resolved_address = try resolveAddressFromKeystoreContents(testing.allocator, contents, "pub-alt-select") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(resolved_address);
    try testing.expectEqualStrings("0xaccount-alt", resolved_address);
}

test "wallet metadata aliases support selector resolution and summaries" {
    const testing = std.testing;

    const seed = [_]u8{0x28} ** 32;
    var encoded_key_bytes: [33]u8 = undefined;
    encoded_key_bytes[0] = ed25519_flag;
    encoded_key_bytes[1..].* = seed;
    const encoded_key = try encodeBase64Owned(testing.allocator, &encoded_key_bytes);
    defer testing.allocator.free(encoded_key);

    const contents = try std.fmt.allocPrint(
        testing.allocator,
        "[{{\"alias\":\"wallet\",\"secret\":\"{s}\",\"wallet_address\":\"0xwallet-alt\",\"pub\":\"pub-wallet-alt\"}}]",
        .{encoded_key},
    );
    defer testing.allocator.free(contents);

    const selected_by_wallet = try parseKeyBySelector(testing.allocator, contents, "0xwallet-alt") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_by_wallet);
    try testing.expectEqualStrings(encoded_key, selected_by_wallet);

    const selected_by_pub = try parseKeyBySelector(testing.allocator, contents, "pub-wallet-alt") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(selected_by_pub);
    try testing.expectEqualStrings(encoded_key, selected_by_pub);

    var accounts = try listAccountEntriesFromContents(testing.allocator, contents);
    defer accounts.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), accounts.accounts.len);
    try testing.expectEqualStrings("0xwallet-alt", accounts.accounts[0].address.?);
    try testing.expectEqualStrings("pub-wallet-alt", accounts.accounts[0].public_key.?);

    const resolved_address = try resolveAddressFromKeystoreContents(testing.allocator, contents, "pub-wallet-alt") orelse return error.TestUnexpectedResult;
    defer testing.allocator.free(resolved_address);
    try testing.expectEqualStrings("0xwallet-alt", resolved_address);
}

test "listAccountEntriesFromContents rejects non-array keystore data" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(error.InvalidCli, listAccountEntriesFromContents(allocator, "{}"));
}

test "runAccountQueryFromContents returns list and info results" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const contents =
        \\[
        \\  "raw-selector",
        \\  {"alias":"builder","privateKey":"sig-builder","address":"0xbuilder"}
        \\]
    ;

    var list_result = (try runAccountQueryFromContents(allocator, contents, .list)).?;
    defer list_result.deinit(allocator);
    try testing.expectEqual(@as(usize, 2), list_result.list.accounts.len);
    try testing.expectEqualStrings("raw-selector", list_result.list.accounts[0].selector.?);

    var info_result = (try runAccountQueryFromContents(allocator, contents, .{ .info = "builder" })).?;
    defer info_result.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), info_result.info.index);
    try testing.expectEqualStrings("sig-builder", info_result.info.selector.?);
    try testing.expectEqualStrings("0xbuilder", info_result.info.address.?);
}

test "runAccountQueryFromContents returns null for missing info selectors" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try runAccountQueryFromContents(
        allocator,
        "[{\"alias\":\"builder\",\"privateKey\":\"sig-builder\",\"address\":\"0xbuilder\"}]",
        .{ .info = "missing" },
    );
    try testing.expect(result == null);
}
