#version 330

in float time_decay;
in vec2 dot_pos;

uniform vec3 dot_color;

out vec4 color;

void main() {
    float d = distance(dot_pos, vec2(0.0));
    float alpha = time_decay * 0.5 + 0.5;

    color = vec4(dot_color, alpha);
}
