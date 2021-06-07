#version 330

layout (location = 0) in vec2 vertex_pos;

uniform mat4 matrix;

void main() {
    gl_Position = matrix * vec4(vertex_pos, 0.0, 1.0);
}
