const std = @import("std");
const zip = @import("zip");

const output_path = "C:\\ziglang_test";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var client = std.http.Client{
        .allocator = allocator,
    };
    defer client.deinit();

    const uri = try std.Uri.parse("https://ziglang.org/download/index.json");
    var headers = std.http.Headers.init(allocator);
    defer headers.deinit();

    var req = try client.request(std.http.Method.GET, uri, headers, .{});
    defer req.deinit();

    try req.start();
    try req.wait();

    var json_reader = std.json.reader(allocator, req.reader());
    defer json_reader.deinit();

    const json = try std.json.parseFromTokenSource(std.json.Value, allocator, &json_reader, .{});
    defer json.deinit();

    //json.value.dump();
    const version = json.value.object.get("master").?.object.get("version").?.string;
    const url = json.value.object.get("master").?.object.get("x86_64-windows").?.object.get("tarball").?.string;
    const size = try std.fmt.parseInt(i32, json.value.object.get("master").?.object.get("x86_64-windows").?.object.get("size").?.string, 10);
    std.log.info("version: {s}\nurl: {s}\nsize: {}\n", .{ version, url, size });

    const uri_download = try std.Uri.parse(url);

    var req_download = try client.request(std.http.Method.GET, uri_download, headers, .{});
    defer req_download.deinit();

    try req_download.start();
    try req_download.wait();

    const zip_buf = try allocator.alloc(u8, @intCast(size));
    defer allocator.free(zip_buf);

    _ = try req_download.reader().readAll(zip_buf);

    if (zip.zip_stream_open(zip_buf.ptr, zip_buf.len, zip.ZIP_DEFAULT_COMPRESSION_LEVEL, 'r')) |archive| {
        const total: usize = @intCast(zip.zip_entries_total(archive));
        std.log.info("total {}\n", .{total});

        var output: [256:0]u8 = undefined;

        for (0..total) |i| {
            if (zip.zip_entry_openbyindex(archive, @intCast(i)) == 0) {
                if (zip.zip_entry_isdir(archive) == 1) {
                    _ = zip.zip_entry_close(archive);
                    continue;
                }

                const zip_file_path = std.mem.span(zip.zip_entry_name(archive));

                replaceRootPath(zip_file_path, output_path, &output);
                try createPathRecursively(&output);

                std.debug.print("output: {s}\n", .{output});

                const res = zip.zip_entry_fread(archive, @ptrCast(@as([*c]u8, &output)));

                if (res < 0) {
                    std.log.err("error on reading: {}", .{res});
                }
                _ = zip.zip_entry_close(archive);
            }
        }

        zip.zip_stream_close(archive);
    }
}

fn replaceRootPath(original_path: []const u8, target_path: []const u8, output: []u8) void {
    @memset(output[0..], 0);

    var index: ?usize = null;
    for (original_path, 0..) |c, i| {
        if (c == '/' or c == '\\') {
            index = i;
            break;
        }
    }

    if (index == null)
        index = original_path.len;

    _ = std.mem.replace(u8, original_path, original_path[0..index.?], target_path, output);
}

fn createPathRecursively(target_path: []const u8) !void {
    for (target_path, 0..) |c, i| {
        if (c == '/' or c == '\\') {
            std.fs.cwd().makeDir(target_path[0..i]) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => return err,
            };

            std.debug.print("creating sub path: {s}\n", .{target_path[0..i]});
        }
    }
}
