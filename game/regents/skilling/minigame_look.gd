class_name MinigameLook extends RefCounted
## THE MINIGAMES' LOOK (`MINIGAMES_PREP.md` §5, Luke's M7 and M8, 2026-11-05): the type and colors a minigame's 2D
## readouts share, so the four (and the ones to come) read as one game. A minigame sets `theme = MinigameLook.theme()`;
## its `_draw` reads the font from the theme (`get_theme_default_font`) and the colors here. Smithing first; the
## others take it as they get their look (§8 step 5).
##
## The font is the machine's own book serif (Palatino on Windows and the Mac, Georgia, else any serif): no font file
## to license or ship. A CC0 display font can replace it here, in one place.

## Warm parchment white for words, a dimmer one for hints, and the forge's gold and ember.
const INK: Color = Color(0.96, 0.92, 0.84)
const HINT: Color = Color(0.96, 0.92, 0.84, 0.72)
const GOLD: Color = Color(0.98, 0.78, 0.36)
const EMBER: Color = Color(1.0, 0.45, 0.14)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.75)

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		var serif: SystemFont = SystemFont.new()
		serif.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "serif"])
		serif.font_weight = 600
		_theme.default_font = serif
		_theme.default_font_size = 20
	return _theme


## How strongly a pattern's outline is drawn (1: full). Full while it is laid on (or with no pattern, or the round over);
## lifted at `lifted_ms` (-1: never laid and lifted), it fades over `fade_ms` to `ghost_pm` thousandths of full and stays
## (Luke, 2026-11-09: copper 3 s to a faint ghost, iron 1.5 s to a fainter one, steel 3 s to nothing).
static func pattern_alpha(shown: bool, now_ms: int, lifted_ms: int, fade_ms: int, ghost_pm: int) -> float:
	if shown:
		return 1.0
	var ghost: float = clampf(float(ghost_pm) / 1000.0, 0.0, 1.0)
	if lifted_ms < 0 or fade_ms <= 0:
		return ghost
	var f: float = clampf(float(now_ms - lifted_ms) / float(fade_ms), 0.0, 1.0)
	return lerpf(1.0, ghost, f)


## Words with a soft shadow under them, so they read over a lit 3D stage.
static func text(ci: CanvasItem, font: Font, at: Vector2, s: String, size: int, color: Color = INK,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(font, at + Vector2(1.5, 2.0), s, align, width, size, SHADOW)
	ci.draw_string(font, at, s, align, width, size, color)
