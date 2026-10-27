// Per-pattern Tidal waveforms behind each `dN $ ...` block in Neovim.
// Data comes from `ghostty-audio --blocks` through 98 palette slots (its
// SLOTS table, logical 35-132; gruvbox-safe; see that script's docstring). Put this shader FIRST in the chain: it tells
// background from text using the terminal's raw alpha, and later shaders
// (zoom, RGB shift) then move the waveforms together with the text.

const int GROUP[98] = int[](60, 61, 62, 63, 64, 65, 67, 68, 69, 70, 71, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 89, 90, 91, 92, 93, 94, 95, 97, 98, 99, 101, 102, 103, 104, 105, 107, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 125, 126, 127, 128, 129, 131, 133, 134, 135, 137, 138, 139, 140, 141, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 168, 169, 170, 171, 173);
const int GRID_SLOT = 0;   // indices into GROUP
const int BLOCK_SLOT = 2;
const int MAX_BLOCKS = 8;
const int LANE_SLOT = BLOCK_SLOT + 3 * MAX_BLOCKS;
const int LANE_POINTS = 36;
const vec3 WAVE_COLOR = vec3(1.0, 0.533, 0.0); // tidal highlight orange #ff8800
const float WAVE_STRENGTH = 0.55;
// Outline where blocks are expected, to check the cell -> pixel mapping.
const bool DEBUG_BLOCKS = false;

// Default xterm color of 256-color palette slot n (16-231 color cube).
vec3 xtermDefault(int n) {
    int i = n - 16;
    vec3 c = vec3(i / 36, (i / 6) % 6, i % 6);
    return mix(vec3(0.0), (c * 40.0 + 55.0) / 255.0, step(0.5, c));
}

bool atDefault(int slot) {
    return distance(iPalette[slot], xtermDefault(slot)) < 0.002;
}

int byteOf(int slot, int c) {
    return int(floor(iPalette[GROUP[slot]][c] * 255.0 + 0.5));
}

float laneSample(int lane, int i) {
    i = clamp(i, 0, LANE_POINTS - 1);
    return iPalette[GROUP[LANE_SLOT + lane * (LANE_POINTS / 3) + i / 3]][i - (i / 3) * 3] * 2.0 - 1.0;
}

float laneAt(int lane, float f) {
    int i = int(floor(f));
    float t = fract(f);
    return mix(laneSample(lane, i), laneSample(lane, i + 1), t * t * (3.0 - 2.0 * t));
}

// p: pixel position (Ghostty's fragCoord has its origin at the top-left).
// Returns (waveform intensity, debug outline) for the pattern block under p.
vec2 blockWave(vec2 p) {
    if (atDefault(GROUP[GRID_SLOT])) return vec2(0.0);
    vec2 cell = vec2(byteOf(GRID_SLOT, 0), byteOf(GRID_SLOT, 1));
    int count = min(byteOf(GRID_SLOT, 2), MAX_BLOCKS);
    vec2 grid = vec2(byteOf(GRID_SLOT + 1, 0) * 256 + byteOf(GRID_SLOT + 1, 1), byteOf(GRID_SLOT + 1, 2));
    if (count == 0 || cell.x == 0.0) return vec2(0.0);
    // window-padding-balance centers the grid in the surface.
    vec2 origin = floor((iResolution.xy - grid * cell) * 0.5);

    for (int k = 0; k < MAX_BLOCKS; k++) {
        if (k >= count) break;
        int s = BLOCK_SLOT + 3 * k;
        float top = float(byteOf(s, 1));
        float rows = float(byteOf(s, 2)) - top + 1.0;
        float left = float(byteOf(s + 1, 0) * 256 + byteOf(s + 1, 1));
        float cols = float(byteOf(s + 2, 0) * 256 + byteOf(s + 2, 1));
        vec2 size = vec2(cols, rows) * cell;
        vec2 q = p - (origin + vec2(left, top) * cell);
        if (q.x < 0.0 || q.y < 0.0 || q.x >= size.x || q.y >= size.y) continue;

        float edge = min(min(q.x, size.x - q.x), min(q.y, size.y - q.y));
        float outline = DEBUG_BLOCKS ? step(edge, 2.0) : 0.0;

        int lane = byteOf(s, 0) - 1;
        float stepPx = size.x / float(LANE_POINTS - 1);
        float f = q.x / stepPx;
        float amp = size.y * 0.42;
        float y = size.y * 0.5 - laneAt(lane, f) * amp;
        float slope = (laneAt(lane, f + 0.5) - laneAt(lane, f - 0.5)) * amp / stepPx;
        float d = abs(q.y - y) / sqrt(1.0 + slope * slope);
        // Fade in from the block's left/right edges so it reads as a backdrop.
        float fade = smoothstep(0.0, cell.x * 3.0, min(q.x, size.x - q.x));
        // Encoder fades this out when the pattern goes quiet.
        float brightness = float(byteOf(s + 1, 2)) / 255.0;
        float wave = (smoothstep(2.5, 0.8, d) + exp(-d * 0.12) * 0.35) * fade * brightness;
        return vec2(wave, outline);
    }
    return vec2(0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);
    vec2 wave = blockWave(fragCoord);
    // Background pixels are translucent (background-opacity < 1); text is opaque.
    float bgMask = 1.0 - smoothstep(0.9, 0.99, term.a);
    vec3 col = term.rgb + WAVE_COLOR * wave.x * WAVE_STRENGTH * bgMask;
    col = mix(col, vec3(0.0, 1.0, 1.0), wave.y);
    fragColor = vec4(col, term.a);
}
