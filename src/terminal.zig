const std = @import("std");
const posix = std.posix;

original_termios: posix.termios,
tty: posix.fd_t,

const Self = @This();

pub fn init() !Self {
    const tty = try posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0);
    const original = try posix.tcgetattr(tty);
    return .{ .original_termios = original, .tty = tty };
}

pub fn enableRawMode(self: *Self) !void {
    var raw = self.original_termios;

    raw.iflag.BRKINT = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;
    raw.oflag.OPOST = false;
    raw.cflag.CSIZE = .CS8;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;

    try posix.tcsetattr(self.tty, .FLUSH, raw);
}

pub fn deinit(self: *Self) void {
    posix.tcsetattr(self.tty, .FLUSH, self.original_termios) catch {};
    posix.close(self.tty);
}

pub fn readKey(self: *Self) !u8 {
    var buf: [1]u8 = undefined;
    _ = try posix.read(self.tty, &buf);
    return buf[0];
}

pub fn write(self: *Self, data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        written += try posix.write(self.tty, data[written..]);
    }
}

pub fn clearScreen(self: *Self) !void {
    try self.write("\x1b[2J");
}

pub fn hideCursor(self: *Self) !void {
    try self.write("\x1b[?25l");
}

pub fn showCursor(self: *Self) !void {
    try self.write("\x1b[?25h");
}

pub fn moveCursor(self: *Self, row: u16, col: u16) !void {
    var buf: [32]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{};{}H", .{ row, col }) catch unreachable;
    try self.write(seq);
}

pub fn getCols(self: *Self) u16 {
    var size: posix.winsize = undefined;
    const err = posix.system.ioctl(self.tty, posix.T.IOCGWINSZ, @intFromPtr(&size));
    if (err != 0) return 80;
    return size.col;
}
