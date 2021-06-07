#version 330

layout(location = 0) in vec2 vertex_pos;
layout(location = 1) in vec2 signal_frame;

uniform float graph_scale, dot_size;

out vec2 dot_pos;

void main() {
    vec2 frame = signal_frame.yx * graph_scale;

    vec2 abs_frame = abs(frame);
    float max_sample = max(abs_frame.x, abs_frame.y);

    if (max_sample > 1.0) {
        frame = frame / max_sample;
    }

    dot_pos = vertex_pos;

    vec2 pos = frame + vertex_pos * dot_size;
    gl_Position = vec4(pos, 0.0, 1.0);
}
