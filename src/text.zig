const std = @import("std");

const words_data = @embedFile("words.txt");
const words = blk: {
    @setEvalBranchQuota(200000);
    var list: [1000][]const u8 = undefined;
    var count: usize = 0;
    var start: usize = 0;
    for (words_data, 0..) |c, i| {
        if (c == '\n') {
            if (i > start) {
                list[count] = words_data[start..i];
                count += 1;
            }
            start = i + 1;
        }
    }
    break :blk list[0..count].*;
};

pub const Pos = struct { row: u16, col: u16 };

allocator: std.mem.Allocator,
text_buf: []u8,
positions_buf: []Pos,
text: []const u8,
positions: []Pos,
max_row: u16,

const Self = @This();

pub fn generate(allocator: std.mem.Allocator, rand: std.Random, word_count: usize, cols: u16) !Self {
    const max_len = word_count * 20;
    const buf = try allocator.alloc(u8, max_len);
    const positions = try allocator.alloc(Pos, max_len);

    var len: usize = 0;
    var row: u16 = 3;
    var col: u16 = 1;

    for (0..word_count) |_| {
        const word = words[rand.intRangeAtMost(usize, 0, words.len - 1)];

        // add space before word (except first)
        if (len > 0) {
            if (col > cols) {
                // space at line break - skip it, just wrap
                row += 1;
                col = 1;
            } else {
                positions[len] = .{ .row = row, .col = col };
                buf[len] = ' ';
                len += 1;
                col += 1;
            }
        }

        // wrap if word doesn't fit
        if (col > 1 and col + word.len - 1 > cols) {
            row += 1;
            col = 1;
        }

        // place word
        for (word) |c| {
            positions[len] = .{ .row = row, .col = col };
            buf[len] = c;
            len += 1;
            col += 1;
        }
    }

    return .{
        .allocator = allocator,
        .text_buf = buf,
        .positions_buf = positions,
        .text = buf[0..len],
        .positions = positions[0..len],
        .max_row = row,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.text_buf);
    self.allocator.free(self.positions_buf);
}
