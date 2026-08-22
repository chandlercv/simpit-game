class_name ScreenLayout
extends RefCounted
## Pure geometry for the display layout: given one screen's rect, whether the
## Main view lives on it, and which secondary roles share it, work out the rect
## each one gets. No DisplayServer calls and no scene loads, so the whole layout
## decision is asserted headlessly (tools/DisplayLayoutSmoke.gd) rather than by
## plugging monitors in.
##
## Two tiers, and the second one is exactly what the game did before tiling:
##  - tile — every role on the screen gets its own rect and they are all up at
##    once. On the Main screen the flight view keeps the top MAIN_FRACTION and
##    the roles share the strip below it.
##  - tabbed — a region where tiling would shrink a panel past MIN_SCALE hands
##    the whole region to a single RoleTabHost instead. On the Main screen that
##    is the dimmed overlay over a fullscreen Main view; on a spare screen it is
##    one window filling it.
##
## A panel is drawn by scaling its authored canvas (WindowManager.ROLE_CANVAS)
## to fit its window, so a small rect costs small type, not a broken layout —
## which is why tiles beat one wide strip here. Three 640x344 tiles of a 1080p
## screen each give a panel ~1340x720 logical px to lay out in, near its 1280x720
## canvas; the same strip undivided would give it 4019x720 and stretch the
## composition across three times its design width.

## Share of the Main screen's height the flight view keeps when it shares.
const MAIN_FRACTION := 2.0 / 3.0

## Below this fraction of its authored canvas a panel's type stops being worth
## reading, and the region falls back to a tabbed host. Set by the tightest
## arrangement still worth allowing: the 1280x800 MFDs in the bottom third of a
## 1080p screen, which come out at 0.43.
const MIN_SCALE := 0.42

## Canvas assumed for a role with no entry in the table passed to plan_screen.
const DEFAULT_CANVAS := Vector2i(1280, 720)

## Which role takes the full-width bottom row of a shared spare screen: the MFDs
## are the display you reach for, and two units side by side want the width.
## First one present wins.
const WIDE_ROW_PRIORITY: Array[String] = ["mfd", "tactical", "camera"]


## The whole layout decision for one screen. `roles` is the secondary roles on
## it (no "main"), in the order they should be laid out left to right; `canvases`
## maps role -> authored content_scale_size. Returns:
##
##   main_fullscreen : the Main window covers this screen (or isn't on it)
##   main            : the Main window's rect when it shares the screen
##   tiles           : role -> Rect2i, one native window each; empty when tabbed
##   tabbed          : this region needs a RoleTabHost instead of tiles
##   tab_overlay     : that host is the dimmed overlay on the Main window
##   tab_region      : the rect the host fills (unused when tab_overlay)
##   tab_roles       : the roles it hosts
static func plan_screen(region: Rect2i, has_main: bool, roles: Array,
		canvases: Dictionary = {}) -> Dictionary:
	var plan := {
		"main_fullscreen": has_main,
		"main": Rect2i(),
		"tiles": {},
		"tabbed": false,
		"tab_overlay": false,
		"tab_region": Rect2i(),
		"tab_roles": [],
	}
	if roles.is_empty():
		return plan

	if has_main:
		var split := split_main(region)
		var tiles := tile_strip(split["strip"], roles)
		if fits(tiles, canvases):
			plan["main_fullscreen"] = false
			plan["main"] = split["main"]
			plan["tiles"] = tiles
			return plan
		# Too short to dock legibly — keep Main edge to edge and put the panels
		# back over it, which is what a laptop panel got before tiling existed.
		plan["tabbed"] = true
		plan["tab_overlay"] = true
		plan["tab_roles"] = roles.duplicate()
		return plan

	var spare := tile_screen(region, roles)
	if fits(spare, canvases):
		plan["tiles"] = spare
		return plan
	plan["tabbed"] = true
	plan["tab_region"] = region
	plan["tab_roles"] = roles.duplicate()
	return plan


## Cut a shared Main screen into the flight view and the panel strip below it.
## Exact: the two heights always sum back to the region's.
static func split_main(region: Rect2i) -> Dictionary:
	var cut := region.position.y + roundi(region.size.y * MAIN_FRACTION)
	return {
		"main": Rect2i(region.position, Vector2i(region.size.x, cut - region.position.y)),
		"strip": Rect2i(Vector2i(region.position.x, cut),
				Vector2i(region.size.x, region.end.y - cut)),
	}


## Equal columns across a region, in the given order — the Main screen's strip.
static func tile_strip(region: Rect2i, roles: Array) -> Dictionary:
	var tiles := {}
	if roles.is_empty():
		return tiles
	var cuts := _cuts(region.position.x, region.size.x, roles.size())
	for i in roles.size():
		tiles[roles[i]] = Rect2i(cuts[i], region.position.y,
				cuts[i + 1] - cuts[i], region.size.y)
	return tiles


## A whole spare screen: one role covers it; otherwise the WIDE_ROW_PRIORITY
## role takes the full-width bottom row and the rest share the top one. Every
## cell stays landscape, which is the shape all three panels are authored in.
static func tile_screen(region: Rect2i, roles: Array) -> Dictionary:
	if roles.is_empty():
		return {}
	if roles.size() == 1:
		return {roles[0]: region}

	var wide: String = roles[roles.size() - 1]
	for candidate in WIDE_ROW_PRIORITY:
		if roles.has(candidate):
			wide = candidate
			break
	var rest := []
	for role in roles:
		if role != wide:
			rest.append(role)

	var cuts := _cuts(region.position.y, region.size.y, 2)
	var top := Rect2i(region.position.x, cuts[0], region.size.x, cuts[1] - cuts[0])
	var bottom := Rect2i(region.position.x, cuts[1], region.size.x, cuts[2] - cuts[1])
	var tiles := tile_strip(top, rest)
	tiles[wide] = bottom
	return tiles


## How much of its authored canvas a panel gets in this rect — the factor
## CONTENT_SCALE_ASPECT_EXPAND will draw it at.
static func scale_for(rect: Rect2i, canvas: Vector2i) -> float:
	if canvas.x <= 0 or canvas.y <= 0:
		return 1.0
	return minf(float(rect.size.x) / float(canvas.x), float(rect.size.y) / float(canvas.y))


## True when every tile can still carry its panel at a readable size.
static func fits(tiles: Dictionary, canvases: Dictionary) -> bool:
	for role: String in tiles:
		var rect: Rect2i = tiles[role]
		if rect.size.x <= 0 or rect.size.y <= 0:
			return false
		if scale_for(rect, canvases.get(role, DEFAULT_CANVAS)) < MIN_SCALE:
			return false
	return true


## One line for the launch card and the chooser, so a reassignment's consequence
## is visible before it's committed.
static func describe(plan: Dictionary) -> String:
	var roles: Array = plan["tab_roles"] if plan["tabbed"] else plan["tiles"].keys()
	if roles.is_empty():
		return "flight view only"
	if plan["tabbed"]:
		var where := "over the flight view" if plan["tab_overlay"] else "filling the screen"
		return "%d displays share a tabbed panel %s — too little room to tile" % [roles.size(), where]
	if not plan["main_fullscreen"]:
		return "flight view over %d tiled displays" % roles.size()
	return "%d display%s tiled" % [roles.size(), "" if roles.size() == 1 else "s"]


## Cut coordinates for n equal parts, rounded as boundaries rather than as
## widths, so adjacent cells share an edge exactly — no 1px seam, no overlap,
## and the parts always sum back to `length`.
static func _cuts(start: int, length: int, n: int) -> PackedInt32Array:
	var cuts := PackedInt32Array()
	for i in n + 1:
		cuts.append(start + roundi(float(length) * float(i) / float(n)))
	return cuts
