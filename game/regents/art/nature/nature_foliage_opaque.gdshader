shader_type spatial;
// Opaque blades: the grass, which has no alpha to test, coloured from the kit's palette of stripes
// (so it is read without mipmaps — FOLIAGE_PALETTE). See nature_foliage.gdshaderinc.
#define FOLIAGE_PALETTE
#include "res://game/regents/art/nature/nature_foliage.gdshaderinc"
