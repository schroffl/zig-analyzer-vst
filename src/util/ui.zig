const std = @import("std");

pub const MousePos = struct {
    x: i16,
    y: i16,
};

pub const KeyMap = struct {
    bits: [32]u8 = [_]u8{0} ** 32,

    pub fn set(self: *KeyMap, code: usize, state: bool) void {
        if (code >= 8 * self.bits.len) {
            std.log.crit("Keycode out of range: {}", .{code});
            return;
        }

        const bin = @divFloor(code, self.bits.len);
        const bit = @intCast(u3, code & 0b111);

        if (state) {
            self.bits[bin] = self.bits[bin] | (@as(u8, 1) << bit);
        } else {
            self.bits[bin] = self.bits[bin] & ~(@as(u8, 1) << bit);
        }
    }

    pub fn get(self: KeyMap, code: usize) bool {
        if (code >= 8 * self.bits.len) {
            std.log.crit("Keycode out of range: {}", .{code});
            return false;
        }

        const bin = @divFloor(code, self.bits.len);
        const bit = @intCast(u3, code & 0b111);

        return self.bits[bin] & (@as(u8, 1) << bit) > 0;
    }
};

test "KeyMap" {
    var key_map = KeyMap{};

    key_map.set(0, true);
    std.testing.expect(key_map.get(0));
    std.testing.expect(!key_map.get(1));
    key_map.set(0, false);
    key_map.set(1, true);
    std.testing.expect(!key_map.get(0));
    std.testing.expect(key_map.get(1));
    key_map.set(145, true);
    std.testing.expect(key_map.get(145));
}
