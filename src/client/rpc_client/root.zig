/// client/rpc_client/root.zig - RPC client module root
///
/// This module provides the RPC client for interacting with Sui nodes.

const std = @import("std");

// Import sub-modules
const errors = @import("error.zig");
pub const constants = @import("constants.zig");
pub const utils = @import("utils.zig");
pub const client_core = @import("client_core.zig");
pub const query = @import("query.zig");
pub const transaction = @import("transaction.zig");
pub const object = @import("object.zig");
pub const event = @import("event.zig");
pub const move_module = @import("move.zig");

// Re-export commonly used types
pub const ClientError = errors.ClientError;
pub const RpcErrorDetail = errors.RpcErrorDetail;
pub const TransportStats = errors.TransportStats;
pub const ResultWithError = errors.ResultWithError;
pub const parseErrorFromJson = errors.parseErrorFromJson;

// Re-export constants
pub const default_sui_coin_type = constants.default_sui_coin_type;
pub const default_mainnet_endpoint = constants.default_mainnet_endpoint;
pub const default_testnet_endpoint = constants.default_testnet_endpoint;
pub const default_devnet_endpoint = constants.default_devnet_endpoint;
pub const default_request_timeout_ms = constants.default_request_timeout_ms;
pub const mist_per_sui = constants.mist_per_sui;
pub const mistToSui = constants.mistToSui;
pub const suiToMist = constants.suiToMist;

// Re-export core client
pub const SuiRpcClient = client_core.SuiRpcClient;
pub const RpcRequest = client_core.RpcRequest;
pub const RequestSender = client_core.RequestSender;
pub const RequestSenderCallback = client_core.RequestSenderCallback;

// Re-export query types and functions
pub const Balance = query.Balance;
pub const DynamicField = query.DynamicField;
pub const DynamicFieldPage = query.DynamicFieldPage;
pub const getBalance = query.getBalance;
pub const getAllBalances = query.getAllBalances;
pub const getObject = query.getObject;
pub const getReferenceGasPrice = query.getReferenceGasPrice;
pub const getDynamicFields = query.getDynamicFields;

// Re-export transaction types and functions
pub const SimulationResult = transaction.SimulationResult;
pub const ExecutionResult = transaction.ExecutionResult;
pub const TransactionEffects = transaction.TransactionEffects;
pub const TransactionStatus = transaction.TransactionStatus;
pub const GasCostSummary = transaction.GasCostSummary;
pub const Event = transaction.Event;
pub const ObjectChange = transaction.ObjectChange;
pub const BalanceChange = transaction.BalanceChange;
pub const SimulationOptions = transaction.SimulationOptions;
pub const ExecutionOptions = transaction.ExecutionOptions;
pub const simulateTransaction = transaction.simulateTransaction;
pub const executeTransaction = transaction.executeTransaction;

// Re-export object types and functions
pub const Object = object.Object;
pub const ObjectDataOptions = object.ObjectDataOptions;
pub const ObjectQuery = object.ObjectQuery;
pub const ObjectFilter = object.ObjectFilter;
pub const ObjectPage = object.ObjectPage;
pub const Owner = object.Owner;
pub const OwnerType = object.OwnerType;
pub const getMultipleObjects = object.getMultipleObjects;
pub const getOwnedObjects = object.getOwnedObjects;

// Re-export event types and functions
pub const SuiEvent = event.SuiEvent;
pub const EventId = event.EventId;
pub const EventFilter = event.EventFilter;
pub const EventPage = event.EventPage;
pub const EventSubscription = event.EventSubscription;
pub const queryEvents = event.queryEvents;
pub const subscribeToEvents = event.subscribeToEvents;

// Re-export move module types and functions
pub const NormalizedMoveModule = move_module.NormalizedMoveModule;
pub const NormalizedMoveStruct = move_module.NormalizedMoveStruct;
pub const NormalizedMoveFunction = move_module.NormalizedMoveFunction;
pub const MoveField = move_module.MoveField;
pub const MoveTypeSignature = move_module.MoveTypeSignature;
pub const MoveTypeTag = move_module.MoveTypeTag;
pub const MoveVisibility = move_module.MoveVisibility;
pub const getNormalizedMoveModule = move_module.getNormalizedMoveModule;

// Re-export utilities
pub const dupeOptionalString = utils.dupeOptionalString;
pub const dupeStringList = utils.dupeStringList;
pub const freeStringList = utils.freeStringList;
pub const parseJsonResultExists = utils.parseJsonResultExists;
pub const extractExecuteDigest = utils.extractExecuteDigest;
pub const isValidHex = utils.isValidHex;
pub const isValidAddress = utils.isValidAddress;
pub const isValidObjectId = utils.isValidObjectId;

// ============================================================
// Tests
// ============================================================

test "rpc_client module imports successfully" {
    _ = errors;
    _ = constants;
    _ = utils;
    _ = client_core;
    _ = query;
    _ = transaction;
    _ = object;
    _ = event;
    _ = move_module;
}

// Import integration tests
comptime {
    _ = @import("integration_test.zig");
}

test "re-exports work correctly" {
    const testing = std.testing;

    // Test error type
    const err: ClientError = errors.ClientError.Timeout;
    try testing.expectEqual(errors.ClientError.Timeout, err);

    // Test constant
    try testing.expectEqual(@as(u64, 1_000_000_000), mist_per_sui);

    // Test utility function exists
    _ = isValidAddress;

    // Test core client exists
    _ = SuiRpcClient;

    // Test query types exist
    _ = Balance;
    _ = Object;

    // Test transaction types exist
    _ = SimulationResult;
    _ = ExecutionResult;

    // Test object types exist
    _ = Object;
    _ = Owner;

    // Test event types exist
    _ = SuiEvent;
    _ = EventFilter;

    // Test move module types exist
    _ = NormalizedMoveModule;
    _ = MoveVisibility;
}
