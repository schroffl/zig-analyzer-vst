#version 330

layout (location = 0) in vec2 corner;
layout (location = 1) in vec2 frame;
layout (location = 2) in vec2 prevFrame;
layout (location = 3) in vec2 nextFrame;

uniform float num_frames;
uniform mat4 matrix;

void main() {
    float x_step = 2.0 / (num_frames - 1.0);

    vec2 point = vec2(corner.y * x_step - 1.0, frame.x);
    vec2 prev = vec2(point.x - x_step, prevFrame.x);
    vec2 next = vec2(point.x + x_step, nextFrame.x);

    vec2 AB = normalize(point - prev);
    vec2 BC = normalize(next - point);
    vec2 tangent = normalize(AB + BC);

    vec2 miter = vec2(-tangent.y, tangent.x);
    vec2 normalA = vec2(-AB.y, AB.x);

    vec2 final = point;

    float uWidth = 0.02;
    float miterLength = 1.0 / dot(miter, normalA);

    final += corner.x * miter * uWidth * miterLength;

    gl_Position = matrix * vec4(final, 0.0, 1.0);
}
