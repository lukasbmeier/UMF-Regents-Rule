class_name RegentsRoleBadge extends RefCounted
## A ROLE'S BADGE (COMBAT_OVERHAUL.md §5; Luke 2026-11-01: SHOW, DON'T NAME): a small shape in the role's colour
## (`RoleDef.badge`, `badge_color`), never a word. Drawn here, once a role and size, so the craft window's handle
## list, the bag and its tooltip need no art yet: a point, a shield, a cross.

static var _cache: Dictionary[String, ImageTexture] = {}


## The badge of `role` as a `size`-pixel square texture (null for no role).
static func texture(role: RoleDef, size: int = 16) -> ImageTexture:
	if role == null:
		return null
	var key: String = "%d:%d:%d:%s" % [role.id, size, role.badge, role.badge_color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var edge: Color = role.badge_color.darkened(0.55)
	for y: int in size:
		for x: int in size:
			if not inside(role.badge, x, y, size):
				continue
			var rim: bool = not (inside(role.badge, x - 1, y, size) and inside(role.badge, x + 1, y, size)
				and inside(role.badge, x, y - 1, size) and inside(role.badge, x, y + 1, size))
			img.set_pixel(x, y, edge if rim else role.badge_color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Whether pixel (`x`, `y`) of a `size` square is inside badge `shape`.
static func inside(shape: RoleDef.Badge, x: int, y: int, size: int) -> bool:
	if x < 0 or y < 0 or x >= size or y >= size:
		return false
	var c: float = (size - 1) / 2.0
	var dx: float = absf(x - c)
	var dy: float = y - c
	var r: float = c - 0.5
	match shape:
		RoleDef.Badge.SHIELD:
			# A flat top, straight sides, tapering to a point at the foot.
			var top: float = -r
			var waist: float = r * 0.15
			if dy < top:
				return false
			if dy <= waist:
				return dx <= r * 0.85
			return dx <= r * 0.85 * (1.0 - (dy - waist) / (r - waist + 0.001))
		RoleDef.Badge.CROSS:
			var arm: float = r * 0.32
			return (dx <= arm and absf(dy) <= r) or (absf(dy) <= arm and dx <= r)
	return dx + absf(dy) <= r   # POINT: a diamond


## The badge as a node, `size` pixels square (an empty one for no role, so rows line up).
static func rect(role: RoleDef, size: int = 16) -> TextureRect:
	var t := TextureRect.new()
	t.name = "RoleBadge"
	t.texture = texture(role, size)
	t.custom_minimum_size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## WHAT A HANDLE DOES on `made` (a weapon of a kit with roles), in the player's words: its role's last hit and
## its guard ("The string ends in a pommel bash ... Held, a full guard: ..."). "" when it gives no role there.
static func does_line(made: ItemDef, role: RoleDef) -> String:
	var kit: KitDef = KitDef.by_key(made.weapon_kit) if made != null and made.weapon_kit != &"" else null
	if kit == null or not kit.has_roles() or role == null:
		return ""
	var kr: KitRole = kit.role_entry(role)
	var parts: PackedStringArray = PackedStringArray()
	if kr != null and not kr.does.is_empty():
		parts.append(kr.does)
	if not role.guard_words.is_empty():
		parts.append("Held, " + role.guard_words + ".")
	return " ".join(parts)


## A weapon's last hit with `role`, named ("Pommel bash"), for its tooltip; "" for a kit with no roles.
static func last_hit_name(made: ItemDef, role: RoleDef) -> String:
	var kit: KitDef = KitDef.by_key(made.weapon_kit) if made != null and made.weapon_kit != &"" else null
	if kit == null or not kit.has_roles():
		return ""
	var a: AbilityDef = kit.finisher_for(role)
	return a.display_name if a != null else ""


## The role a handle `part` gives `made` (its shape's, else the plain one), or null when `made` has no roles.
static func role_of_part(part: ItemDef, made: ItemDef) -> RoleDef:
	var kit: KitDef = KitDef.by_key(made.weapon_kit) if made != null and made.weapon_kit != &"" else null
	if kit == null or not kit.has_roles() or part == null:
		return null
	return part.role if part.role != null else RoleDef.plain_role()
