const std = @import("std");

pub const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 2 };
pub const default_rpc_url = "https://fullnode.mainnet.sui.io:443";

pub const rpc_client = @import("./client/rpc_client/client.zig");
pub const SuiRpcClient = rpc_client.SuiRpcClient;
pub const ClientError = rpc_client.ClientError;
pub const RpcErrorDetail = rpc_client.RpcErrorDetail;
pub const tx_builder = @import("./tx_builder.zig");
pub const tx_request_builder = @import("./tx_request_builder.zig");
pub const keystore = @import("./keystore.zig");
