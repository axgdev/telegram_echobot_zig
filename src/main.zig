const std = @import("std");
const Client = @import("requestz").Client;

pub const Update = struct {
    updateId: i64,
    chatId: i64,
    text: []const u8,
};

const GetUpdatesError = error{
    NoMessages
};

pub fn main() anyerror!void {
    try runEchoBot();
}

pub fn runEchoBot() anyerror!void {
        //var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    //defer _ = gpa.deinit();
    //const allocator = gpa.allocator();

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();
    // const initial_allocator = std.testing.allocator;

    var buffer: [94]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const token_allocator = fba.allocator();

    const token = try getToken(token_allocator);
    defer token_allocator.free(token);

    // const stdout = std.io.getStdOut().writer();
    // try stdout.print("Press q to quit: ", .{});

    
    // var buf: [1]u8 = undefined;
    // const stdin = std.io.getStdIn().reader();

    var updateId: i64 = undefined;

    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var client = try Client.init(allocator);
        defer client.deinit();

        defer std.time.sleep(1e+10);
        var update = try getUpdates(allocator, client, token);
        defer allocator.free(update.text);

        var newUpdateId = update.updateId;
        if (updateId == newUpdateId) {
            continue;
        }

        updateId = newUpdateId;
        try sendMessage(allocator, client, token, update);
    }
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

pub fn getUpdates(allocator: std.mem.Allocator, client: Client, token: []u8) !Update {
    const methodName = "getUpdates?offset=-1";
    const telegramUrlTemplate = "https://api.telegram.org/bot{s}/" ++ methodName;
    const telegramUrl = try std.fmt.allocPrint(allocator, telegramUrlTemplate, .{ token });
    std.debug.print("\n{s}\n", .{telegramUrl});

    var response = try client.get(telegramUrl, .{});

    const responseBody = response.body;
    std.debug.print("{s}", .{responseBody});

    var tree = try response.json();
    defer tree.deinit();
    
    //var tree_alloc = allocator.dupe(!std.json.ValueTree, tree);
    var result = tree.root.Object.get("result").?;

    if (result.Array.items.len < 1) {
        return GetUpdatesError.NoMessages;
    }

    var lastIndex = result.Array.items.len - 1;
    var updateId = result.Array.items[0].Object.get("update_id").?.Integer;
    var message = result.Array.items[lastIndex].Object.get("message").?;
    var text = message.Object.get("text").?;
    var chat = message.Object.get("chat").?;
    var chatId = chat.Object.get("id").?;

    std.debug.print("\nUpdateId: {d}\n", .{updateId});
    std.debug.print("\nText: {s}\n", .{text.String});
    std.debug.print("\nChatId: {d}\n", .{chatId.Integer});
    return Update{
        .updateId = updateId,
        .chatId = chatId.Integer,
        .text = try allocator.dupe(u8, text.String),
    };
}

pub fn sendMessage(allocator: std.mem.Allocator, client: Client, token: []u8, update: Update) !void {
    const messageMethod = "sendMessage";
    const sendMessageUrlTemplate = "https://api.telegram.org/bot{s}/" ++ messageMethod;
    const sendMessageUrl = try std.fmt.allocPrint(allocator, sendMessageUrlTemplate, .{ token });

    const rawJson = \\ {{ "chat_id": {d}, "text": "{s}" }}
    ;

    const echoResponseJsonString = try std.fmt.allocPrint(allocator, rawJson, .{ update.chatId, update.text });
    const echoComplete = try std.fmt.allocPrint(allocator, "{s}", .{echoResponseJsonString});
    defer allocator.free(echoResponseJsonString);

    var headers = .{.{ "Content-Type", "application/json" }};

    std.debug.print("\n echoComplete: {s}\n", .{echoComplete});

    var response1 = try client.post(sendMessageUrl, .{ .content = echoComplete, .headers = headers });
    defer response1.deinit();

    std.debug.print("\n{s}\n", .{response1.body});
}
