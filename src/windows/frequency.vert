#version 330

layout(location = 0) in vec2 vertex_pos;

uniform mat4 matrix;

out vec2 tex_pos;

void main() {
    tex_pos = vertex_pos * 0.5 + 0.5;
    gl_Position = matrix * vec4(vertex_pos, 0.0, 1.0);
}
