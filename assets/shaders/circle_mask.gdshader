shader_type canvas_item;

uniform float radius = 0.5;   // 相对纹理短边的半径比例
uniform float feather = 0.01; // 边缘羽化

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	float a = 1.0 - smoothstep(radius - feather, radius + feather, d);
	COLOR.a *= a;
}
