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

    const token = token_file[0..token_length]; //ignore the last character

    const methodName = "getUpdates";
    const telegramUrlTemplate = "https://api.telegram.org/bot{s}/" ++ methodName;
    const telegramUrl = std.fmt.allocPrint(allocator, telegramUrlTemplate, .{ token }) catch unreachable;

    var response = try client.get(telegramUrl, .{});
    defer response.deinit();
    const responseBody = response.body;
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(responseBody);
    std.log.err("{s}", .{responseBody});

    var tree = try response.json();
    defer tree.deinit();

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
