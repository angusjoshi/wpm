const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;

pub const Record = packed struct {
    timestamp: i64,
    wpm: u16,
    word_count: u16,
    correct_chars: u32,
    total_chars: u32,

    const byte_size = @divExact(@bitSizeOf(Record), 8);
};

allocator: Allocator,
fd: ?posix.fd_t,
records: std.ArrayList(Record),

const Self = @This();

fn readAll(fd: posix.fd_t, buf: []u8) !void {
    var total: usize = 0;
    while (total < buf.len) {
        const n = try posix.read(fd, buf[total..]);
        if (n == 0) return error.EndOfStream;
        total += n;
    }
}

pub fn init(allocator: Allocator, path: [:0]const u8) !Self {
    var self = Self{
        .allocator = allocator,
        .fd = null,
        .records = .empty,
    };

    self.fd = posix.openat(posix.AT.FDCWD, path, .{
        .ACCMODE = .RDWR,
        .APPEND = true,
        .CREAT = true,
    }, 0o644) catch null;

    if (self.fd) |fd| {
        const stat = try posix.fstat(fd);
        const record_count = @as(usize, @intCast(stat.size)) / Record.byte_size;
        try self.records.ensureTotalCapacity(allocator, record_count);

        for (0..record_count) |_| {
            var bytes: [Record.byte_size]u8 = undefined;
            readAll(fd, &bytes) catch break;
            try self.records.append(allocator, @bitCast(bytes));
        }
    }

    self.sortByWpm();
    return self;
}

pub fn deinit(self: *Self) void {
    if (self.fd) |fd| posix.close(fd);
    self.records.deinit(self.allocator);
}

pub fn add(self: *Self, record: Record) !void {
    if (self.fd) |fd| {
        const bytes: [Record.byte_size]u8 = @bitCast(record);
        _ = try posix.write(fd, &bytes);
        posix.fdatasync(fd) catch {};
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
