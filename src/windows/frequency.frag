#version 330

in vec2 tex_pos;

uniform vec3 col;

out vec4 color;

void main() {
    color = vec4(col, 1.0);
}
