// Audio-reactive pulse: slight zoom and warm edge vignette on bass, glow with
// overall loudness, sparkles with the highs. Driven by `ghostty-audio`
// (palette slots 88-90: 8 spectrum bands + overall level). Passes the screen
// through untouched when the encoder isn't running.

// Palette slots written by ghostty-audio (its SLOTS table; gruvbox-safe).
const int LEVEL[3] = int[](25, 26, 27);
const float ZOOM = 0.012;
const float GLOW = 0.6;
const float VIGNETTE = 0.25;
const float SPARKLE = 0.3;

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
    if (atDefault(LEVEL[0]) && atDefault(LEVEL[2])) {
        fragColor = texture(iChannel0, uv);
        return;
    }

    vec3 a = iPalette[LEVEL[0]];
    vec3 b = iPalette[LEVEL[1]];
    vec3 c = iPalette[LEVEL[2]];
    float bass = max(a.r, a.g);
    float highs = (b.b + c.r + c.g) / 3.0;
    float level = c.b;

    vec2 zuv = clamp(0.5 + (uv - 0.5) * (1.0 - ZOOM * bass), 0.0, 1.0);
    vec4 base = texture(iChannel0, zuv);
    vec3 col = base.rgb;

    vec3 glow = vec3(0.0);
    vec2 px = 1.0 / iResolution.xy;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.785398;
        glow += texture(iChannel0, zuv + vec2(cos(ang), sin(ang)) * px * 3.0).rgb;
    }
    col += glow / 8.0 * GLOW * level;

    vec2 dir = zuv - 0.5;
    float vign = smoothstep(0.35, 0.95, length(dir * vec2(iResolution.x / iResolution.y, 1.0)));
    col += vec3(0.98, 0.55, 0.15) * vign * bass * VIGNETTE;

    float sparkle = fract(sin(dot(fragCoord + iTime, vec2(12.9898, 78.233))) * 43758.5453);
    col += step(0.998 - 0.004 * highs, sparkle) * highs * SPARKLE;

    fragColor = vec4(col, base.a);
}
