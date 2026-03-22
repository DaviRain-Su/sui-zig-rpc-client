// Simple Browser WebAuthn Bridge
// Opens browser with HTML file for WebAuthn credential creation

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Create WebAuthn credential via browser
pub fn createCredentialInBrowser(
    allocator: Allocator,
    rp_id: []const u8,
    user_name: []const u8,
    output_dir: []const u8,
) !Credential {
    // Create output directory
    try std.fs.cwd().makePath(output_dir);
    
    // Generate request ID
    var request_id: [16]u8 = undefined;
    std.crypto.random.bytes(&request_id);
    const request_id_hex = try std.fmt.allocPrint(allocator, "{x}", .{request_id});
    defer allocator.free(request_id_hex);
    
    // Create HTML file
    const html_path = try std.fs.path.join(allocator, &.{ output_dir, "webauthn.html" });
    defer allocator.free(html_path);
    
    const html = try generateSimpleHtml(allocator, request_id_hex, rp_id, user_name);
    defer allocator.free(html);
    
    const file = try std.fs.cwd().createFile(html_path, .{});
    defer file.close();
    try file.writeAll(html);
    
    // Create response file path
    const response_filename = try std.fmt.allocPrint(allocator, "{s}.json", .{request_id_hex});
    defer allocator.free(response_filename);
    const response_path = try std.fs.path.join(allocator, &.{ output_dir, response_filename });
    defer allocator.free(response_path);
    
    // Open browser
    std.log.info("Opening browser for WebAuthn...", .{});
    std.log.info("HTML file: {s}", .{html_path});
    std.log.info("", .{});
    std.log.info("Please:", .{});
    std.log.info("  1. Click 'Create Passkey' in the browser", .{});
    std.log.info("  2. Authenticate with Touch ID / YubiKey", .{});
    std.log.info("  3. Download the .json file", .{});
    std.log.info("  4. Move it to: {s}/", .{output_dir});
    std.log.info("", .{});
    
    try openBrowser(html_path);
    
    // Wait for response file
    std.log.info("Waiting for browser response (timeout: 2 minutes)...", .{});
    const response = try waitForFile(allocator, response_path, 120000);
    defer allocator.free(response);
    
    std.log.info("Response received!", .{});
    
    // Parse credential
    return try parseCredential(allocator, response);
}

fn generateSimpleHtml(
    allocator: Allocator,
    request_id: []const u8,
    rp_id: []const u8,
    user_name: []const u8,
) ![]const u8 {
    // Use a simple template approach
    // First, write static parts to a buffer
    var buf: [32768]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();
    
    // HTML head
    try writer.writeAll(
        "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Sui WebAuthn</title>");
    try writer.writeAll(
        "<style>");
    try writer.writeAll(
        "body{font-family:-apple-system,sans-serif;max-width:600px;margin:50px auto;padding:20px;");
    try writer.writeAll(
        "background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);min-height:100vh}");
    try writer.writeAll(
        ".container{background:white;padding:40px;border-radius:20px;box-shadow:0 20px 60px rgba(0,0,0,0.3)}");
    try writer.writeAll(
        "h1{color:#333;margin-bottom:10px}");
    try writer.writeAll(
        "button{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;");
    try writer.writeAll(
        "padding:18px 40px;border:none;border-radius:10px;cursor:pointer;font-size:18px;width:100%}");
    try writer.writeAll(
        ".status{margin-top:20px;padding:15px;border-radius:10px}");
    try writer.writeAll(
        ".success{background:#d4edda;color:#155724}");
    try writer.writeAll(
        ".error{background:#f8d7da;color:#721c24}");
    try writer.writeAll(
        ".pending{background:#fff3cd;color:#856404}");
    try writer.writeAll(
        "</style></head><body>");
    
    // Container start
    try writer.writeAll(
        "<div class='container'>");
    try writer.writeAll(
        "<h1>🔐 Create Sui Passkey</h1>");
    try writer.writeAll(
        "<p>Click below to create a credential using Touch ID, Face ID, or YubiKey</p>");
    
    // RP ID - use writer.print
    try writer.writeAll("<p><strong>App:</strong> ");
    try writer.writeAll(rp_id);
    try writer.writeAll("</p>");
    
    // User name
    try writer.writeAll("<p><strong>User:</strong> ");
    try writer.writeAll(user_name);
    try writer.writeAll("</p>");
    
    // Button and status
    try writer.writeAll(
        "<button id='btn' onclick='create()'>Create Passkey</button>");
    try writer.writeAll(
        "<div id='status'></div>");
    try writer.writeAll(
        "</div>");
    
    // JavaScript
    try writer.writeAll("<script>");
    try writer.writeAll("const requestId='");
    try writer.writeAll(request_id);
    try writer.writeAll("';");
    
    // JavaScript function
    try writer.writeAll(
        "async function create(){");
    try writer.writeAll(
        "document.getElementById('btn').disabled=true;");
    try writer.writeAll(
        "const s=document.getElementById('status');");
    try writer.writeAll(
        "s.className='status pending';");
    try writer.writeAll(
        "s.textContent='⏳ Waiting for authenticator...';");
    try writer.writeAll(
        "try{");
    try writer.writeAll(
        "const cred=await navigator.credentials.create({publicKey:{");
    try writer.writeAll(
        "challenge:crypto.getRandomValues(new Uint8Array(32)),");
    
    // RP info
    try writer.writeAll("rp:{name:'Sui CLI',id:'");
    try writer.writeAll(rp_id);
    try writer.writeAll("'},");
    
    // User info
    try writer.writeAll("user:{id:crypto.getRandomValues(new Uint8Array(16)),name:'");
    try writer.writeAll(user_name);
    try writer.writeAll("',displayName:'");
    try writer.writeAll(user_name);
    try writer.writeAll("'},");
    
    // Continue WebAuthn
    try writer.writeAll(
        "pubKeyCredParams:[{alg:-7,type:'public-key'}],");
    try writer.writeAll(
        "authenticatorSelection:{userVerification:'required'}}});");
    
    // Response handling
    try writer.writeAll(
        "const data={requestId:requestId,id:cred.id,rawId:Array.from(new Uint8Array(cred.rawId)),");
    try writer.writeAll(
        "response:{clientDataJSON:Array.from(new Uint8Array(cred.response.clientDataJSON)),");
    try writer.writeAll(
        "attestationObject:Array.from(new Uint8Array(cred.response.attestationObject))}};");
    
    // Download
    try writer.writeAll(
        "const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'});");
    try writer.writeAll(
        "const url=URL.createObjectURL(blob);");
    try writer.writeAll(
        "const a=document.createElement('a');a.href=url;a.download=requestId+'.json';");
    try writer.writeAll(
        "document.body.appendChild(a);a.click();document.body.removeChild(a);URL.revokeObjectURL(url);");
    
    // Success
    try writer.writeAll(
        "s.className='status success';");
    try writer.writeAll(
        "s.innerHTML='✅ Success! File downloaded. Move it to the keystore directory.';");
    
    // Error handling
    try writer.writeAll(
        "}catch(e){");
    try writer.writeAll(
        "document.getElementById('btn').disabled=false;");
    try writer.writeAll(
        "s.className='status error';");
    try writer.writeAll(
        "s.textContent='❌ Error: '+e.message;");
    try writer.writeAll(
        "}}");
    
    // WebAuthn check
    try writer.writeAll(
        "if(!window.PublicKeyCredential){");
    try writer.writeAll(
        "document.getElementById('btn').disabled=true;");
    try writer.writeAll(
        "document.getElementById('status').className='status error';");
    try writer.writeAll(
        "document.getElementById('status').textContent='❌ WebAuthn not supported';");
    try writer.writeAll(
        "}");
    try writer.writeAll(
        "</script></body></html>");
    
    const written = stream.getWritten().len;
    return try allocator.dupe(u8, buf[0..written]);
}

fn openBrowser(path: []const u8) !void {
    // Use posix spawn for Zig 0.15.2 compatibility
    const result = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "open", path },
    });
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);
}

fn waitForFile(allocator: Allocator, path: []const u8, timeout_ms: u64) ![]const u8 {
    const start = std.time.milliTimestamp();
    
    while (std.time.milliTimestamp() - start < timeout_ms) {
        const file = std.fs.cwd().openFile(path, .{}) catch {
            std.Thread.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        defer file.close();
        
        return try file.readToEndAlloc(allocator, 1024 * 1024);
    }
    
    return error.Timeout;
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
