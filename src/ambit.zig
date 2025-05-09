const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AmbitError = error{ General, InvalidOpcode, InvalidCallAddress };

pub const Opcode = enum(u8) { Call, Scope, Abort, Mset, Mget, Cmp, Jump, Tjmp, Fjmp, Copy, Add, Sub, Mul, Div, _ };

const memorySize = std.math.maxInt(u16);
const registerCount = 32;
const argCount = 8;

const AmbiBuiltin = *const fn (vm: *VM, args: [8]u16) u16;

fn bytesToUsize(bytes: []const u8) usize {
    var result: usize = 0;

    for (bytes, 0..) |b, i| {
        result |= @intCast(b);
        // can't use <<= because of issues with how it works with runtime-known values
        // see https://ziggit.dev/t/cannot-cast-usize-to-i64-in-std-math-pow/6518
        // and https://github.com/ziglang/zig/issues/7605
        result = std.math.shr(usize, result, 8 * (i + 1));
    }

    return result;
}

pub const Scope = struct {
    parent: ?*Scope,
    raddress: ?usize,
    memory: *[memorySize]u8,
    args: [argCount]u16,
    pub fn init(parent: ?*Scope, raddress: ?usize, args: [argCount]u16) Scope {
        var memory = [_]u8{0} ** memorySize;
        return .{ .parent = parent, .raddress = raddress, .memory = if (parent) |p| p.memory else &memory, .args = args };
    }
};

pub const VM = struct {
    scope: Scope,
    registers: [registerCount]u16,
    passedArgs: [argCount]u16,
    ret: u16,
    pc: usize,
    t: bool,
    builtins: std.StringHashMap(AmbiBuiltin),
    allocator: Allocator,
    err: []const u8,
    pub fn init(allocator: Allocator) VM {
        return VM.initWithScope(allocator, Scope.init(null, 0, [_]u16{0} ** argCount));
    }
    fn initWithScope(allocator: Allocator, scope: Scope) VM {
        return .{
            .scope = scope,
            .registers = [_]u16{0} ** registerCount,
            .passedArgs = [_]u16{0} ** argCount,
            .ret = 0,
            .pc = 0,
            .t = false,
            .builtins = std.StringHashMap(AmbiBuiltin).init(allocator),
            .allocator = allocator,
            .err = &[0]u8{},
        };
    }
    pub fn deinit(self: *VM) void {
        self.builtins.deinit();
    }
    fn errf(self: *VM, e: AmbitError, comptime format: []const u8, args: anytype) !void {
        self.err = try std.fmt.allocPrint(self.allocator, format, args);
        return e;
    }
    pub fn getRegister(self: *VM, register: u8) !u16 {
        if (register <= 31) {
            return self.registers[@intCast(register)];
        } else if (register >= 32 and register <= 39) {
            return self.scope.args[@intCast(register - 31)];
        } else {
            try self.errf(AmbitError.General, "{d} is not a readable register", .{register});
        }

        unreachable;
    }
    pub fn setRegister(self: *VM, register: u8, value: u16) !void {
        if (register <= 31) {
            self.registers[@intCast(register)] = value;
        } else if (register >= 32 and register <= 39) {
            self.passedArgs[@intCast(register - 31)] = value;
        } else if (register == 40) {
            self.ret = value;
        } else {
            try self.errf(AmbitError.General, "{d} is not a writable register", .{register});
        }
    }
    pub fn execute(self: *VM, bytes: []const u8) !u16 {
        while (self.pc < bytes.len) {
            const imm = bytes[self.pc] & 1 == 1;
            const op: Opcode = @enumFromInt(bytes[self.pc] >> 1);
            switch (op) {
                .Call => {
                    const state = bytes[self.pc + 1];

                    if (state == 1) {} else {
                        const target = bytesToUsize(bytes[self.pc + 1 .. 2]);
                        const rr = bytes[self.pc + 3];

                        const targetOp: Opcode = @enumFromInt(bytes[target]);
                        if (targetOp != Opcode.Scope) {
                            try self.errf(AmbitError.InvalidCallAddress, "{d} is not a valid calling address, as all calls must be to a scope instruction", .{target});
                        }

                        var subvm = VM.initWithScope(self.allocator, Scope.init(&self.scope, self.pc + 4, self.passedArgs));
                        try self.setRegister(rr, try subvm.execute(bytes[target..]));

                        self.pc += 1;
                    }
                },
                .Scope => {
                    const subsc = Scope.init(&self.scope, null, self.passedArgs);
                    self.scope = subsc;

                    self.pc += 1;
                },
                .Abort => {
                    if (self.scope.parent != null) {
                        if (self.scope.raddress) |ra| {
                            self.pc = ra;
                        }

                        self.scope = self.scope.parent.?.*;
                    }

                    self.pc += 1;
                },
                .Mget => self.pc += 1,
                .Mset => self.pc += 1,
                .Cmp => self.pc += 1,
                .Jump => self.pc += 1,
                .Tjmp => self.pc += 1,
                .Fjmp => self.pc += 1,
                .Copy => {
                    const val = if (imm) bytes[self.pc + 1] else try self.getRegister(bytes[self.pc + 1]);

                    try self.setRegister(bytes[self.pc + 2], val);

                    self.pc += 3;
                },
                .Add => self.pc += 1,
                .Sub => self.pc += 1,
                .Mul => self.pc += 1,
                .Div => self.pc += 1,
                _ => try self.errf(AmbitError.InvalidOpcode, "invalid opcode {d}", .{bytes[self.pc]}),
            }
        }

        return self.ret;
    }
};
