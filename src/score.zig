const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Record = packed struct {
    timestamp: i64,
    wpm: u16,
    word_count: u16,
    correct_chars: u32,
    total_chars: u32,
};

allocator: Allocator,
file: ?std.fs.File,
records: std.ArrayList(Record),

const Self = @This();

pub fn init(allocator: Allocator, path: []const u8) !Self {
    var self = Self{
        .allocator = allocator,
        .file = null,
        .records = .empty,
    };

    self.file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => std.fs.cwd().createFile(path, .{ .read = true }) catch null,
        else => null,
    };

    const record_size = @divExact(@bitSizeOf(Record), 8);
    if (self.file) |file| {
        const stat = try file.stat();
        const record_count = stat.size / record_size;
        try self.records.ensureTotalCapacity(allocator, record_count);

        const divd_record_size = @divExact(@bitSizeOf(Record), 8);
        for (0..record_count) |_| {
            var bytes: [divd_record_size]u8 = undefined;
            const n = file.read(&bytes) catch break;
            if (n != divd_record_size) break;
            const record: Record = @bitCast(bytes);
            try self.records.append(allocator, record);
        }
    }

    self.sortByWpm();
    return self;
}

pub fn deinit(self: *Self) void {
    if (self.file) |file| file.close();
    self.records.deinit(self.allocator);
}

pub fn add(self: *Self, record: Record) !void {
    const record_size = @divExact(@bitSizeOf(Record), 8);
    if (self.file) |file| {
        const bytes: [record_size]u8 = @bitCast(record);
        try file.seekFromEnd(0);
        try file.writeAll(&bytes);
    }
    try self.records.append(self.allocator, record);
    self.sortByWpm();
}

fn sortByWpm(self: *Self) void {
    std.mem.sort(Record, self.records.items, {}, struct {
        fn cmp(_: void, a: Record, b: Record) bool {
            return a.wpm > b.wpm;
        }
    }.cmp);
}

pub fn count(self: *Self) usize {
    return self.records.items.len;
}

pub fn top(self: *Self, offset: usize, limit: usize) []const Record {
    const start = @min(offset, self.records.items.len);
    const end = @min(offset + limit, self.records.items.len);
    return self.records.items[start..end];
}

pub fn all(self: *Self) []const Record {
    return self.records.items;
}
