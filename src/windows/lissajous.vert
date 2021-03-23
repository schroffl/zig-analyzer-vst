#version 330

layout(location = 0) in vec2 vertex_pos;
layout(location = 1) in vec2 signal_frame;

uniform float num_frames;
uniform float graph_scale, dot_size;

out float time_decay;
out vec2 dot_pos;

void main() {
    vec2 pos = signal_frame * graph_scale + vertex_pos * dot_size;
    time_decay = gl_InstanceID / num_frames;
    dot_pos = vertex_pos;
    gl_Position = vec4(pos, 0.0, 1.0);
}
