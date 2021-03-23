const std = @import("std");
const Ring = @This();

allocator: *std.mem.Allocator,
buffer: []f32,

write_idx: usize = 0,
read_idx: usize = 0,

pub fn init(allocator: *std.mem.Allocator, size: usize) !Ring {
    var ring = Ring{
        .allocator = allocator,
        .buffer = try allocator.alloc(f32, size),
    };

    std.mem.set(f32, ring.buffer, 0);
    return ring;
}

pub fn deinit(self: *Ring) void {
    self.allocator.free(self.buffer);
    self.* = undefined;
}

pub fn write(self: *Ring, data: []const f32) void {
    for (data) |value| {
        const idx = self.write_idx % self.buffer.len;
        self.buffer[idx] = value;
        self.write_idx += 1;

        if (self.write_idx - self.read_idx > self.buffer.len) {
            self.read_idx = self.write_idx - self.buffer.len;
        }
    }
}

pub fn read(self: *Ring) ?f32 {
    if (self.write_idx - self.read_idx == 0)
        return null;

    const idx = self.read_idx % self.buffer.len;
    return idx;
}

pub fn iterateMax(self: *Ring, max_size: usize) ReadMaxIterator {
    return ReadMaxIterator{
        .ring = self,
        .max_size = max_size,
    };
}

pub const ReadMaxIterator = struct {
    count: usize = 0,
    max_size: usize,
    ring: *Ring,

    pub fn next(self: *ReadMaxIterator) ?f32 {
        if (self.count >= self.max_size)
            return null;

        self.count += 1;
        return ring.read();
    }
};

pub fn readSlice(self: *Ring) SliceResult {
    var result: SliceResult = undefined;

    const available = self.write_idx - self.read_idx;

    const read_idx = self.read_idx % self.buffer.len;
    const write_idx = self.write_idx % self.buffer.len;

    if (read_idx > write_idx) {
        // We need two parts
        result.first = self.buffer[read_idx..];
        result.second = self.buffer[0..write_idx];
        result.count = result.first.len + result.second.?.len;
    } else {
        result.first = self.buffer[read_idx..write_idx];
        result.second = null;
        result.count = result.first.len;
    }

    self.read_idx += available;

    return result;
}

pub const SliceResult = struct {
    first: []const f32,
    second: ?[]const f32,
    count: usize,
};
