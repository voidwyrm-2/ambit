const std = @import("std");

const ambit = @import("ambit.zig");
const VM = ambit.VM;

pub fn main() !u8 {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var vm = VM.init(std.heap.page_allocator);
    defer vm.deinit();

    const input = [_]u8{ (@intFromEnum(ambit.Opcode.Copy) << 1) | 1, 20, 0 };

    const ret = try vm.execute(&input);

    try stdout.print("{any}\n", .{vm.registers});

    try bw.flush();

    return @intCast(ret);
}
