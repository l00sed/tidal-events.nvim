// Strudel-style waveform of the whole mix across the middle of the screen.
// Needs `ghostty-audio --scope` (96 waveform points, 3 per palette slot).
// Passes the screen through untouched when that data isn't being sent.

// Palette slots written by ghostty-audio (its SLOTS table; gruvbox-safe).
const int LEVEL[3] = int[](25, 26, 27);
const int SCOPE[32] = int[](28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59);
const int SCOPE_POINTS = 96;
const float SCOPE_HEIGHT = 0.22; // fraction of screen height at full amplitude

// Default xterm color of 256-color palette slot n (16-231 color cube).
vec3 xtermDefault(int n) {
    int i = n - 16;
    vec3 c = vec3(i / 36, (i / 6) % 6, i % 6);
    return mix(vec3(0.0), (c * 40.0 + 55.0) / 255.0, step(0.5, c));
}

bool atDefault(int slot) {
    return distance(iPalette[slot], xtermDefault(slot)) < 0.002;
}

float scopeSample(int i) {
    i = clamp(i, 0, SCOPE_POINTS - 1);
    vec3 s = iPalette[SCOPE[i / 3]];
    int c = i - (i / 3) * 3;
    return (c == 0 ? s.r : c == 1 ? s.g : s.b) * 2.0 - 1.0;
}

// Waveform height (pixels from screen center) at horizontal pixel x.
float scopeY(float x) {
    float f = x / iResolution.x * float(SCOPE_POINTS - 1);
    int i = int(floor(f));
    float t = fract(f);
    return mix(scopeSample(i), scopeSample(i + 1), t * t * (3.0 - 2.0 * t)) * SCOPE_HEIGHT * iResolution.y;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 base = texture(iChannel0, fragCoord / iResolution.xy);
    fragColor = base;
    if (atDefault(SCOPE[0]) && atDefault(SCOPE[31])) return;

    float level = iPalette[LEVEL[2]].b;
    float y = iResolution.y * 0.5 + scopeY(fragCoord.x);
    float slope = (scopeY(fragCoord.x + 1.0) - scopeY(fragCoord.x - 1.0)) * 0.5;
    float d = abs(fragCoord.y - y) / sqrt(1.0 + slope * slope);
    float line = smoothstep(1.6, 0.4, d) + exp(-d * 0.35) * 0.25;
    vec3 tint = mix(vec3(0.98, 0.74, 0.18), vec3(0.56, 0.75, 0.49), fragCoord.x / iResolution.x);
    fragColor = vec4(base.rgb + tint * line * (0.5 + 0.5 * level), base.a);
}
