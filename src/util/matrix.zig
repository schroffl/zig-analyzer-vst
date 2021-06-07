const std = @import("std");
const Mat4 = @This();

pub const identity = Mat4{ .data = [_]f32{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
} };

data: [16]f32,

pub fn fromValues(values: [16]f32) Mat4 {
    return Mat4{ .data = values };
}

pub fn multiply(a: Mat4, b: Mat4) Mat4 {
    var out: Mat4 = undefined;

    var row: usize = 0;

    while (row < 4) : (row += 1) {
        var column: usize = 0;

        while (column < 4) : (column += 1) {
            const i = row * 4 + column;

            out.data[i] = a.data[row * 4] * b.data[column] + a.data[row * 4 + 1] * b.data[column + 4] + a.data[row * 4 + 2] * b.data[column + 8] + a.data[row * 4 + 3] * b.data[column + 12];
        }
    }

    return out;
}

pub fn multiplyMany(matrices: []const Mat4) Mat4 {
    var current = matrices[0];
    std.debug.assert(matrices.len >= 1);

    for (matrices[1..]) |matrix| {
        current = current.multiply(matrix);
    }

    return current;
}

pub fn rotateZ(angle: f32) Mat4 {
    var out = identity;

    out.data[0] = std.math.cos(angle);
    out.data[1] = -std.math.sin(angle);

    out.data[4] = std.math.sin(angle);
    out.data[5] = std.math.cos(angle);

    return out;
}

pub fn rotateY(angle: f32) Mat4 {
    var out = identity;

    out.data[0] = std.math.cos(angle);
    out.data[2] = -std.math.sin(angle);

    out.data[8] = std.math.sin(angle);
    out.data[10] = std.math.cos(angle);

    return out;
}

pub fn rotateX(angle: f32) Mat4 {
    var out = identity;

    out.data[5] = std.math.cos(angle);
    out.data[6] = -std.math.sin(angle);

    out.data[9] = std.math.sin(angle);
    out.data[10] = std.math.cos(angle);

    return out;
}

pub fn scale(x: f32, y: f32, z: f32) Mat4 {
    var out = identity;

    out.data[0] = x;
    out.data[5] = y;
    out.data[10] = z;

    return out;
}

pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const fov_rad = fov * std.math.pi / 180.0;
    const f = 1.0 / std.math.tan(fov_rad / 2.0);
    const range_inv = 1.0 / (near - far);

    var out = identity;

    out.data[0] = f / aspect;
    out.data[5] = f;
    out.data[10] = (near + far) * range_inv;
    out.data[11] = -1;
    out.data[14] = near * far * range_inv * 2;
    out.data[15] = 0;

    return out;
}

pub fn translate(x: f32, y: f32, z: f32) Mat4 {
    var out = identity;
    out.data[12] = x;
    out.data[13] = y;
    out.data[14] = z;
    return out;
}

pub fn approxEq(a: Mat4, b: Mat4, tolerance: f32) bool {
    for (a.data) |a_val, i| {
        const b_val = b.data[i];

        if (!std.math.approxEqAbs(f32, a_val, b_val, tolerance))
            return false;
    }

    return true;
}

test "multiply" {
    const a = Mat4.fromValues([_]f32{
        1, 0, 0, 0,
        2, 1, 3, 0,
        0, 1, 1, 2,
        0, 2, 3, 4,
    });

    const b = Mat4.fromValues([_]f32{
        2, 1, 0, 0,
        2, 1, 0, 3,
        1, 4, 2, 0,
        0, 4, 1, 2,
    });

    const result = Mat4.multiply(a, b);
    const result_many = Mat4.multiplyMany(&[_]Mat4{ a, b });
    const expected = Mat4.fromValues([_]f32{
        2, 1,  0,  0,
        9, 15, 6,  3,
        3, 13, 4,  7,
        7, 30, 10, 14,
    });

    std.testing.expect(Mat4.approxEq(result, expected, 0.01));
    std.testing.expect(Mat4.approxEq(result_many, expected, 0.01));
}

test "rotateZ" {
    const rotation = rotateZ(std.math.pi);
    const result = multiply(identity, rotation);
    const result_reverse = multiply(rotation, identity);

    std.testing.expect(approxEq(result, rotation, 0.01));
    std.testing.expect(approxEq(result_reverse, rotation, 0.01));
}
