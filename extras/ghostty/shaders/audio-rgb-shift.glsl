// Audio-reactive RGB split: red and blue channels pull apart from the center
// with the mids and highs. Driven by `ghostty-audio` (palette slots 88-90:
// 8 spectrum bands + overall level). Passes the screen through untouched when
// the encoder isn't running.

// Palette slots written by ghostty-audio (its SLOTS table; gruvbox-safe).
const int LEVEL[3] = int[](25, 26, 27);
const float MIDS_SHIFT = 0.006;
const float HIGHS_SHIFT = 0.012;

// Default xterm color of 256-color palette slot n (16-231 color cube).
vec3 xtermDefault(int n) {
    int i = n - 16;
    vec3 c = vec3(i / 36, (i / 6) % 6, i % 6);
    return mix(vec3(0.0), (c * 40.0 + 55.0) / 255.0, step(0.5, c));
}

bool atDefault(int slot) {
    return distance(iPalette[slot], xtermDefault(slot)) < 0.002;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 base = texture(iChannel0, uv);
    if (atDefault(LEVEL[0]) && atDefault(LEVEL[2])) {
        fragColor = base;
        return;
    }

    vec3 a = iPalette[LEVEL[0]];
    vec3 b = iPalette[LEVEL[1]];
    vec3 c = iPalette[LEVEL[2]];
    float mids = (a.b + b.r + b.g) / 3.0;
    float highs = (b.b + c.r + c.g) / 3.0;

    vec2 dir = uv - 0.5;
    float shift = MIDS_SHIFT * mids + HIGHS_SHIFT * highs;
    fragColor = vec4(
        texture(iChannel0, uv + dir * shift).r,
        base.g,
        texture(iChannel0, uv - dir * shift).b,
        base.a
    );
}
