#version 330

in vec2 dot_pos;

out vec4 color;

void main() {
    float d = distance(dot_pos, vec2(0.0));
    float alpha = clamp(1.0 - d, 0.0, 1.0);

    color = vec4(1.0, 1.0, 1.0, alpha);
}
