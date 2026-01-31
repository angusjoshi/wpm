const std = @import("std");
const main = @import("main.zig");
const Terminal = @import("terminal.zig");
const TextLayout = @import("text.zig");

const Context = main.Context;
const State = main.State;

const Event = union(enum) {
    char: u8,
    backspace,
    escape,
    tab,
    highscores,
    ignore,
};

layout: TextLayout,
typed: []u8,
typed_len: usize = 0,
start_time: ?i128 = null,

const Self = @This();

pub fn init(ctx: *Context) !Self {
    const layout = try TextLayout.generate(ctx.allocator, ctx.prng.random(), ctx.word_count, ctx.cols);
    const typed = try ctx.allocator.alloc(u8, layout.text.len);
    return .{
        .layout = layout,
        .typed = typed,
    };
}

pub fn deinit(self: *Self, ctx: *Context) void {
    ctx.allocator.free(self.typed);
    self.layout.deinit();
}

fn restart(self: *Self, ctx: *Context) !void {
    ctx.allocator.free(self.typed);
    self.layout.deinit();

    self.layout = try TextLayout.generate(ctx.allocator, ctx.prng.random(), ctx.word_count, ctx.cols);
    self.typed = try ctx.allocator.alloc(u8, self.layout.text.len);
    self.typed_len = 0;
    self.start_time = null;
}

fn renderFull(self: *Self, ctx: *Context) !void {
    try ctx.term.moveCursor(1, 1);
    try ctx.term.write("\x1b[J");
    try ctx.term.write("ESC to quit | TAB to restart | ` for scores");

    for (0..self.layout.text.len) |i| {
        try self.updateCharAt(ctx, i);
    }
}

fn writeStyledChar(self: *Self, ctx: *Context, i: usize, char: u8) !void {
    if (i < self.typed_len) {
        if (self.typed[i] == self.layout.text[i]) {
            try ctx.term.write("\x1b[42m");
        } else {
            try ctx.term.write("\x1b[41m");
        }
    } else if (i == self.typed_len) {
        try ctx.term.write("\x1b[7m");
    }
    try ctx.term.write(&[_]u8{char});
    if (i <= self.typed_len) {
        try ctx.term.write("\x1b[0m");
    }
}

fn updateCharAt(self: *Self, ctx: *Context, i: usize) !void {
    if (i >= self.layout.text.len) return;
    const pos = self.layout.positions[i];
    try ctx.term.moveCursor(pos.row, pos.col);
    try self.writeStyledChar(ctx, i, self.layout.text[i]);
}

fn updateWpm(self: *Self, ctx: *Context) !void {
    try ctx.term.moveCursor(self.layout.max_row + 2, 1);
    try ctx.term.write("\x1b[K");
    if (self.start_time) |start| {
        const elapsed_ns = std.time.nanoTimestamp() - start;
        const elapsed_min: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 60_000_000_000.0;
        if (elapsed_min > 0.001) {
            var correct: usize = 0;
            for (0..self.typed_len) |i| {
                if (self.typed[i] == self.layout.text[i]) correct += 1;
            }
            const w: f64 = @as(f64, @floatFromInt(correct)) / 5.0;
            const wpm: u32 = @intFromFloat(w / elapsed_min);
            var buf: [32]u8 = undefined;
            const wpm_str = std.fmt.bufPrint(&buf, "WPM: {}", .{wpm}) catch unreachable;
            try ctx.term.write(wpm_str);
        }
    }
}

fn handleEvent(self: *Self, ctx: *Context, event: Event) !?State {
    const prev_len = self.typed_len;

    switch (event) {
        .escape => return .quit,
        .highscores => return .highscores,
        .backspace => {
            if (self.typed_len > 0) self.typed_len -= 1;
        },
        .char => |c| {
            if (self.typed_len < self.typed.len) {
                if (self.start_time == null) {
                    self.start_time = std.time.nanoTimestamp();
                }
                self.typed[self.typed_len] = c;
                self.typed_len += 1;
            }
        },
        .tab => {
            try self.restart(ctx);
            try self.renderFull(ctx);
        },
        .ignore => {},
    }

    if (self.typed_len != prev_len) {
        try self.updateCharAt(ctx, prev_len);
        try self.updateCharAt(ctx, self.typed_len);
        try self.updateWpm(ctx);
    }

    if (self.typed_len == self.layout.text.len and
        std.mem.eql(u8, self.typed[0..self.typed_len], self.layout.text))
    {
        try self.saveScore(ctx);
        try ctx.term.moveCursor(self.layout.max_row + 4, 1);
        try ctx.term.write("Complete! TAB to restart | ` for scores | ESC to quit");
        while (true) {
            const key = try ctx.term.readKey();
            switch (key) {
                '\t' => {
                    try self.restart(ctx);
                    try self.renderFull(ctx);
                    break;
                },
                '`' => return .highscores,
                27 => return .quit,
                else => {},
            }
        }
    }

    return null;
}

fn saveScore(self: *Self, ctx: *Context) !void {
    const start = self.start_time orelse return;
    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_min: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 60_000_000_000.0;

    var correct: u32 = 0;
    for (0..self.typed_len) |i| {
        if (self.typed[i] == self.layout.text[i]) correct += 1;
    }

    const wpm: u16 = if (elapsed_min > 0.001)
        @intFromFloat(@as(f64, @floatFromInt(correct)) / 5.0 / elapsed_min)
    else
        0;

    try ctx.scores.add(.{
        .timestamp = std.time.timestamp(),
        .wpm = wpm,
        .word_count = @intCast(ctx.word_count),
        .correct_chars = correct,
        .total_chars = @intCast(self.typed_len),
    });
}

fn parseKey(key: u8) Event {
    return switch (key) {
        27 => .escape,
        127 => .backspace,
        '\t' => .tab,
        '`' => .highscores,
        32...95, 97...126 => .{ .char = key },
        else => .ignore,
    };
}

pub fn run(self: *Self, ctx: *Context) !State {
    try self.renderFull(ctx);
    while (true) {
        const key = try ctx.term.readKey();
        const event = parseKey(key);
        if (try self.handleEvent(ctx, event)) |next_state| {
            return next_state;
        }
    }
}
