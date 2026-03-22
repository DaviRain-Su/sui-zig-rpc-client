// Browser WebAuthn Bridge with Local HTTP Server
// WebAuthn requires HTTPS or localhost

const std = @import("std");
const Allocator = std.mem.Allocator;
const net = std.net;

const SERVER_PORT = 8765;
const SERVER_HOST = "127.0.0.1";

/// Simple HTTP server for WebAuthn
pub const WebAuthnServer = struct {
    allocator: Allocator,
    port: u16,
    server: net.Server,
    running: bool,
    response_data: ?[]const u8,
    response_received: std.Thread.ResetEvent,

    const Self = @This();

    pub fn init(allocator: Allocator, port: u16) !Self {
        const address = try net.Address.parseIp4(SERVER_HOST, port);
        const server = try net.Address.listen(address, .{
            .reuse_address = true,
        });

        return Self{
            .allocator = allocator,
            .port = port,
            .server = server,
            .running = false,
            .response_data = null,
            .response_received = std.Thread.ResetEvent{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
        if (self.response_data) |data| {
            self.allocator.free(data);
        }
    }

    /// Start server in background thread
    pub fn start(self: *Self, html_content: []const u8) !void {
        self.running = true;

        // Spawn server thread
        const thread = try std.Thread.spawn(.{}, serverLoop, .{ self, html_content });
        thread.detach();
    }

    fn serverLoop(self: *Self, html_content: []const u8) !void {
        std.log.info("WebAuthn server listening on http://localhost:{d}", .{self.port});

        while (self.running) {
            const conn = self.server.accept() catch |err| {
                if (self.running) {
                    std.log.err("Accept error: {s}", .{@errorName(err)});
                }
                continue;
            };

            // Handle connection
            self.handleConnection(conn, html_content) catch |err| {
                std.log.err("Connection error: {s}", .{@errorName(err)});
            };
        }
    }

    fn handleConnection(self: *Self, conn: net.Server.Connection, html_content: []const u8) !void {
        defer conn.stream.close();

        var buf: [4096]u8 = undefined;
        const n = try conn.stream.read(&buf);
        const request = buf[0..n];

        // Parse request line
        if (std.mem.startsWith(u8, request, "GET / ")) {
            // Serve HTML page
            const response = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 200 OK\r\n" ++
                "Content-Type: text/html\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Access-Control-Allow-Origin: *\r\n" ++
                "\r\n" ++
                "{s}", .{ html_content.len, html_content });
            defer self.allocator.free(response);

            _ = try conn.stream.write(response);
        } else if (std.mem.startsWith(u8, request, "POST /credential ")) {
            // Receive credential data
            const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse {
                _ = try conn.stream.write("HTTP/1.1 400 Bad Request\r\n\r\n");
                return;
            };
            const body = request[body_start + 4 ..];

            self.response_data = try self.allocator.dupe(u8, body);
            self.response_received.set();

            _ = try conn.stream.write("HTTP/1.1 200 OK\r\n" ++
                "Content-Type: application/json\r\n" ++
                "Access-Control-Allow-Origin: *\r\n" ++
                "\r\n" ++
                "{\"status\":\"ok\"}");
            self.running = false;
        } else if (std.mem.startsWith(u8, request, "OPTIONS ")) {
            // CORS preflight
            _ = try conn.stream.write("HTTP/1.1 200 OK\r\n" ++
                "Access-Control-Allow-Origin: *\r\n" ++
                "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n" ++
                "Access-Control-Allow-Headers: Content-Type\r\n" ++
                "\r\n");
        } else {
            _ = try conn.stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
        }
    }

    pub fn waitForResponse(self: *Self, timeout_ms: u64) ![]const u8 {
        self.response_received.timedWait(timeout_ms * std.time.ns_per_ms) catch {
            return error.Timeout;
        };

        return self.response_data orelse error.NoResponse;
    }

    pub fn stop(self: *Self) void {
        self.running = false;
    }
};

/// Create WebAuthn credential via browser with localhost server
pub fn createCredentialInBrowser(
    allocator: Allocator,
    rp_id: []const u8,
    user_name: []const u8,
    output_dir: []const u8,
) !Credential {
    _ = output_dir;

    // Generate request ID
    var request_id: [16]u8 = undefined;
    std.crypto.random.bytes(&request_id);
    const request_id_hex = try std.fmt.allocPrint(allocator, "{x}", .{request_id});
    defer allocator.free(request_id_hex);

    // Generate HTML
    const html = try generateWebAuthnHtml(allocator, request_id_hex, rp_id, user_name, SERVER_PORT);
    defer allocator.free(html);

    // Start server
    var server = try WebAuthnServer.init(allocator, SERVER_PORT);
    defer server.deinit();

    try server.start(html);

    // Open browser
    const url = try std.fmt.allocPrint(allocator, "http://localhost:{d}", .{SERVER_PORT});
    defer allocator.free(url);

    std.log.info("Opening browser: {s}", .{url});
    std.log.info("", .{});
    std.log.info("Please:", .{});
    std.log.info("  1. Click 'Create Passkey' in the browser", .{});
    std.log.info("  2. Authenticate with Touch ID / YubiKey", .{});
    std.log.info("  3. Wait for confirmation", .{});
    std.log.info("", .{});

    try openBrowser(url);

    // Wait for response
    std.log.info("Waiting for browser response (timeout: 2 minutes)...", .{});
    const response = try server.waitForResponse(120000);
    defer allocator.free(response);

    std.log.info("Response received!", .{});

    // Parse credential
    return try parseCredential(allocator, response);
}

fn generateWebAuthnHtml(
    allocator: Allocator,
    request_id: []const u8,
    rp_id: []const u8,
    user_name: []const u8,
    port: u16,
) ![]const u8 {
    var buf: [32768]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // HTML head
    try writer.writeAll("<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Sui WebAuthn</title>");
    try writer.writeAll("<style>");
    try writer.writeAll("body{font-family:-apple-system,sans-serif;max-width:600px;margin:50px auto;padding:20px;");
    try writer.writeAll("background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh}");
    try writer.writeAll(".container{background:white;padding:40px;border-radius:20px;box-shadow:0 20px 60px rgba(0,0,0,0.3)}");
    try writer.writeAll("h1{color:#333;margin-bottom:10px}");
    try writer.writeAll("button{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;");
    try writer.writeAll("padding:18px 40px;border:none;border-radius:10px;cursor:pointer;font-size:18px;width:100%}");
    try writer.writeAll(".status{margin-top:20px;padding:15px;border-radius:10px}");
    try writer.writeAll(".success{background:#d4edda;color:#155724}");
    try writer.writeAll(".error{background:#f8d7da;color:#721c24}");
    try writer.writeAll(".pending{background:#fff3cd;color:#856404}");
    try writer.writeAll("</style></head><body>");

    // Container
    try writer.writeAll("<div class='container'>");
    try writer.writeAll("<h1>🔐 Create Sui Passkey</h1>");
    try writer.writeAll("<p>Click below to create a credential using Touch ID, Face ID, or YubiKey</p>");

    // Info
    try writer.writeAll("<p><strong>App:</strong> ");
    try writer.writeAll(rp_id);
    try writer.writeAll("</p>");
    try writer.writeAll("<p><strong>User:</strong> ");
    try writer.writeAll(user_name);
    try writer.writeAll("</p>");

    // Button
    try writer.writeAll("<button id='btn' onclick='create()'>Create Passkey</button>");
    try writer.writeAll("<div id='status'></div>");
    try writer.writeAll("</div>");

    // JavaScript
    try writer.writeAll("<script>");
    try writer.writeAll("const requestId='");
    try writer.writeAll(request_id);
    try writer.writeAll("';");

    // Port for POST
    const port_str = try std.fmt.allocPrint(allocator, "{d}", .{port});
    defer allocator.free(port_str);

    try writer.writeAll("async function create(){");
    try writer.writeAll("document.getElementById('btn').disabled=true;");
    try writer.writeAll("const s=document.getElementById('status');");
    try writer.writeAll("s.className='status pending';");
    try writer.writeAll("s.textContent='⏳ Waiting for authenticator...';");
    try writer.writeAll("try{");
    try writer.writeAll("const cred=await navigator.credentials.create({publicKey:{");
    try writer.writeAll("challenge:crypto.getRandomValues(new Uint8Array(32)),");
    try writer.writeAll("rp:{name:'Sui CLI',id:'localhost'},");
    try writer.writeAll("user:{id:crypto.getRandomValues(new Uint8Array(16)),name:'");
    try writer.writeAll(user_name);
    try writer.writeAll("',displayName:'");
    try writer.writeAll(user_name);
    try writer.writeAll("'},");
    try writer.writeAll("pubKeyCredParams:[{alg:-7,type:'public-key'}],");
    try writer.writeAll("authenticatorSelection:{userVerification:'required'}}});");

    // Send to server
    try writer.writeAll("const data={requestId:requestId,id:cred.id,rawId:Array.from(new Uint8Array(cred.rawId)),");
    try writer.writeAll("response:{clientDataJSON:Array.from(new Uint8Array(cred.response.clientDataJSON)),");
    try writer.writeAll("attestationObject:Array.from(new Uint8Array(cred.response.attestationObject))}};");
    try writer.writeAll("await fetch('http://localhost:");
    try writer.writeAll(port_str);
    try writer.writeAll("/credential',{");
    try writer.writeAll("method:'POST',headers:{'Content-Type':'application/json'},");
    try writer.writeAll("body:JSON.stringify(data)});");

    // Success
    try writer.writeAll("s.className='status success';");
    try writer.writeAll("s.innerHTML='✅ Success! Credential created.';");
    try writer.writeAll("}catch(e){");
    try writer.writeAll("document.getElementById('btn').disabled=false;");
    try writer.writeAll("s.className='status error';");
    try writer.writeAll("s.textContent='❌ Error: '+e.message;");
    try writer.writeAll("}}");

    // Check support
    try writer.writeAll("if(!window.PublicKeyCredential){");
    try writer.writeAll("document.getElementById('btn').disabled=true;");
    try writer.writeAll("document.getElementById('status').className='status error';");
    try writer.writeAll("document.getElementById('status').textContent='❌ WebAuthn not supported';");
    try writer.writeAll("}");
    try writer.writeAll("</script></body></html>");

    const written = stream.getWritten().len;
    return try allocator.dupe(u8, buf[0..written]);
}

fn openBrowser(path: []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "open", path },
    });
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);
}

fn parseCredential(allocator: Allocator, response: []const u8) !Credential {
    const parsed = try std.json.parseFromSlice(struct {
        requestId: []const u8,
        id: []const u8,
        rawId: []u8,
        response: struct {
            clientDataJSON: []u8,
            attestationObject: []u8,
        },
    }, allocator, response, .{});
    defer parsed.deinit();

    return Credential{
        .id = try allocator.dupe(u8, parsed.value.id),
        .raw_id = try allocator.dupe(u8, parsed.value.rawId),
        .public_key = try allocator.dupe(u8, parsed.value.response.attestationObject),
    };
}

pub const Credential = struct {
    id: []const u8,
    raw_id: []const u8,
    public_key: []const u8,

    pub fn deinit(self: *Credential, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.raw_id);
        allocator.free(self.public_key);
    }
};
