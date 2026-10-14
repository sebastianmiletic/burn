// Material class IDs read by the ASCII pass. Mirrors AsciiMaterialId.gd.
// A material picks its glyph style by writing:
//     ROUGHNESS = ascii_roughness(my_roughness, ASCII_FOLIAGE);

const int ASCII_SOLID = 0;
const int ASCII_FOLIAGE = 1;
const int ASCII_LIQUID = 2;
const int ASCII_STREAK = 3;
const int ASCII_GROUND = 4;
const int ASCII_EMISSIVE = 5;
const int ASCII_CLOTH = 6;
const int ASCII_DEFAULT = 7;

float ascii_roughness(float roughness, int ascii_id) {
	float level = clamp(floor(roughness * 15.0 + 0.5), 0.0, 15.0);
	return (level * 8.0 + float(ascii_id)) / 127.0;
}
