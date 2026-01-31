const std = @import("std");
const Terminal = @import("terminal.zig");
const GameplayScene = @import("gameplay.zig");
const HighscoresScene = @import("highscores.zig");
const ScoreStore = @import("score.zig");

pub const State = enum {
    gameplay,
    highscores,
    quit,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    term: *Terminal,
    prng: *std.Random.DefaultPrng,
    scores: *ScoreStore,
    word_count: usize,
    cols: u16,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const max_words = 100_000;
    const args = std.os.argv;
    const num_words: usize = if (args.len > 1) blk: {
        const arg = std.mem.span(args[1]);
        const parsed = std.fmt.parseInt(usize, arg, 10) catch 10;
        break :blk @min(parsed, max_words);
    } else 10;

    var term = try Terminal.init();
    defer term.deinit();

    const scores_path = blk: {
        const home = std.posix.getenv("HOME") orelse break :blk "scores.dat";
        const dir_path = std.fmt.allocPrint(allocator, "{s}/.wpm", .{home}) catch break :blk "scores.dat";
        std.fs.cwd().makeDir(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => break :blk "scores.dat",
        };
        break :blk std.fmt.allocPrint(allocator, "{s}/.wpm/scores.dat", .{home}) catch "scores.dat";
    };

    var scores = try ScoreStore.init(allocator, scores_path);
    defer scores.deinit();

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));

    var ctx = Context{
        .allocator = allocator,
        .term = &term,
        .prng = &prng,
        .scores = &scores,
        .word_count = num_words,
        .cols = @min(term.getCols(), 80),
    };

    var gameplay = try GameplayScene.init(&ctx);
    defer gameplay.deinit(&ctx);

    var highscores = HighscoresScene.init();
    defer highscores.deinit();

    try term.enableRawMode();
    try term.hideCursor();
    try term.clearScreen();

    var state: State = .gameplay;
    while (state != .quit) {
        state = switch (state) {
            .gameplay => try gameplay.run(&ctx),
            .highscores => try highscores.run(&ctx),
            .quit => break,
        };
    }

    try term.clearScreen();
    try term.moveCursor(1, 1);
    try term.showCursor();
}
