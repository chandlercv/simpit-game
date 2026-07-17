extends Node
## Weight/volume-limited hold (feeds the tablet's inventory grid). Salvage
## arrives from SalvageSystem cuts; the tablet can jettison items to make
## room; MarketSystem empties the hold on sale.

var _next_item_id := 0


## SalvageSystem: stow a severed member's yield. Mass/volume derive from the
## good's per-unit figures. Returns false (yield lost adrift) if the hold
## can't take it — jettison something and cut smarter next time.
func stow_salvage(item_name: String, good_name: String, qty: float) -> bool:
	var good := MarketSystem.good(good_name)
	var mass_t: float = qty * good.mass_t_per_unit
	var vol_m3: float = qty * good.vol_m3_per_unit
	var ship: Dictionary = GameState.local_ship()
	if cargo_mass() + mass_t > ship["cargo_mass_limit_t"] \
			or cargo_volume() + vol_m3 > ship["cargo_vol_limit_m3"]:
		GameState.post_comms("SALVAGE",
				"HOLD FULL — %s ADRIFT (JETTISON TO MAKE ROOM)" % item_name)
		return false
	ship["cargo"].append({
		"id": _next_item_id,
		"name": item_name,
		"good": good_name,
		"qty": qty,
		"mass_t": mass_t,
		"vol_m3": vol_m3,
	})
	_next_item_id += 1
	GameState.cargo_changed.emit()
	GameState.post_comms("SALVAGE", "STOWED %s — %.1f %s %s" % [
		item_name, qty, good.unit, good_name])
	return true


## Intent (tablet): dump an item overboard.
func jettison(item_id: int) -> void:
	var cargo: Array = GameState.local_ship()["cargo"]
	for i in cargo.size():
		if cargo[i]["id"] == item_id:
			GameState.post_comms("OPS", "JETTISONED %s" % cargo[i]["name"])
			cargo.remove_at(i)
			GameState.cargo_changed.emit()
			return


## MarketSystem: hold sold, clear it.
func clear_hold() -> void:
	GameState.local_ship()["cargo"] = []
	GameState.cargo_changed.emit()


func cargo_mass() -> float:
	var total := 0.0
	for item: Dictionary in GameState.local_ship()["cargo"]:
		total += item["mass_t"]
	return total


func cargo_volume() -> float:
	var total := 0.0
	for item: Dictionary in GameState.local_ship()["cargo"]:
		total += item["vol_m3"]
	return total
