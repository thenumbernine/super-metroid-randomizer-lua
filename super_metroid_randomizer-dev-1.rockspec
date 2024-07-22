package = "super_metroid_randomizer"
version = "dev-1"
source = {
	url = "git+https://github.com/thenumbernine/super-metroid-randomizer-lua"
}
description = {
	summary = "Super Metroid Visualizer and Item Randomizer",
	detailed = "Super Metroid Visualizer and Item Randomizer",
	homepage = "https://github.com/thenumbernine/super-metroid-randomizer-lua",
	license = "MIT"
}
dependencies = {
	"lua >= 5.1"
}
build = {
	type = "builtin",
	modules = {
		["super_metroid_randomizer.blob"] = "blob.lua",
		["super_metroid_randomizer.config"] = "config.lua",
		["super_metroid_randomizer.door"] = "door.lua",
		["super_metroid_randomizer.doors"] = "doors.lua",
		["super_metroid_randomizer.enemies"] = "enemies.lua",
		["super_metroid_randomizer.exprand"] = "exprand.lua",
		["super_metroid_randomizer.item-scavenger"] = "item-scavenger.lua",
		["super_metroid_randomizer.items"] = "items.lua",
		["super_metroid_randomizer.lz"] = "lz.lua",
		["super_metroid_randomizer.mapbg"] = "mapbg.lua",
		["super_metroid_randomizer.md5"] = "md5.lua",
		["super_metroid_randomizer.memorymap"] = "memorymap.lua",
		["super_metroid_randomizer.palette"] = "palette.lua",
		["super_metroid_randomizer.patches"] = "patches.lua",
		["super_metroid_randomizer.pc"] = "pc.lua",
		["super_metroid_randomizer.plm"] = "plm.lua",
		["super_metroid_randomizer.print-instrs"] = "print-instrs.lua",
		["super_metroid_randomizer.randomizeworld"] = "randomizeworld.lua",
		["super_metroid_randomizer.room"] = "room.lua",
		["super_metroid_randomizer.roomblocks"] = "roomblocks.lua",
		["super_metroid_randomizer.rooms"] = "rooms.lua",
		["super_metroid_randomizer.roomstate"] = "roomstate.lua",
		["super_metroid_randomizer.run"] = "run.lua",
		["super_metroid_randomizer.sm"] = "sm.lua",
		["super_metroid_randomizer.sm-code"] = "sm-code.lua",
		["super_metroid_randomizer.sm-enemies"] = "sm-enemies.lua",
		["super_metroid_randomizer.sm-graphics"] = "sm-graphics.lua",
		["super_metroid_randomizer.sm-items"] = "sm-items.lua",
		["super_metroid_randomizer.sm-map"] = "sm-map.lua",
		["super_metroid_randomizer.sm-regions"] = "sm-regions.lua",
		["super_metroid_randomizer.sm-samus"] = "sm-samus.lua",
		["super_metroid_randomizer.sm-weapons"] = "sm-weapons.lua",
		["super_metroid_randomizer.smstruct"] = "smstruct.lua",
		["super_metroid_randomizer.tileset"] = "tileset.lua",
		["super_metroid_randomizer.util"] = "util.lua",
		["super_metroid_randomizer.vis"] = "vis.lua",
		["super_metroid_randomizer.weapons"] = "weapons.lua",
		["super_metroid_randomizer.writerange"] = "writerange.lua"
	}
}
