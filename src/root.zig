const std = @import("std");

pub const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 2 };
pub const default_rpc_url = "https://fullnode.mainnet.sui.io:443";

// Legacy RPC client (44,708 lines - full featured)
pub const rpc_client = @import("./client/rpc_client/client.zig");
pub const SuiRpcClient = rpc_client.SuiRpcClient;
pub const ClientError = rpc_client.ClientError;
pub const RpcErrorDetail = rpc_client.RpcErrorDetail;

// New modular RPC client (128K lines - actively developed)
pub const rpc_client_new = @import("./client/rpc_client/root.zig");
pub const tx_builder = @import("./tx_builder.zig");
pub const tx_result = @import("./tx_result.zig");
pub const inspect_result = @import("./inspect_result.zig");
pub const artifact_result = @import("./artifact_result.zig");
pub const object_result = @import("./object_result.zig");
pub const event_result = @import("./event_result.zig");
pub const owned_object_result = @import("./owned_object_result.zig");
pub const dynamic_field_result = @import("./dynamic_field_result.zig");
pub const coin_result = @import("./coin_result.zig");
pub const move_result = @import("./move_result.zig");
pub const tx_request_builder = @import("./tx_request_builder.zig");
pub const ptb_bytes_builder = @import("./ptb_bytes_builder.zig");
pub const keystore = @import("./keystore.zig");
pub const package_preset = @import("./package_preset.zig");
pub const built_in_object_preset = @import("./builtin_object_preset.zig");
pub const protocol_object_registry = @import("./protocol_object_registry.zig");
pub const object_preset = @import("./object_preset.zig");

// RPC adapter for gradual migration
pub const rpc_adapter = @import("./rpc_adapter.zig");

// GraphQL client for advanced queries
pub const graphql = @import("./graphql/root.zig");

// Plugin system for extensibility
pub const plugin = @import("./plugin/root.zig");
