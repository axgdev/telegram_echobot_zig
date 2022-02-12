const std = @import("std");
const Client = @import("requestz").Client;

pub fn main() anyerror!void {
    //var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    //defer _ = gpa.deinit();
    //const allocator = gpa.allocator();

    //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena.deinit();
    //const allocator = arena.allocator();
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator);
    defer client.deinit();

    const token = getToken(allocator) catch unreachable;
    defer allocator.free(token);
    var tree = getUpdates(allocator, client, token) catch unreachable;
    defer tree.deinit();
    try sendMessage(allocator, client, token, tree);
}

pub fn getToken(allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(
        "token.txt",
        .{ .mode = .read_only }
    );
    defer file.close();

    const token_length = 46;

    const token_file = try file.reader().readAllAlloc(
        allocator,
        token_length+1, //The last character should be ignored
    );
    defer allocator.free(token_file);

    // const token = try allocator.alloc(u8, token_length);
    // // errdefer allocator.free(token);
    // std.mem.copy(u8, token, token_file[0..token_length]);
    const token = allocator.dupe(u8, token_file[0..token_length]);
    //const token = token_file[0..token_length]; //ignore the last character
    std.debug.print("\nToken: {s}\n", .{token});
    return token;
}

pub fn getUpdates(allocator: std.mem.Allocator, client: Client, token: []u8) !std.json.ValueTree {
    const methodName = "getUpdates";
    const telegramUrlTemplate = "https://api.telegram.org/bot{s}/" ++ methodName;
    //std.debug.print("\nToken: {s}\n", .{token});
    const telegramUrl = std.fmt.allocPrint(allocator, telegramUrlTemplate, .{ token }) catch unreachable;

    var response = try client.get(telegramUrl, .{});
    //defer response.deinit(); //TODO: How to deinit this, how to copy the tree, so that when we deinit the response, the tree survives
    const responseBody = response.body;
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(responseBody);
    std.log.err("{s}", .{responseBody});

    var tree = try response.json();
    
    //var tree_alloc = allocator.dupe(!std.json.ValueTree, tree);
    return tree;
}

pub fn sendMessage(allocator: std.mem.Allocator, client: Client, token: []u8, tree: std.json.ValueTree) !void {
    var result = tree.root.Object.get("result").?;
    var lastIndex = result.Array.items.len - 1;
    var message = result.Array.items[lastIndex].Object.get("message").?;
    var text = message.Object.get("text").?;
    var chat = message.Object.get("chat").?;
    var chatId = chat.Object.get("id").?;

    std.debug.print("\n{s}\n", .{text.String});
    std.debug.print("\n{d}\n", .{chatId.Integer});

    const messageMethod = "sendMessage";
    const sendMessageUrlTemplate = "https://api.telegram.org/bot{s}/" ++ messageMethod;
    const sendMessageUrl = std.fmt.allocPrint(allocator, sendMessageUrlTemplate, .{ token }) catch unreachable;

    const rawJson =
       \\ {{
       \\   "chat_id": {d}, "text": "{s}"
       \\ }}
    ;

    const echoResponseJsonString = std.fmt.allocPrint(allocator, rawJson, .{ chatId.Integer, text.String }) catch unreachable;
    const echoComplete = std.fmt.allocPrint(allocator, "{s}", .{echoResponseJsonString}) catch unreachable;
    defer allocator.free(echoResponseJsonString);

    var headers = .{.{ "Content-Type", "application/json" }};

    std.debug.print("\n echoComplete: {s}\n", .{echoComplete});

    var response1 = try client.post(sendMessageUrl, .{ .content = echoComplete, .headers = headers });
    defer response1.deinit();

    std.debug.print("\n{s}\n", .{response1.body});
}