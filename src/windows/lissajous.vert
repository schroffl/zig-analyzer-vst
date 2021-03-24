#version 330

layout(location = 0) in vec2 vertex_pos;
layout(location = 1) in vec2 signal_frame;

uniform float num_frames;
uniform float graph_scale, dot_size;

out float time_decay;
out float draw_clipped;
out vec2 dot_pos;

void main() {
    vec2 frame = signal_frame * graph_scale;

    vec2 abs_frame = abs(frame);
    float max_sample = max(abs_frame.x, abs_frame.y);
    draw_clipped = min(1.0, floor(max_sample));

    if (draw_clipped > 0.0) {
        frame = frame / max_sample;
    }

    time_decay = gl_InstanceID / num_frames;
    dot_pos = vertex_pos;

    vec2 pos = frame + vertex_pos * dot_size;
    float z = time_decay;
    gl_Position = vec4(pos, z, 1.0);
}
