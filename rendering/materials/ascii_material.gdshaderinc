// Legacy material class tags (the ASCII renderer that read them is gone).
// Shaders still call ascii_roughness(roughness, class); it now returns the
// roughness unchanged, so materials keep full specular precision. The
// constants stay only so existing shaders compile.

const int ASCII_SOLID = 0;
const int ASCII_FOLIAGE = 1;
const int ASCII_LIQUID = 2;
const int ASCII_STREAK = 3;
const int ASCII_GROUND = 4;
const int ASCII_EMISSIVE = 5;
const int ASCII_CLOTH = 6;
const int ASCII_DEFAULT = 7;

float ascii_roughness(float roughness, int ascii_id) {
	return clamp(roughness, 0.0, 1.0);
}
