const std = @import("std");
const main = @import("main.zig");
const ScoreStore = @import("score.zig");

const Context = main.Context;
const State = main.State;

const Self = @This();

pub fn init() Self {
    return .{};
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn run(self: *Self, ctx: *Context) !State {
    _ = self;

    try ctx.term.moveCursor(1, 1);
    try ctx.term.write("\x1b[J");
    try ctx.term.write("HIGH SCORES\r\n\r\n");

    const records = ctx.scores.top(0, 10);

    if (records.len == 0) {
        try ctx.term.write("  No scores yet.\r\n");
    } else {
        for (records, 1..) |record, rank| {
            var buf: [80]u8 = undefined;
            const datetime = formatTimestamp(record.timestamp);
            const line = std.fmt.bufPrint(&buf, "  {d:>2}. {d:>3} WPM  ({d} words)  {s}\r\n", .{
                rank,
                record.wpm,
                record.word_count,
                datetime,
            }) catch continue;
            try ctx.term.write(line);
        }
    }

    try ctx.term.write("\r\nESC to quit | ` to play");

    while (true) {
        const key = try ctx.term.readKey();
        switch (key) {
            27 => return .quit,
            '`' => return .gameplay,
            else => {},
        }
    }
}

fn formatTimestamp(timestamp: i64) [19]u8 {
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch.getDaySeconds();

    var buf: [19]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch {};
    return buf;
}
