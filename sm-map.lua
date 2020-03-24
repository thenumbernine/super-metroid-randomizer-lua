-- https://github.com/tewtal/smlib especially SMLib/ROMHandler.cs
-- metroidconstruction.com/SMMM
-- https://github.com/dansgithubuser/dansSuperMetroidLibrary/blob/master/sm.hpp
-- http://forum.metroidconstruction.com/index.php?topic=2476.0
-- http://www.metroidconstruction.com/SMMM/plm_disassembly.txt

local ffi = require 'ffi'
local struct = require 'struct'
local lz = require 'lz'
local WriteRange = require 'writerange'


local SMMap = {}


-- defined in section 6 of metroidconstruction.com/SMMM
-- mdb = 'map database' I'm guessing?
-- I am really tempted to defy convention and just call this 'room_t'
-- and then call 'rooms' => 'roomblocks' or something, since it is the per-block data
local mdb_t = struct'mdb_t'{	-- aka mdb, aka mdb_header
	{index = 'uint8_t'},		-- 0
	{region = 'uint8_t'},		-- 1
	{x = 'uint8_t'},			-- 2
	{y = 'uint8_t'},			-- 3
	{width = 'uint8_t'},		-- 4
	{height = 'uint8_t'},		-- 5
	{upScroller = 'uint8_t'},	-- 6
	{downScroller = 'uint8_t'},	-- 7
	{gfxFlags = 'uint8_t'},		-- 8
	{doors = 'uint16_t'},		-- 9 offset at bank  ... 9f?
}

-- this is how the mdb_format.txt describes it, but it looks like the structure might be a bit more conditional...
local roomselect_t = struct'roomselect_t'{
	{testcode = 'uint16_t'},	-- ptr to test code in bank $8f
	{testvalue = 'uint8_t'},
	{roomstate = 'uint16_t'},	-- ptr to alternative roomstate in bank $8f
}

local roomselect2_t = struct'roomselect2_t'{
	{testcode = 'uint16_t'},
	{roomstate = 'uint16_t'},
}

local roomstate_t = struct'roomstate_t'{
	{roomAddr = 'uint16_t'},
	{roomBank = 'uint8_t'},		-- usu c2-c9
	{gfxSet = 'uint8_t'},
	{musicTrack = 'uint8_t'},
	{musicControl = 'uint8_t'},
	{fx1 = 'uint16_t'},
	{enemySpawn = 'uint16_t'},
	{enemyGFX = 'uint16_t'},
	{layer2scrollData = 'uint16_t'},	-- TODO
	
	--[[
	scroll is either a constant, or an offset in bank $8f to 1 byte per map block
	if scroll is 0 or 1 then it is a constant -- to fill all map blocks with that scroll value
	otherwise it is a ptr to an array of scroll values for each map block.
	0 = don't scroll up/down, or past the scroll==0 boundaries at all
	1 = scroll anywhere, but clip the top & bottom 2 blocks (which will hide vertical exits)
	2 = scroll anywhere at all ... but keeps samus in the middle, which makes it bad for hallways
	--]]
	{scroll = 'uint16_t'},
	
	--[[
	this is only used by the gold torizo room, and points to the extra data after mdb_t
	--]]
	{unknown = 'uint16_t'},				
	{fx2 = 'uint16_t'},					-- TODO - aka 'main asm ptr'
	{plm = 'uint16_t'},
	{bgdata = 'uint16_t'},
	{layerHandling = 'uint16_t'},
}

-- plm = 'post-load modification'
-- this is a non-enemy object in a map.
local plm_t = struct'plm_t'{
	{cmd = 'uint16_t'},
	{x = 'uint8_t'},
	{y = 'uint8_t'},
	{args = 'uint16_t'},
}

-- this is a single spawn location of an enemy.
local enemySpawn_t = struct'enemySpawn_t'{
	{enemyAddr = 'uint16_t'},	-- matches enemies[].addr
	{x = 'uint16_t'},
	{y = 'uint16_t'},
	{initGFX = 'uint16_t'},	-- init param / tilemaps / orientation
	{prop1 = 'uint16_t'},	-- special
	{prop2 = 'uint16_t'},	-- graphics
	{roomArg1 = 'uint16_t'},-- speed
	{roomArg2 = 'uint16_t'},-- speed2
}

-- enemy sets have a list of entries
-- each entry points to an enemy and a palette
local enemyGFX_t = struct'enemyGFX_t'{
	{enemyAddr = 'uint16_t'},	-- matches enemies[].addr
	{palette = 'uint16_t'},
}

-- http://metroidconstruction.com/SMMM/fx_values.txt
local fx1_t = struct'fx1_t'{
	-- bank $83, ptr to door data.  0 means no door-specific fx
	{doorSelect = 'uint16_t'},				-- 0
	-- starting height of water/lava/acid
	{liquidSurfaceStart = 'uint16_t'},		-- 2
	-- ending height of water
	{liquidSurfaceNew = 'uint16_t'},		-- 4

	--[[ from metroidconstruction.com/SMMM:
	how long until the water/lava/acid starts to rise or lower. For rooms with liquid, you must use a value between 01 (instantly) and FF (a few seconds). For rooms with no liquid, use 00.
	For liquids moving up, use a surface speed value between FE00-FFFF. Examples: FFFE (absolute slowest), FFD0 (slow), FFD0 (decent speed), and FE00 (very fast).
	For liquids moving down, use a surface speed value between 0001-0100. Examples: 0001 (absolute slowest), 0020 (slow), 0040 (decent speed), 0100 (very fast). 
	--]]
	{liquidSurfaceDelay = 'uint8_t'},		-- 6

	-- liquid, fog, spores, rain, etc
	{fxType = 'uint8_t'},					-- 7
	
	-- lighting options: 02 = normal, 28 = dark visor room, 2a = darker yellow-visor room
	{a = 'uint8_t'},						-- 8
	
	-- prioritize/color layers
	{b = 'uint8_t'},						-- 9
	
	-- liquid options
	{c = 'uint8_t'},						-- 0xa
	
	{paletteFXFlags = 'uint8_t'},			-- 0xb
	{tileAnimateFlags = 'uint8_t'},			-- 0xc
	{paletteBlend = 'uint8_t'},				-- 0xd
	
	{last = 'uint16_t'},					-- 0xe
}

local bg_t = struct'bg_t'{
	{header = 'uint16_t'},
	{addr = 'uint16_t'},
	{bank = 'uint8_t'},
	-- skip the next 14 bytes
	{unknown1 = 'uint16_t'},
	{unknown2 = 'uint16_t'},
	{unknown3 = 'uint16_t'},
	{unknown4 = 'uint16_t'},
	{unknown5 = 'uint16_t'},
	{unknown6 = 'uint16_t'},
	{unknown7 = 'uint16_t'},
}

-- described in section 12 of metroidconstruction.com/SMMM
-- if a user touches a xx-9x-yy tile then the number in yy (3rd channel) is used to lookup the door_t to see where to go
-- This isn't the door so much as the information associated with its destination.
-- This doesn't reference the in-room door object so much as vice-versa.
-- I'm tempted to call this 'exit_t' ... since you don't need a door
local door_t = struct'door_t'{
	{dest_mdb = 'uint16_t'},				-- 0: points to the mdb_t to transition into
	
--[[
0x40 = change regions
0x80 = elevator
--]]
	{flags = 'uint8_t'},				-- 2

--[[
0 = right
1 = left
2 = down
3 = up
| 0x04 flag = door closes behind samus
--]]
	{direction = 'uint8_t'},			-- 3
	
	{capX = 'uint8_t'},					-- 4
	{capY = 'uint8_t'},					-- 5
	{screenX = 'uint8_t'},				-- 6	target room x offset to place you at?
	{screenY = 'uint8_t'},				-- 7	... y ...
	{distToSpawnSamus = 'uint16_t'},	-- 9
	{code = 'uint16_t'},				-- A
}

-- this is what the metroid ROM map says ... "Elevator thing"
-- two dooraddrs point to a uint16_t of zero, at $0188fc and $01a18a, and they point to structs that only take up 2 bytes
-- you find it trailing the door_t corresponding with the lift
local lift_t = struct'lift_t'{
	{zero = 'uint16_t'},
}

SMMap.plmCmdValueForName = table{
	
	-- I don't know about these ...

	-- probably scroll stuff
	exit_right = 0xb63b,
	--0xb63b: 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/07, 00/07, 00/07, 00/07, 00/1c, 00/1c, 01/01, 01/03, 01/03, 01/08, 01/08, 01/08, 01/08, 01/08, 01/08, 01/08, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/0f, 01/13, 01/13, 01/20, 01/24, 01/25, 01/28, 01/28, 01/28, 01/28, 01/28, 01/28, 01/2e, 01/2e, 01/34, 01/34, 02/04, 02/24, 02/24, 02/24, 02/24, 02/2d, 02/2d, 02/2d, 02/2d, 02/2d, 02/36, 02/36, 02/36, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/37, 02/3c, 02/3c, 02/3e, 02/3e, 02/41, 02/41, 02/41, 02/41, 02/41, 02/41, 02/41, 02/41, 02/41, 02/43, 02/43, 02/43, 02/43, 02/43, 02/43, 02/43, 02/45, 02/45, 02/45, 02/45, 02/45, 02/45, 02/45, 02/46, 02/46, 02/46, 02/46, 02/46, 02/46, 02/4b, 02/4b, 02/4b, 02/4b, 02/4b, 02/4b, 02/4b, 02/4b, 02/4b, 03/06, 03/06, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/0c, 04/1b, 04/1b, 04/1b, 04/1b, 04/1b, 04/1b, 04/1b, 04/1b, 04/1b, 04/24, 04/24, 04/24, 04/24, 04/24, 04/25, 04/25, 04/25, 04/25, 04/25, 04/25, 04/25, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a, 04/2a
	
	-- probably scroll stuff
	-- Crateria climb
	exit_left = 0xb63f,
	--0xb63f: 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 01/08, 01/08, 01/08, 01/08, 01/08
	
	-- probably scroll stuff
	-- in pink brinstar speed bird room - just below speed boost blocks - where the camera starts to scroll down as you fall
	exit_down = 0xb643,
	--0xb643: 01/08, 01/08, 01/08
	
	-- probably scroll stuff
	-- found in the bombable blocks between the intro room and the Gauntlet - to allow left-scrolling
	-- also found in the first room after the start, right at the point where the camera allows downward scrolling
	-- also found in the bombable blocks in the pink brinstar speed bird room
	exit_up = 0xb647,
	--0xb647: 00/00, 00/00, 00/00, 00/00, 00/00, 00/00, 00/00, 00/00, 00/00, 00/00, 00/00, 00/00, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 01/08, 01/08, 01/08, 01/08, 01/08, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/17, 01/17, 01/26, 01/26, 01/26, 01/26, 01/26, 01/26, 01/26, 01/26, 01/2c, 01/2c, 01/2c, 01/2c, 01/2c, 01/2c, 01/2c, 01/34, 01/34, 01/34, 01/34, 01/34, 01/34, 01/34, 01/34, 01/34, 01/34, 01/34, 01/34, 02/09, 02/09, 02/09, 02/09, 02/09, 02/09, 02/09, 02/09, 02/09, 02/1d, 02/1d, 02/21, 02/21, 02/21, 02/21, 02/21, 02/21, 02/21, 02/21, 02/22, 02/22, 02/22, 02/3e, 02/3e, 02/3e, 02/3e, 02/3e, 02/3e, 02/43, 02/43, 02/43, 02/45, 02/46, 02/46, 02/46, 02/46, 02/46, 02/46, 02/46, 02/48, 02/48, 02/48, 02/48, 02/48, 02/4b, 02/4b, 02/4b, 02/4b, 02/4b, 03/00, 03/00, 03/00, 03/00, 04/03, 04/03, 04/03, 04/03, 04/03, 04/03, 04/05, 04/05, 04/05, 04/05, 04/05, 04/05, 04/0b, 04/0b, 04/0b, 04/0b, 04/0b, 04/0b, 04/0d, 04/0d, 04/0d, 04/0d, 04/0d, 04/0d, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/24, 04/31, 04/31, 04/31


	map_station = 0xb6d3,
	--0xb6d3: 00/1b, 01/05, 02/2e, 03/09, 04/16

	energy_refill_station = 0xb6df,
	--0xb6df: 01/15, 01/31, 01/32, 02/2b, 02/39, 04/34, 05/09

	missile_refill_station = 0xb6eb,
	--0xb6eb: 01/07, 01/32, 04/2d, 05/09

	scrollmod = 0xb703,
	-- 0xb703: 00/00, 00/00, 00/00, 00/00, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/02, 00/07, 00/07, 00/08, 00/0f, 00/10, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/12, 00/13, 00/13, 00/13, 00/13, 00/13, 00/13, 00/14, 00/14, 00/19, 00/1c, 00/1c, 01/00, 01/00, 01/00, 01/00, 01/01, 01/03, 01/03, 01/03, 01/04, 01/08, 01/08, 01/08, 01/09, 01/09, 01/09, 01/09, 01/09, 01/09, 01/0c, 01/0c, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0e, 01/0f, 01/0f, 01/10, 01/10, 01/10, 01/10, 01/13, 01/17, 01/20, 01/24, 01/24, 01/24, 01/25, 01/26, 01/28, 01/28, 01/28, 01/28, 01/28, 01/28, 01/2a, 01/2a, 01/2a, 01/2a, 01/2c, 01/2c, 01/2c, 01/2c, 01/2c, 01/2e, 01/34, 01/34, 01/34, 01/34, 02/04, 02/07, 02/07, 02/07, 02/07, 02/09, 02/09, 02/09, 02/0d, 02/0d, 02/0d, 02/0d, 02/19, 02/1d, 02/1d, 02/1d, 02/21, 02/21, 02/21, 02/21, 02/22, 02/22, 02/22, 02/24, 02/24, 02/26, 02/2d, 02/2d, 02/2d, 02/35, 02/35, 02/36, 02/36, 02/36, 02/37, 02/37, 02/3c, 02/3c, 02/3e, 02/3e, 02/3e, 02/3e, 02/3e, 02/3e, 02/41, 02/43, 02/43, 02/43, 02/45, 02/45, 02/45, 02/45, 02/45, 02/45, 02/46, 02/46, 02/46, 02/46, 02/46, 02/46, 02/46, 02/46, 02/46, 02/48, 02/48, 02/48, 02/4b, 02/4b, 02/4b, 02/4b, 03/00, 03/00, 03/00, 03/00, 03/04, 03/04, 03/04, 03/04, 03/04, 03/04, 03/04, 03/04, 03/04, 03/04, 03/06, 03/06, 03/08, 03/08, 03/08, 03/08, 03/0d, 03/0d, 04/01, 04/01, 04/01, 04/01, 04/01, 04/01, 04/03, 04/03, 04/03, 04/03, 04/04, 04/05, 04/05, 04/09, 04/09, 04/0a, 04/0b, 04/0b, 04/0c, 04/0d, 04/0d, 04/0e, 04/0e, 04/1b, 04/24, 04/24, 04/24, 04/24, 04/25, 04/25, 04/2a, 04/2a, 04/31, 04/31, 04/31
	
	--0xb70b: 01/00, 01/24, 02/03, 02/36, 04/13, 05/00

	save_station = 0xb76f,
	--0xb76f: 00/04, 01/1b, 01/1e, 01/1f, 01/36, 01/37, 02/0f, 02/2f, 02/32, 02/33, 02/34, 02/4c, 03/0f, 04/00, 04/17, 04/29, 04/2c, 05/0d, 05/12

	-- found in the room before speed booster.  placed in the upper right corner.  maybe to do with the triggered lava raising?
	lava_raise_maybe = 0xb8ac,
	--0xb8ac: 02/1b
	
	-- this is in the chozo boss room.  the door starts open but closes later.
	door_grey_right_closing = 0xbaf4,

	-- in the top room of Wrecked Ship
	--0xbb05: 03/02, 03/02

	-- gates
	normal_open_gate = 0xc826,		-- not used
	normal_close_gate = 0xc82a,		-- open/close gate (starting closed)
	flipped_open_gate = 0xc82e,		-- not used
	flipped_close_gate = 0xc832,	-- not used
	shot_gate_top = 0xc836,			-- blue top of a open/close gate
	-- grey
	door_grey_right = 0xc842,
	door_grey_left = 0xc848,
	door_grey_down = 0xc84e,
	door_grey_up = 0xc854,
	-- orange
	door_orange_right = 0xc85a,
	door_orange_left = 0xc860,
	door_orange_down = 0xc866,
	door_orange_up = 0xc86c,
	-- green
	door_green_right = 0xc872,
	door_green_left = 0xc878,
	door_green_down = 0xc87e,
	door_green_up = 0xc884,
	-- red
	door_red_right = 0xc88a,
	door_red_left = 0xc890,
	door_red_down = 0xc896,			-- not used
	door_red_up = 0xc89c,			-- not used
	-- blue
	-- where are the regular blue doors? in the separate door structures / in the map tile data?
	-- none of the door_blue_* are used: 
	door_blue_right_opening = 0xc8a2,
	door_blue_left_opening = 0xc8a8,
	door_blue_down_opening = 0xc8ae,
	door_blue_up_opening = 0xc8b4,
	door_blue_right_closing = 0xc8ba,
	door_blue_left_closing = 0xc8be,
	door_blue_down_closing = 0xc8c2,
	door_blue_up_closing = 0xc8c6,

--[[ these are all the door plm codes that are used in the game:
0xc82a: 01/0d, 01/19, 01/24, 02/0c, 02/13, 02/1e, 02/22, 02/27, 02/38, 04/03, 04/07
0xc836: 01/0d, 01/19, 01/24, 02/0c, 02/13, 02/1e, 02/22, 02/27, 02/38, 04/03, 04/07
0xc842: 00/00, 00/00, 00/02, 00/05, 00/12, 00/12, 00/12, 00/12, 00/12, 00/13, 01/00, 01/02, 01/0c, 01/19, 01/25, 01/2b, 01/2d, 01/2d, 01/2f, 01/2f, 02/0d, 02/37, 02/37, 02/3a, 02/3a, 03/02, 03/02, 03/04, 03/04, 04/14, 04/22, 04/37, 04/37, 05/02, 05/02, 05/03, 05/03, 05/06, 05/06, 05/07, 05/07
0xc848: 00/00, 00/02, 00/02, 00/02, 00/12, 00/12, 00/12, 00/13, 00/13, 00/15, 01/0a, 01/0e, 01/19, 01/2a, 01/2d, 01/2d, 01/2f, 01/2f, 00/33, 02/3a, 02/3a, 02/3e, 02/47, 03/00, 03/02, 03/02, 03/04, 03/04, 03/0a, 03/0a, 04/11, 04/31, 04/32, 04/32, 04/37, 04/37, 05/01, 05/01, 05/06, 05/06, 05/10, 05/11
0xc84e: 00/02, 03/02, 05/04, 05/04
0xc854: 01/0a, 02/0a, 02/0a, 05/0f
0xc85a: 00/00, 00/00, 00/00, 00/07, 00/12, 00/12, 01/09, 01/0d
0xc860: 01/20, 01/24, 02/03, 02/22

orange door down:
0xc866: 00/07, 00/0c, 02/45

orange door up:
0xc86c: 00/0f

green door right:
0xc872: 00/00, 00/00, 00/00, 00/05, 01/09, 01/11, 01/28, 01/2e, 02/01, 02/1a, 04/0c, 04/28, 04/28

green door left:
0xc878: 01/06, 01/13, 01/16, 01/20, 01/24, 01/24, 02/03, 02/1a, 02/46

green door down:
0xc87e: 01/0b, 01/0b, 02/09, 03/04, 03/04, 04/14

green door up:
0xc884: 04/1b

red door right:
0xc88a: 00/02, 00/02, 00/16, 00/16, 00/1c, 01/00, 01/00, 01/03, 01/09, 01/0f, 01/0f, 02/02, 02/11, 02/1b, 02/1d, 02/1e, 04/01, 04/01, 04/04, 04/05, 04/0e, 04/13, 04/28, 05/08

red door left:
0xc890: 01/00, 01/00, 01/00, 01/09, 01/21, 02/03, 02/0e, 03/06, 04/21, 05/0c
--]]


	-- something in the intro door of the room after the mother brain battle
	--0xc8ca: 05/0e
	
	motherbrain_in_a_jar = 0xd6de,

	-- in the crateria chozo boss room next to the item
	--0xd6ea: 00/15, 00/15

	powerbomb_glass_tube = 0xd70c,

	-- in Crateria first room after start, just past the bombable block wall
	-- in Crateria climb, but off screen
	-- in the room before the chozo boss, middle of the first room
	-- in the room of the chozo boss, middle of the room
	-- also in a lot of Tourian rooms
	--0xdb44: 00/00, 00/02, 00/12, 00/15, 00/16, 05/01, 05/01, 05/02, 05/02, 05/03, 05/03, 05/04, 05/04, 05/0e, 05/0f, 05/10, 05/11

	door_eye_left_part2 = 0xdb48,
	door_eye_left = 0xdb4c,
	door_eye_left_part3 = 0xdb52,
	
	door_eye_right_part2 = 0xdb56,
	door_eye_right = 0xdb5a,
	door_eye_right_part3 = 0xdb60,

	-- all in Draygon's room...
	
	draygon_turret_left = 0xdf59,			-- on the left wall, pointing to the right
	--0xdf59: 04/37, 04/37

	draygon_turret_left_broken = 0xdf65,	-- on the left wall, pointing to the right
	--0xdf65: 04/37, 04/37
	
	draygon_turret_right = 0xdf71,			-- on the right wall, pointing to the left
	--0xdf71: 04/37, 04/37, 04/37, 04/37

	-- draygon_turret_right_broken = 0xdf7d, -- (me guessing) ... on the right, pointing to the left

	-- items: (this is just like SMItems.itemTypes in sm-items.lua
	item_energy 		= 0xeed7,
	item_missile 		= 0xeedb,
	item_supermissile 	= 0xeedf,
	item_powerbomb		= 0xeee3,
	item_bomb			= 0xeee7,
	item_charge			= 0xeeeb,
	item_ice			= 0xeeef,
	item_hijump			= 0xeef3,
	item_speed			= 0xeef7,
	item_wave			= 0xeefb,
	item_spazer 		= 0xeeff,
	item_springball		= 0xef03,
	item_varia			= 0xef07,
	item_gravity		= 0xef0b,
	item_xray			= 0xef0f,
	item_plasma			= 0xef13,
	item_grappling		= 0xef17,
	item_spacejump 		= 0xef1b,
	item_screwattack	= 0xef1f,
	item_morph			= 0xef23,
	item_reserve		= 0xef27,
}

-- add 84 = 0x54 to items to get to chozo , another 84 = 0x54 to hidden
for _,k in ipairs(SMMap.plmCmdValueForName:keys():filter(function(k)
	return k:match'^item_'
end)) do
	local v = SMMap.plmCmdValueForName[k]
	SMMap.plmCmdValueForName[k..'_chozo'] = v + 0x54
	SMMap.plmCmdValueForName[k..'_hidden'] = v + 2*0x54
end


SMMap.plmCmdNameForValue = SMMap.plmCmdValueForName:map(function(v,k) return k,v end)

local RoomState = class()
function RoomState:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.fx1s = self.fx1s or table()
	self.bgs = self.bgs or table()
end

function RoomState:setPLMSet(plmset)
	if self.plmset then
		self.plmset.roomStates:removeObject(self)
	end
	self.plmset = plmset
	if self.plmset then
		self.plmset.roomStates:insert(self)
	end
end
function RoomState:setEnemySpawnSet(enemySpawnSet)
	if self.enemySpawnSet then
		self.enemySpawnSet.roomStates:removeObject(self)
	end
	self.enemySpawnSet = enemySpawnSet
	if self.enemySpawnSet then
		self.enemySpawnSet.roomStates:insert(self)
	end
end
function RoomState:setEnemyGFXSet(enemyGFXSet)
	if self.enemyGFXSet then
		self.enemyGFXSet.roomStates:removeObject(self)
	end
	self.enemyGFXSet = enemyGFXSet
	if self.enemyGFXSet then
		self.enemyGFXSet.roomStates:insert(self)
	end
end


local PLMSet = class()

function PLMSet:init(args)
	self.addr = args.addr	--optional
	self.plms = table(args.plms)
	self.scrollmods = table()
	self.roomStates = table()
end

function SMMap:newPLMSet(args)
	local plmset = PLMSet(args)
	self.plmsets:insert(plmset)
	return plmset
end

-- table of all unique plm regions
-- m is only used for MemoryMap.  you have to add to plmset.mdbs externally
function SMMap:mapAddPLMSetFromAddr(addr, m)
	local rom = self.rom
	local startaddr = addr
	local _,plmset = self.plmsets:find(nil, function(plmset) return plmset.addr == addr end)
	if plmset then return plmset end

	local startaddr = addr

	local plms = table()
	while true do
		local ptr = ffi.cast('plm_t*', rom+addr)
		if ptr.cmd == 0 then 
			-- include plm term
			addr = addr + 2
			break 
		end

		--inserting the struct by-value
		-- why did I have to make a copy?
		plms:insert(ffi.new('plm_t', ptr[0]))
		addr = addr + ffi.sizeof'plm_t'
	end
	
	-- nil plmset for no plms
	--if #plms == 0 then return end

	local plmset = self:newPLMSet{
		addr = startaddr,
		plms = plms,
	}

	-- now interpret the plms...
	for _,plm in ipairs(plmset.plms) do
		if plm.cmd == self.plmCmdValueForName.scrollmod then
			local startaddr = 0x70000 + plm.args
			local addr = startaddr
			local data = table()
			while true do
				local screen = rom[addr] addr=addr+1
				-- including the 0x80 terminator
				data:insert(screen)
				if screen == 0x80 then break end
				local scroll = rom[addr] addr=addr+1
				data:insert(scroll)
			end
			assert(addr - startaddr == #data)
			plmset.scrollmods:insert{
				addr = startaddr,
				data = data,
			}
		end
	end

	return plmset
end


function SMMap:mapAddEnemySpawnSet(addr)
	local rom = self.rom
	local _,enemySpawnSet = self.enemySpawnSets:find(nil, function(enemySpawnSet)
		return enemySpawnSet.addr == addr
	end)
	if enemySpawnSet then return enemySpawnSet end

	local startaddr = addr
	local enemySpawns = table()
	local enemiesToKill 
	while true do
		local ptr = ffi.cast('enemySpawn_t*', rom + addr)
		if ptr.enemyAddr == 0xffff then
			-- include term and enemies-to-kill
			addr = addr + 2
			break
		end
		enemySpawns:insert(ffi.new('enemySpawn_t', ptr[0]))
		addr = addr + ffi.sizeof'enemySpawn_t'
	end
	enemiesToKill = rom[addr]
	addr = addr + 1

	local enemySpawnSet = {
		addr = startaddr,
		enemySpawns = enemySpawns,
		enemiesToKill = enemiesToKill, 
		roomStates = table(),
	}
	self.enemySpawnSets:insert(enemySpawnSet)
	return enemySpawnSet
end

function SMMap:mapAddEnemyGFXSet(addr)
	local rom = self.rom
	local _,enemyGFXSet = self.enemyGFXSets:find(nil, function(enemyGFXSet)
		return enemyGFXSet.addr == addr
	end)
	if enemyGFXSet then return enemyGFXSet end

	local startaddr = addr
	local enemyGFXs = table()

	-- NOTICE the name is padded at the beginning with terms
	-- and it is 8 bytes long
	local name = range(0,7):map(function(i) return string.char(rom[startaddr-8+i]) end):concat()

	while true do
		if ffi.cast('uint16_t*', rom+addr)[0] == 0xffff then break end
		local ptr = ffi.cast('enemyGFX_t*', rom+addr)
		enemyGFXs:insert(ffi.new('enemyGFX_t', ptr[0]))
		addr = addr + ffi.sizeof'enemyGFX_t'
	end

	local enemyGFXSet = {
		addr = startaddr,
		name = name,
		enemyGFXs = enemyGFXs,
		roomStates = table(),
	}
	self.enemyGFXSets:insert(enemyGFXSet)
	return enemyGFXSet
end


-- table of all unique bgs.
-- each entry has .addr and .ptr = (bg_t*)(rom+.addr)
-- doesn't create duplicates -- returns a previous copy if it exists
function SMMap:mapAddBG(addr)
	local _,bg = self.bgs:find(nil, function(bg) return bg.addr == addr end)
	if bg then return bg end
	bg = {
		addr = addr,
		ptr = ffi.cast('bg_t*', self.rom + addr),
		-- list of all m's that use this bg
		mdbs = table(),
	}
	self.bgs:insert(bg)
	return bg
end


function SMMap:mapAddFX1(addr)
	local _,fx1 = self.fx1s:find(nil, function(fx1) return fx1.addr == addr end)
	if fx1 then return fx1 end
	fx1 = {
		addr = addr,
		ptr = ffi.cast('fx1_t*', self.rom + addr),
		mdbs = table(),
	}
	self.fx1s:insert(fx1)
	return fx1
end


local Room = class()
SMMap.Room = Room

function Room:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.mdbs = table()
end

function Room:getData()
	local w, h = self.width, self.height
	local ch12 = ffi.new('uint8_t[?]', 2 * w * h)
	local ch3 = ffi.new('uint8_t[?]', w * h)
	local k = 0
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			ch12[0 + 2 * k] = self.blocks[0 + 3 * k]
			ch12[1 + 2 * k] = self.blocks[1 + 3 * k]
			ch3[k] = self.blocks[2 + 3 * k]
			k = k + 1
		end
	end

	return mergeByteArrays(
		self.head,
		ch12,
		ch3,
		self.tail
	)
end

--[[ for the room tile data:
looks like this is channel 2:
lower nibble channel 2 bits:
bit 0
bit 1
bit 2 = flip up/down
bit 3 = flip left/right

upper-nibble channel 2 values:
0 = empty
1 = slope
2 = spikes
	channel 3 lo:
		0000b = 0 = 1x1 spike solid
		0010b = 2 = 1x1 spike non-solid 
3 = push
	channel 3 lo:
		0000b = 0 = down force x1 (maridia quicksand top of two secrets)
		0001b = 1 = down force x2 (maridia quicksand in bottom of two secret rooms)
		0010b = 2 = down force x3 (maridia quicksand)
		0011b = 3 = down force x4 - can't jump up from (maridia sand downward shafts)
		0101b = 5 = down force x.5 - (maridia sand falling from ceiling)
		1000b = 8 = right
		1001b = 9 = left
4 =
5 = copy what's to the left
6 =
7 =
8 = solid
9 = door
a = spikes / invis blocks
	channel 3:
		0000b = 0 = spikes solid 
		0011b = 3 = spikes non-solid destroyed by walking chozo statue
		1110b = e = invis blocks
		1111b = f = spikes non-solid destroyed by walking chozo statue
				  = also solid sand blocks destroyed by that thing in maridia
b = crumble / speed
	channel 3 lo:
		0000b = 0 = 1x1 crumble regen
		0001b = 1 = 2x1 crumble regen
		0010b = 2 = 1x2 crumble regen
		0011b = 3 = 2x2 crumble regen
		
		0100b = 4 = 1x1 crumble noregen
		0101b = 5 = 2x1 crumble noregen
		0110b = 6 = 1x1 crumble noregen
		0111b = 7 = 2x2 crumble noregen
		
		1110b = e = 1x1 speed regen
		1111b = f = 1x1 speed noregen
c = break by beam / supermissile / powerbomb
	channel 3 lo:
		0000b = 0 = 1x1 beam regen
		0001b = 1 = 1x2 beam regen
		0010b = 2 = 2x1 beam regen
		0011b = 3 = 2x2 beam regen
		
		0100b = 4 = 1x1 beam noregen
		0101b = 5 = 2x1 beam noregen
		0110b = 6 = 1x2 beam noregen
		0111b = 7 = 2x2 beam noregen
		
		1001b = 9 = 1x1 power bomb noregen
		1010b = a = 1x1 super missile regen
		1011b = b = 1x1 super missile noregen
d = copy what's above 
e = grappling
	channel 3 bit 1:
		0000b = 0 = 1x1 grappling
		0001b = 1 = 1x1 grappling breaking regen
		0010b = 2 = 1x1 grappling breaking noregen
f = bombable 
	channel 3 lo:
		0000b = 0 = 1x1 bomb regen
		0001b = 1 = 2x1 bomb regen
		0010b = 2 = 1x2 bomb regen
		0011b = 3 = 2x2 bomb regen
		
		0100b = 4 = 1x1 bomb noregen
		0101b = 5 = 2x1 bomb noregen
		0110b = 6 = 1x2 bomb noregen
		0111b = 7 = 2x2 bomb noregen
--]]

-- this is ch2hi
Room.tileTypes = {
	empty 				= 0x0,
	slope				= 0x1,
	spikes				= 0x2,
	push				= 0x3,
	copy_left 	 	 	= 0x5,
	solid 				= 0x8,
	door				= 0x9,
	spikes_or_invis		= 0xa,
	crumble_or_speed	= 0xb,
	breakable 			= 0xc,
	copy_up 			= 0xd,
	grappling			= 0xe,
	bombable			= 0xf,
}
-- this is ch3lo:ch2hi
Room.extTileTypes = {
	spike_solid_1x1			= 0x20,
	spike_notsolid_1x1		= 0x22,
	push_quicksand1			= 0x30,
	push_quicksand2			= 0x31,
	push_quicksand3			= 0x32,
	push_quicksand4			= 0x33,
	push_quicksand1_2		= 0x35,
	push_conveyor_right		= 0x38,
	push_conveyor_left		= 0x39,
	spike_solid2_1x1		= 0xa0,
	spike_notsolid2_1x1		= 0xa3,
	invisble_solid			= 0xae,
	spike_notsolid3_1x1		= 0xaf,
	crumble_1x1_regen		= 0xb0,
	crumble_2x1_regen		= 0xb1,
	crumble_1x2_regen		= 0xb2,
	crumble_2x2_regen		= 0xb3,
	crumble_1x1				= 0xb4,
	crumble_2x1				= 0xb5,
	crumble_1x2				= 0xb6,
	crumble_2x2				= 0xb7,
	speed_regen				= 0xbe,
	speed					= 0xbf,
	beam_1x1_regen			= 0xc0,
	beam_2x1_regen			= 0xc1,
	beam_1x2_regen			= 0xc2,
	beam_2x2_regen			= 0xc3,
	beam_1x1				= 0xc4,
	beam_2x1				= 0xc5,
	beam_1x2				= 0xc6,
	beam_2x2				= 0xc7,
	powerbomb_1x1			= 0xc9,
	supermissile_1x1_regen	= 0xca,
	supermissile_1x1		= 0xcb,
	grappling				= 0xe0,
	grappling_break_regen 	= 0xe1,
	grappling_break			= 0xe2,
	bombable_1x1_regen		= 0xf0,
	bombable_2x1_regen		= 0xf1,
	bombable_1x2_regen		= 0xf2,
	bombable_2x2_regen		= 0xf3,
	bombable_1x1			= 0xf4,
	bombable_2x1			= 0xf5,
	bombable_1x2			= 0xf6,
	bombable_2x2			= 0xf7,
}
Room.extTileTypeNameForValue = setmetatable(table.map(Room.extTileTypes, function(v,k) return k,v end), nil)

Room.oobType = Room.tileTypes.solid -- consider the outside to be solid

function Room:getTileData(x,y)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = 3 * (x + self.width * y)
	local ch1 = self.blocks[0 + bi]
	local ch2 = self.blocks[1 + bi]
	local ch3 = self.blocks[2 + bi]
	return ch1, ch2, ch3
end

function Room:setTileData(x,y,ch1,ch2,ch3)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = 3 * (x + self.width * y)
	self.blocks[0 + bi] = ch1
	self.blocks[1 + bi] = ch2
	self.blocks[2 + bi] = ch3
end


-- for position x,y, returns the real x,y that the tile type is determined by
function Room:getCopySource(x,y)
	while true do
		if x < 0 or x >= self.width
		or y < 0 or y >= self.height
		then 
			return x,y
		end
	
		local ch1, ch2, ch3 = self:getTileData(x,y)
		local ch2hi = bit.band(0xf, bit.rshift(ch2, 4))
		-- TODO the next channel states how far to copy
		-- so we really have to scan the whole map (up front)
		-- and then make a list keyed by the copy-source position, listing all blocks which do copy that copy-source position
		if ch2hi == self.tileTypes.copy_up then
			y = y - 1
		elseif ch2hi == self.tileTypes.copy_left then
			x = x - 1
		else
			return x,y
		end
	end
	error'here'
end

-- returns true if this is a 'is copy up / left' tile
function Room:isCopy(x,y)
	-- don't use getTileType because this uses the copy_*
	local _, ch2 = self:getTileData(x,y)
	local ch2hi = bit.band(0xf, bit.rshift(ch2, 4))
	return ch2hi == self.tileTypes.copy_left 
		or ch2hi == self.tileTypes.copy_up
end

-- returns true if this is targetted by a 'copy up / left' tile
function Room:isCopied(x,y)
	local copiedRight = false
	local copiedUp = false
	if x < self.width-1 then
		local _, ch2R = self:getTileData(x+1,y)
		local ch2Rhi = bit.band(0xf, bit.rshift(ch2R, 4))
		copiedRight = ch2Rhi == self.tileTypes.copy_left
	end
	if y < self.height-1 then
		local _, ch2U = self:getTileData(x,y+1)
		local ch2Uhi = bit.band(0xf, bit.rshift(ch2U, 4))
		copiedUp = ch2Uhi == self.tileTypes.copy_up
	end
	return copiedRight and copiedUp, copiedRight, copiedUp
end

-- run this from a copied tile
-- returns a quick span right then a quick span down of all copies 
function Room:getAllCopyLocs(x,y)
	local locs = table{x,y}
	local checked = table{x,y}
	while #checked > 0 do
		local ch = checked:remove()
		local _, ch2R = self:getTileData(x+1,y)
error'finish me - but you might have to redo all copies'
	end
end

-- if a block is a copy or is copied then replace it and all copies with its copy source
function Room:splitCopies(x,y)
print'finish me plz'
do return end
	if self:isCopy(x,y) or self:isCopied(x,y) then
		local sx,sy = self:getCopySource(x,y)
		local _, ett = self:getTileType(sx,sy)
		for _,pos in ipairs(self:getAllCopyLocs(sx,sy)) do
			self:setTileType(pos[1], pos[2], ett)
		end
	end
end



--[[
returns the tile type (ch2 hi) and the extended tile type (ch2 hi:ch3 lo)
--]]
function Room:getTileType(x,y)
	x,y = self:getCopySource(x,y)
	if x < 0 or x >= self.width
	or y < 0 or y >= self.height
	then 
		return self.oobType
	end
	assert(not self:isCopy(x,y))
	local ch1, ch2, ch3 = self:getTileData(x,y)
	local ch2hi = bit.band(0xf0, ch2)
	local ch3lo = bit.band(0x0f, ch3)
	local ett = bit.bor(ch3lo, ch2hi)
	return bit.rshift(ch2hi, 4), ett
end

function Room:getExtTileType(x,y)
	return select(2, self:getTileType(x,y))
end

-- set the 'ett' 
function Room:setExtTileType(x,y,ett)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = 3 * (x + self.width * y)
	local b = self.blocks[1 + bi]
	local c = self.blocks[2 + bi]

	-- TODO if it is a copy tile then break whatever it is copying from
	local ch3lo = bit.band(0x0f, ett)
	local ch2hi = bit.band(0xf0, ett)
--print('setting '..x..', '..y..' ett '..('%x (%x, %x)'):format(ett, bit.rshift(ch2hi, 4), ch3lo))
	local a,b,c = self:getTileData(x,y)
--print(' data was '..('%02x %02x %02x'):format(a,b,c))	
	b = bit.bor(bit.band(b, 0x0f), ch2hi)
	c = bit.bor(bit.band(c, 0xf0), ch3lo)
--print(' data now '..('%02x %02x %02x'):format(a,b,c))	

	self.blocks[1 + bi] = b
	self.blocks[2 + bi] = c
end

-- notice this asks 'is is the 'solid' type?'
-- it does not ask 'is it a solid collidable block?'
function Room:isSolid(x,y) 
	return self:getTileType(x,y) == self.tileTypes.solid
end

function Room:isAccessible(x,y) 
	local tt, ett = self:getTileType(x,y)
	return tt == self.tileTypes.empty 
		or tt == self.tileTypes.crumble_or_speed
		or tt == self.tileTypes.breakable
		or ett == self.extTileTypes.grappling_break
		or ett == self.extTileTypes.grappling_break_regen
		or tt == self.tileTypes.bombable
end

--[[
TODO there's a small # of borders inaccessible
how to determine them?
1) flood fill per-room, starting at all doors
2) just manually excise them
they are:
landing room, left side of the room
first missile ever, under the floor
vertical of just about all the lifts in the game
top left of maridia's big room in the top left of the map
the next room over, the crab room, has lots of internal borders
the next room over from that, the hermit crab room, has lots of internal borders
the speed room before the mocktroids has a few internal borders
--]]
function Room:isBorder(x,y)
	--if x == 0 or y == 0 or x == self.width-1 or y == self.height-1 then return false end
	if self:isSolid(x,y) then
		for i,offset in ipairs{
			{1,0},
			{-1,0},
			{0,1},
			{0,-1},
		} do
			if self:isAccessible(x+offset[1], y+offset[2]) then 
				return true
			end
		end
	end
	return false
end

function Room:isBorderAndNotCopy(x,y)
	return self:isBorder(x,y) 
		and not self:isCopy(x,y) 
		and not self:isCopied(x,y)
end



-- this is the block data of the rooms
function SMMap:mapAddRoom(addr, m)
	local _,room = self.rooms:find(nil, function(room) 
		return room.addr == addr 
	end)
	if room then 
		-- rooms can come from separate mdb_t's
		-- which means they can have separate widths & heights
		-- so here, assert that their width & height matches
		assert(16 * room.mdbs[1].ptr.width == room.width, "expected room width "..room.width.." but got "..m.ptr.width)
		assert(16 * room.mdbs[1].ptr.height == room.height, "expected room height "..room.height.." but got "..m.ptr.height)
		return room 
	end
	
	local roomaddrstr = ('$%06x'):format(addr)
--print('roomaddr '..roomaddrstr)
	
	-- then we decompress the next 0x10000 bytes ...
--print('decompressing address '..('0x%06x'):format(addr))
	local data, compressedSize = lz.decompress(self.rom, addr, 0x10000)
--print('decompressed from '..compressedSize..' to '..ffi.sizeof(data))
	
	local ofs = 0
	local head = byteArraySubset(data, ofs, 2) ofs=ofs+2
	local w = m.ptr.width * 16
	local h = m.ptr.height * 16
	local ch12 = byteArraySubset(data, ofs, 2*w*h) ofs=ofs+2*w*h
	local ch3 = byteArraySubset(data, ofs, w*h) ofs=ofs+w*h -- referred to as 'bts' = 'behind the scenes' in some docs.  I'm just going to interleave everything.
	local blocks = ffi.new('uint8_t[?]', 3 * w * h)
	local k = 0
	for j=0,h-1 do
		for i=0,w-1 do
			blocks[0 + 3 * k] = ch12[0 + 2 * k]
			blocks[1 + 3 * k] = ch12[1 + 2 * k]
			blocks[2 + 3 * k] = ch3[k]
			k = k + 1
		end
	end
	local tail = byteArraySubset(data, ofs, ffi.sizeof(data) - ofs)
	assert(ofs <= ffi.sizeof(data), "didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..ffi.sizeof(data))

	-- keep track of doors
	
	-- ok, this correlates with the door plms, so it is useful
	--  but it isn't general to all exits
	local doors = table()	-- x,y,w,h
	-- so that's where this comes in.  it is general to all exits.
	-- 	key is the exit, value is a list of all positions of each exit xx9xyy block
	local blocksForExit = table()
	for j=0,h-1 do	-- ids of horizontal regions (up/down doors) are 2 blocks from the 4xfffefd pattern
		for i=0,w-1 do
			local a = blocks[0 + 3 * (i + w * j)]
			local b = blocks[1 + 3 * (i + w * j)]
			local c = blocks[2 + 3 * (i + w * j)]

-- [[
-- look for 0x9x in ch2 of of room.blocks
			if bit.band(b, 0xf0) == 0x90 then
				local exitIndex = c
				blocksForExit[exitIndex] = blocksForExit[exitIndex] or table()
				blocksForExit[exitIndex]:insert{i,j}
			end
--]]

--[[
doors are 40 through 43, followed by ff, fe, fd, either horizontally or vertically
 and then next to the 4 numbers, offset based on the door dir 40-43 <-> x+1,x-1,y+2,y-2, 
 will be the door_t index, repeated 4 times.
 for non-blue doors, this will match up with a plm in the roomstate that has x,y matching the door's location
 for blue doors, no plm is needed
however exits with no doors: 
 	* 00/0d the room to the right of the ship, exits 0 & 1 
 	* 01/09 the tall pink brinstar room, exit 5
 	* 04/01 maridia tube room, exits 1 & 2
 	* 04/0e maridia broken tube crab room, exits 0 & 1
 	* between maridia tall room 04/04 (exit 4) and maridia balloon room 04/08 (exit 4)
		-- this one is really unique, since the rest of them would always be 4 indexes in a row, and always at the same offsets %16 depending on their direction, (not always on the map edge)
			but 04/04 is only a single 04 on the edge of the map surrounded by 0's
			and 04/08 is two 0404's in a row, in the middle of the map, surrounded by 0's
	* 04/19 maridia upper right sandpit start
	* 04/1a maridia where sand pit #1 falls into. there's a third door_t for the sand entrance, 
			but no 02's in ch3 
	* 04/1d maridia sand pit #1.  has two door_t's.  only one is seen in the ch3's: exit 1 in the floor
	* 04/1e maridia sand pit #2.  same as #1 
	* 04/1f maridia sandfall room #1 ... has no up exit, but the bottom is all 01 tiles for exit #1
	* 04/20 maridia sandfall room #2 same.  interesting that there is no exit #0 used, only exit #1.
		the roomstate says there are two doors though, but no door for index 0 can be seen.
	* 04/21 maridia big pink room with two sand exits to 04/1f (exit 1) and 04/20 (exit 2)
		-- these are a row of 80 tiles over a row of exit # tiles 
	* 04/22 maridia upper right sandpit end
 	* 04/27 where sand pit 04/2b ends up
 	* 04/2b maridia room after botwoon, has 4 doors, two are doors, two are sandpit exits (#1 & #2)
	* 04/2e maridia upper right sandpit middle
	* 04/2f sandpit down from room after botwoon 
 will only have their dest door_t number and a door_t entry ... no plm even
so how does the map know when to distinguish those tiles from ordinary 00,01,etc shot tiles, especially with no plm there?
 and esp when the destination door_t structure doesn't say anything about the location from where the door is?
--]]			
			if i >= 1 and i <= w-2 
			and j >= 2 and j <= h-3
			and c >= 0x40 and c <= 0x43 
			then
				-- here's the upper-left of a door.  now, which way is it facing
				if i<w-3
				and (c == 0x42 or c == 0x43)
				and blocks[2 + 3 * ((i+1) + w * j)] == 0xff 
				and blocks[2 + 3 * ((i+2) + w * j)] == 0xfe 
				and blocks[2 + 3 * ((i+3) + w * j)] == 0xfd 
				then
					-- if c == 0x42 then it's down, if c == 0x43 then it's up 
					local doorIndex = c == 0x42 
						and blocks[2 + 3 * ( i + w * (j+2))]
						or blocks[2 + 3 * ( i + w * (j-2))]
					doors:insert{
						x = i,
						y = j,
						w = 4,
						h = 1,
						dir = bit.band(3, c),
						index = doorIndex,
					}
				elseif j<h-3	-- TODO assert this
				and (c == 0x40 or c == 0x41)
				and blocks[2 + 3 * (i + w * (j+1))] == 0xff 
				and blocks[2 + 3 * (i + w * (j+2))] == 0xfe 
				and blocks[2 + 3 * (i + w * (j+3))] == 0xfd 
				then
					-- if c == 0x41 then it's left, if c == 0x40 then it's right
					local doorIndex = c == 0x40 
						and blocks[2 + 3 * ((i+1) + w * j)]
						or blocks[2 + 3 * ((i-1) + w * j)]
					doors:insert{
						x = i,
						y = j,
						w = 1,
						h = 4, 
						dir = bit.band(3, c),
						index = doorIndex,
					}
				else
					-- nothing, there's lots of other 40..43's out there
				end
			end
		end
	end

	local room = Room{
		addr = addr,
		mdbs = table(),
		roomStates = table(),
		-- this is just 16 * mdb's (width, height)
		width = w,
		height = h,
		-- rule of thumb: do not exceed this
		compressedSize = compressedSize,
		-- decompressed data (in order):
		head = head,	-- first 2 bytes of data
		blocks = blocks,	-- interleaved 2-byte and 1-byte bts into 3-byte room block data
		tail = tail,	-- last bytes after blocks 
		-- extra stuff I'm trying to keep track of
		doors = doors,
		blocksForExit = blocksForExit,
	}
	room.mdbs:insert(m)
	self.rooms:insert(room)
	return room
end


local function readCode(rom, addr, maxlen)
	local code = table()
	for i=0,maxlen-1 do
		local r = rom[addr] addr=addr+1
		code:insert(r)
		if r == 0x60 then break end
		if i == maxlen-1 then error("code read overflow") end
	end
	return code
end


function SMMap:mapAddLayerHandling(addr)
	local _,layerHandling = self.layerHandlings:find(nil, function(layerHandling)
		return layerHandling.addr == addr
	end)
	if layerHandling then return layerHandling end
	local layerHandling = {
		addr = addr,
		code = readCode(self.rom, addr, 0x100),
		roomStates = table(),
	}
	self.layerHandlings:insert(layerHandling)
	return layerHandling
end

SMMap.fx1Bank = 0x83
SMMap.doorBank = 0x83

-- each mdb and its roomstates, dooraddrs, and scrolldata are stored grouped together
SMMap.mdbBank = 0x8e
SMMap.roomStateBank = 0x8e	-- bank for roomselect_t.roomstate
SMMap.doorAddrBank = 0x8e	-- bank for mdb_t.doors
SMMap.scrollBank = 0x8f		-- if scrolldata is stored next to mdb, roomstate, and dooraddr, then why does it have a separate bank?
-- then between groups of mdbs (and their content) are groups of bg_t's and doorcodes
SMMap.bgBank = 0x8f			
SMMap.doorCodeBank = 0x8f
-- then comes a group o fplms, and then comes a group of layer handling
SMMap.layerHandlingBank = 0x8f
-- TODO if there was a 'plm bank' it would go here
-- and then we go back to some more mdbs

SMMap.enemySpawnBank = 0xa1
SMMap.enemyGFXBank = 0xb4

function SMMap:mapInit()
	local rom = self.rom

	-- check where the PLM bank is
	-- TODO this will affect the items.lua addresses
	self.plmBank = rom[0x204ac]
	
	self.mdbs = table()
	self.rooms = table()
	self.bgs = table()
	self.fx1s = table()
	self.layerHandlings = table()
	
	self.plmsets = table()
	self.enemySpawnSets = table()
	self.enemyGFXSets = table()

	--[[
	from $078000 to $079193 is plm_t data
	the first mdb_t is at $0791f8
	from there it is a dense structure of ...
	mdb_t
	roomselect's (in reverse order)
	roomstate_t's (in forward order)
	dooraddrs
	... then comes extra stuff, sometimes:
	scrolldata (which is in one place wedged into nowhere)
	plm scrollmod

	TODO don't check *every* byte from 0x8000 to 0xffff
	--]]
	for x=0x8000,0xffff do
		local data = rom + topc(self.mdbBank, x)
		local function read(ctype)
			local result = ffi.cast(ctype..'*', data)
			data = data + ffi.sizeof(ctype)
			return result[0]
		end

		local mptr = ffi.cast('mdb_t*', data)
		if (
			(data[12] == 0xE5 or data[12] == 0xE6) 
			and mptr.region < 8 
			and (mptr.width ~= 0 and mptr.width < 20) 
			and (mptr.height ~= 0 and mptr.height < 20)
			and mptr.gfxFlags < 0x10 
			and mptr.doors > 0x7F00
		) then
			
			local m = {
				roomStates = table(),
				doors = table(),
-- TODO bank-offset addr vs pc addr for all my structures ...
				addr = x,
				ptr = mptr,
			}	
			self.mdbs:insert(m)
			data = data + ffi.sizeof'mdb_t'

			-- events
			while true do
				local testcode = ffi.cast('uint16_t*',data)[0]
				
				local ctype
				if testcode == 0xe5e6 then 
					ctype = 'uint16_t'
				elseif testcode == 0xe612
				or testcode == 0xe629
				then
					ctype = 'roomselect_t'
				elseif testcode == 0xe5eb then
					-- this is never reached
					error'here' 
					-- I'm not using this just yet
					-- struct {
					-- 	uint16_t testcode;
					-- 	uint16_t testvaluedoor;
					--	uint16_t roomstate;
					-- }
				else
					ctype = 'roomselect2_t'
				end
				local rs = RoomState{
					m = m,
					select = ffi.cast(ctype..'*', data),
					select_ctype = ctype,	-- using for debug print only
				}
				m.roomStates:insert(rs)
				
				data = data + ffi.sizeof(ctype)

				if ctype == 'uint16_t' then break end	-- term
			end

			do
				-- after the last roomselect is the first roomstate_t
				local rs = m.roomStates:last()
				-- uint16_t select means a terminator
				assert(rs.select_ctype == 'uint16_t')
				rs.ptr = ffi.cast('roomstate_t*', data)
				data = data + ffi.sizeof'roomstate_t'

				-- then the rest of the roomstates come
				for _,rs in ipairs(m.roomStates) do
					if rs.select_ctype ~= 'uint16_t' then
						assert(not rs.ptr)
						local addr = topc(self.roomStateBank, rs.select[0].roomstate)
						rs.ptr = ffi.cast('roomstate_t*', rom + addr)
					end

					assert(rs.ptr)
				end

				-- I wonder if I can assert that all the roomstate_t's are in contiguous memory after the roomselect's ... 
				-- they sure aren't sequential
				-- they might be reverse-sequential
				-- sure enough, YES.  roomstates are contiguous and reverse-sequential from roomselect's
				--[[
				for i=1,#m.roomStates-1 do
					assert(m.roomStates[i+1].ptr + 1 == m.roomStates[i].ptr)
				end
				--]]

				for _,rs in ipairs(m.roomStates) do
					if rs.ptr.scroll > 0x0001 and rs.ptr.scroll ~= 0x8000 then
						local addr = topc(self.scrollBank, rs.ptr.scroll)
						local size = m.ptr.width * m.ptr.height
						rs.scrollData = range(size):map(function(i)
							return rom[addr+i-1]
						end)
					end
				end

				-- add plms in reverse order, because the roomstates are in reverse order of roomselects,
				-- and the plms are stored in-order with roomselects
				-- so now, when writing them out, they will be in the same order in memory as they were when being read in
				for i=#m.roomStates,1,-1 do
					local rs = m.roomStates[i]
					if rs.ptr.plm ~= 0 then
						local addr = topc(self.plmBank, rs.ptr.plm)
						local plmset = self:mapAddPLMSetFromAddr(addr, m)
						rs:setPLMSet(plmset)
					end
				end

				-- enemySpawnSet
				-- but notice, for writing back enemy spawn sets, sometimes there's odd padding in there, like -1, 3, etc
				for _,rs in ipairs(m.roomStates) do
					local enemySpawnSet = self:mapAddEnemySpawnSet(topc(self.enemySpawnBank, rs.ptr.enemySpawn))
					rs:setEnemySpawnSet(enemySpawnSet)
				end
				
				for _,rs in ipairs(m.roomStates) do
					local enemyGFXSet = self:mapAddEnemyGFXSet(topc(self.enemyGFXBank, rs.ptr.enemyGFX))
					rs:setEnemyGFXSet(enemyGFXSet)
				end

				-- some rooms use the same fx1 ptr
				-- and from there they are read in contiguous blocks until a term is encountered
				-- so I should make these fx1sets (like plmsets)
				-- unless -- another optimization -- is, if one room's fx1's (or plms) are a subset of another,
				-- then make one set and just put the subset's at the end
				-- (unless the order matters...)
				for _,rs in ipairs(m.roomStates) do
					local startaddr = topc(self.fx1Bank, rs.ptr.fx1)
					local addr = startaddr
					local retry
					while true do
						local cmd = ffi.cast('uint16_t*', rom+addr)[0]
						
						-- null sets are represented as an immediate ffff
						-- whereas sets of more than 1 value use 0000 as a term ...
						-- They can also be used to terminate a set of fx1_t
						if cmd == 0xffff then
							-- include terminator bytes in block length:
							rs.fx1term = true
							addr = addr + 2
							break
						end
						
						--if cmd == 0
						-- TODO this condition was in smlib, but m.doors won't be complete until after all doors have been loaded
						--or m.doors:find(nil, function(door) return door.addr == cmd end)
						--then
						if true then
							local fx1 = self:mapAddFX1(addr)
-- this misses 5 fx1_t's
local done = fx1.ptr.doorSelect == 0 
							fx1.mdbs:insert(m)
							rs.fx1s:insert(fx1)
							
							addr = addr + ffi.sizeof'fx1_t'

-- term of 0 past the first entry
if done then break end
						end
					end
				end
				
				for _,rs in ipairs(m.roomStates) do
					if rs.ptr.bgdata > 0x8000 then
						local addr = topc(self.bgBank, rs.ptr.bgdata)
						while true do
							local ptr = ffi.cast('bg_t*', rom+addr)
							
-- this is a bad test of validity
-- this says so: http://metroidconstruction.com/SMMM/ready-made_backgrounds.txt
-- in fact, I never read more than 1 bg, and sometimes I read 0
--[[
							if ptr.header ~= 0x04 then
								addr = addr + 8
								break
							end
--]]
							-- so bgs[i].addr is the address where bgs[i].ptr was found
							-- and bgs[i].ptr.bank,addr points to where bgs[i].data was found
							-- a little confusing
							local bg = self:mapAddBG(addr)
							bg.mdbs:insert(m)
							rs.bgs:insert(bg)
							addr = addr + ffi.sizeof'bg_t'
						
							addr=addr+8
							do break end
						end
					
						--[[ load data
						-- this worked fine when I was discounting zero-length bg_ts, but once I started requiring bgdata to point to at least one, this is now getting bad values
						for _,bg in ipairs(rs.bgs) do
							local addr = topc(bg.ptr.bank, bg.ptr.addr)
							local decompressed, compressedSize = lz.decompress(rom, addr, 0x10000)
							bg.data = decompressed
							mem:add(addr, compressedSize, 'bg data', m)
						end
						--]]
					end
				end

				for _,rs in ipairs(m.roomStates) do
					if rs.ptr.layerHandling > 0x8000 then
						local addr = topc(self.layerHandlingBank, rs.ptr.layerHandling)
						rs.layerHandling = self:mapAddLayerHandling(addr)
						rs.layerHandling.roomStates:insert(rs)
					end
					
					local addr = topc(rs.ptr.roomBank, rs.ptr.roomAddr)
					rs.room = self:mapAddRoom(addr, m)
					rs.room.mdbs:insertUnique(m)
					rs.room.roomStates:insert(rs)
				end

				local startaddr = topc(self.doorAddrBank, m.ptr.doors)
				data = rom + startaddr 
				--data = rom + 0x70000 + m.ptr.doors
				local doorAddr = read'uint16_t'
				while doorAddr > 0x8000 do
					m.doors:insert{
						addr = doorAddr,
					}
					doorAddr = read'uint16_t'
				end
				-- exclude terminator
				data = data - 2
				local len = data-rom - startaddr
			
	--doorsSoFar = doorsSoFar or table()
				for _,door in ipairs(m.doors) do
					local addr = topc(self.doorBank, door.addr)
	--doorsSoFar[addr] = doorsSoFar[addr] or table()
	--doorsSoFar[addr]:insert(m)
					data = rom + addr 
					local dest_mdb = ffi.cast('uint16_t*', data)[0]
					-- if dest_mdb == 0 then it is just a 2-byte 'lift' structure ...
					local ctype = dest_mdb == 0 and 'lift_t' or 'door_t'
					door.ctype = ctype
					door.ptr = ffi.cast(ctype..'*', data)
					if ctype == 'door_t' 
					and door.ptr.code > 0x8000 
					then
						door.doorCodeAddr = topc(self.doorCodeBank, door.ptr.code)
						door.doorCode = readCode(rom, door.doorCodeAddr, 0x100)
					end
				end
			
				-- ok now we've got all the roomstates, rooms, plms, and door_t's ...
				-- now to link the doors in the rooms to their plm and door_t 
				--[[ turns out it is very slow, esp when building the map from roomstate to exit
				for _,rs in ipairs(m.roomStates) do
					for _,door in ipairs(rs.room.doors) do
						local exit = m.doors[door.index+1]
						if not exit then
							print("failed to find exit index "..door.index.." in "
								..('%02x/%02x'):format(m.ptr.region, m.ptr.index))
						else
							door.exit = door.exit or {}
							door.exit[rs] = exit 
						end

						local plmindex, plm = rs.plmset.plms:find(nil, function(plm)
							return plm.x == door.x and plm.y == door.y
						end)
						-- may or may not be there
						if plm then
							door.plms = door.plms or {}
							door.plms[rs] = plm
						end
					end
				end
				---]]
			end
		end
	end


	-- link all doors to their mdbs
	-- TODO in the future, maybe a door:setMDB function?
	for _,m in ipairs(self.mdbs) do
		for _,door in ipairs(m.doors) do
			if door.ctype == 'door_t' then
				local dest_mdb = assert(
					select(2, self.mdbs:find(nil, function(m) 
						return m.addr == door.ptr.dest_mdb 
					end)), 
					'!!!! door '..('%06x'):format(ffi.cast('uint8_t*',door.ptr)-rom)..' points nowhere')
				-- points to the dest mdb
				door.dest_mdb = dest_mdb
			end
		end
	end
	
	--[[ get a table of doors based on their plm arg low byte
	self.doorPLMForID = table()
	for _,plmset in ipairs(self.plmsets) do
		for _,plm in ipairs(plmset.plms) do
			local name = self.plmCmdNameForValue[plm.cmd]
			if name and name:match'^door_' then
				local id = bit.band(plm.args, 0xff)
				assert(not self.doorPLMForID[id])
				self.doorPLMForID[id] = plm
			end	
		end
	end
	--]]


	-- ok, now to try and change a mdb_t


	--[[ seeing if any two rooms have door addrs that point to the same door ...
	-- looks like the only ones that do are the lift_t zero structure:
	-- $0188fc, used by 00/08 00/0f 00/14 00/19 01/00 01/0e 01/24 00/33 01/34 02/03 02/26 02/36
	-- $01a18a, used by 04/13 05/00
	print()
	for _,addr in ipairs(doorsSoFar:keys():sort()) do
		local ms = doorsSoFar[addr]
		if #ms > 1 then
			io.write('found overlapping doors at '..('$%06x'):format(addr)..', used by')
			for _,m in ipairs(ms) do
				io.write(' '..('%02x/%02x'):format(m.ptr.region, m.ptr.index))
			end
			print()
		end
	end
	--]]
	--[[ now lets look through all doors and see if there's any duplicates that *could have* been overlapping
	-- nope, all doors are unique.  any sort of duplication is handled by the overlapping door addresses above
	local alldoors = table():append(self.mdbs:map(function(m) return m.doors end):unpack())
	print()
	print('#alldoors '..#alldoors)
	for i=1,#alldoors-1 do
		local da = alldoors[i]
		for j=i+1,#alldoors do
			local db = alldoors[j]
			if da.addr ~= db.addr and da.ptr[0] == db.ptr[0] then
				print('doors '..('$%06x'):format(ffi.cast('uint8_t*',da.ptr)-rom)
					..' and '..('$%06x'):format(ffi.cast('uint8_t*',db.ptr)-rom)
					..' are identical (and could be consolidated)')
			end
		end
	end
	--]]



	-- [[ -------------------------------- ASSERT STRUCT ---------------------------------
	-- asserting underlying contiguousness of structure of the mdb_t's...
	-- verify that after each mdb_t, the roomselect / roomstate_t / dooraddrs are packed together

	-- before the first mdb_t is 174 plm_t's, 
	-- then 100 bytes of something
	assert(self.mdbs)
	for j,m in ipairs(self.mdbs) do
		local d = ffi.cast('uint8_t*',m.ptr)
		local mdbaddr = d - rom
		d = d + ffi.sizeof'mdb_t'
		-- if there's only 1 roomState then it is a term, and
		for i=1,#m.roomStates-1 do
			assert(d == ffi.cast('uint8_t*', m.roomStates[i].select))
			d = d + ffi.sizeof(m.roomStates[i].select_ctype)
		end
		-- last roomselect should always be 2 byte term
		d = d + 2
		-- next should always match the last room
		for i=#m.roomStates,1,-1 do
			assert(d == ffi.cast('uint8_t*', m.roomStates[i].ptr))
			d = d + ffi.sizeof'roomstate_t'
		end
		-- for a single room there is an extra 26 bytes of padding between the roomstate_t's and the dooraddrs
		-- and that room is $07ad1b, the speed booster room
		-- the memory map at http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
		-- says it is just part of the speed booster room
		if mdbaddr == 0x07ad1b then
			local data = ffi.new('uint8_t[?]', 26)
			ffi.copy(data, d, 26)
			m.speedBoosterRoomExtraData = data
print('speed booster room extra trailing data at '..('$%06x'):format(d - rom)..': '..byteArrayToHexStr(data))
			d = d + 26
		end
		local dooraddr = topc(self.doorAddrBank, m.ptr.doors)
		assert(d == rom + dooraddr)
		d = d + 2 * #m.doors
		
		-- now expect all scrolldatas of all rooms of this mdb_t
		-- the # of unique scrolldatas is either 0 or 1
		local scrolls = m.roomStates:map(function(rs)
			return true, rs.ptr.scroll
		end):keys():filter(function(scroll)
			return scroll > 1 and scroll ~= 0x8000
		end):sort()
		assert(#scrolls <= 1)
		-- mdb_t $07adad -- room before wave room -- has its scrolldata overlap with the dooraddr
		-- so... shouldn't this assertion fail?
		for _,scroll in ipairs(scrolls) do
			local addr = topc(self.scrollBank, scroll)
			assert(d == rom + addr)
			d = d + m.ptr.width * m.ptr.height
		end

		-- mdb_t $079804 - gold torizo room - has 14 bytes here -- pointed to by roomstate_t.unknown: 0f 0a 52 00 0f 0b 52 00 0f 0c 52 00 00 00
		-- mdb_t $07a66a - statues before tourian - has 8 bytes after it 
		-- mdb_t $07a923 - slope down to crocomire - has 5 bytes here 
		-- mdb_t $07a98d - crocomire's room - has 6 bytes here 
		-- mdb_t $07ad1b - speed booster room - has 26 bytes here
		-- mdb_t $07b1e5 - lava-lowering chozo statue - has 11 bytes here
		d = d + (({
			[0x79804] = 14,
			[0x7a66a] = 8,
			[0x7a923] = 5,
			[0x7a98d] = 6,
			[0x7ad1b] = 26,
			[0x7b1e5] = 11,
		})[mdbaddr] or 0)

	--[=[ continuity of plm scrollmods?
	print('d starts at '..('%06x'):format( d-rom ))
		-- plm scrollmod sometimes go here
		local plmsets = table()
		for _,rs in ipairs(m.roomStates) do
			plmsets:insertUnique(rs.plmset)
		end
		plmsets:sort(function(a,b) return a.addr < b.addr end)
		for _,plmset in ipairs(plmsets) do
			if plmset and #plmset.scrollmods > 0 then
				for _,scrollmod in ipairs(plmset.scrollmods) do
	--				assert(d == ffi.cast('uint8_t*', rom+scrollmod.addr))
					d = d + scrollmod.len
				end
			end
		end
	--]=]

		-- mdb_t $07c98e - wrecked ship chozo & reserve - has 12 bytes here
		-- mdb_t $07ca42 - hallway at top of wrecked ship - has 8 bytes here
		-- mdb_t $07cc6f - hallway before phantoon - has 3 bytes here

		-- see if the next mdb_t is immediately after
		--[=[
		if j+1 <= #self.mdbs then
			local m2 = ffi.cast('uint8_t*', self.mdbs[j+1].ptr)
			if d ~= m2 then
				print('non-contiguous mdb_t before '..('$%06x'):format(m2-rom))	
			end
		end
		--]=]
	end


	--]] --------------------------------------------------------------------------------
end






local blockSizeInPixels = 4
local blocksPerRoom = 16
local roomSizeInPixels = blocksPerRoom * blockSizeInPixels

local colormap = range(254)
--colormap = shuffle(colormap)
colormap[0] = 0
colormap[255] = 255
-- data is sized 32*m.width x 16*m.width
local ofsPerRegion = {
	function(m) 
		-- special case for crateria
		if m.region == 0	-- crateria
		and m.x > 45 
		then
			return 10,0
		end
		return 3,0
	end,	-- crateria
	function(m) return 0,18 end,	-- brinstar
	function(m) return 31,38 end,	-- norfair
	function(m) return 37,-10 end,	-- wrecked ship
	function(m) return 28,18 end,	-- maridia
	function(m) return 0,0 end,	-- tourian
	function(m) return -5,25 end,	-- ceres
	function(m) return 7,47 end,	-- testing
}


-- it'd be really nice to draw the mdb region/index next to the room ...
-- now it'd be nice if i didn't draw over the numbers ... either by the room tile data, or by other numbers ...
local digits = {
	['$'] = {
		' **',
		'** ',
		' * ',
		' **',
		'** ',
	},
	['-'] = {
		'   ',
		'   ',
		'***',
		'   ',
		'   ',
	},
	['0'] = {
		' * ',
		'* *',
		'* *',
		'* *',
		' * ',
	},
	['1'] = {
		' * ',
		' * ',
		' * ',
		' * ',
		' * ',
	},
	['2'] = {
		'** ',
		'  *',
		' * ',
		'*  ',
		'***',
	},
	['3'] = {
		'** ',
		'  *',
		'** ',
		'  *',
		'** ',
	},
	['4'] = {
		'* *',
		'* *',
		'***',
		'  *',
		'  *',
	},
	['5'] = {
		'***',
		'*  ',
		'** ',
		'  *',
		'** ',
	},
	['6'] = {
		' **',
		'*  ',
		'***',
		'* *',
		'***',
	},
	['7'] = {
		'***',
		'  *',
		'  *',
		'  *',
		'  *',
	},
	['8'] = {
		'***',
		'* *',
		'***',
		'* *',
		'***',
	},
	['9'] = {
		'***',
		'* *',
		'***',
		'  *',
		'** ',
	},
	['a'] = {
		' * ',
		'* *',
		'***',
		'* *',
		'* *',
	},
	['b'] = {
		'** ',
		'* *',
		'** ',
		'* *',
		'** ',
	},
	['c'] = {
		' **',
		'*  ',
		'*  ',
		'*  ',
		' **',
	},
	['d'] = {
		'** ',
		'* *',
		'* *',
		'* *',
		'** ',
	},
	['e'] = {
		'***',
		'*  ',
		'***',
		'*  ',
		'***',
	},
	['f'] = {
		'***',
		'*  ',
		'***',
		'*  ',
		'*  ',
	},
}

local function drawstr(mapimg, posx, posy, s)
	for i=1,#s do
		local ch = digits[s:sub(i,i)]
		if ch then
			for pj=0,4 do
				for pi=0,2 do
					local c = ch[pj+1]:byte(pi+1) == (' '):byte() and 0 or 255
					if c ~= 0 then	
						local x = posx + pi + (i-1)*4
						local y = posy + pj
					
						if x >= 0 and x < mapimg.width
						and y >= 0 and y < mapimg.height 
						then
							mapimg.buffer[0+3*(x+mapimg.width*y)] = c
							mapimg.buffer[1+3*(x+mapimg.width*y)] = c
							mapimg.buffer[2+3*(x+mapimg.width*y)] = c
						end	
					end	
				end
			end
		end
	end
end

-- to prevent overlap
-- honestly, excluding the empty background tiles below fixes most of this
-- but for the solid tile output, I still want to see those types, so that's why I added this code 
-- what regions on the map to exclude
local mapDrawExcludeMapBlocks = {
	{1, 0x08, 0, 1, 4, 5},	-- brinstar pink speed fall room
	{1, 0x09, 0, 0, 1, 1},	-- brinstar pink big room
	{1, 0x09, 0, 1, 2, 2},	-- "
	{1, 0x0e, 0, 0, 5, 2},	-- brinstar blue first room
	{1, 0x13, 2, 0, 3, 1},	-- brinstar bottom flea room
	{1, 0x2c, 0, 1, 1, 1},	-- brinstar kraid fly room
	{2, 0x04, 0, 0, 3, 3},	-- norfair speed room to ice
	{2, 0x04, 4, 3, 3, 1},	-- "
	{2, 0x07, 1, 0, 1, 1},	-- norfair room before ice
	{2, 0x07, 1, 2, 1, 1},	-- "
	{2, 0x14, 5, 0, 3, 2},	-- norfair room before grappling
	{2, 0x21, 0, 0, 2, 2},	-- norfair lava rise room run to wave
	{2, 0x36, 5, 0, 3, 2},	-- norfair lower first room
	{2, 0x3e, 0, 0, 2, 3},	-- norfair lower return from gold chozo loop
	{2, 0x48, 0, 0, 1, 2},	-- norfair lower escape last room
	{2, 0x4b, 0, 1, 1, 5},	-- norfair lower escape first room
	{3, 0x00, 0, 0, 2, 1},	-- wrecked ship bowling chozo room
	{3, 0x00, 0, 2, 1, 1},	-- "
	{3, 0x04, 0, 0, 4, 5},	-- wrecked ship main shaft
	{3, 0x04, 5, 0, 1, 6},	-- "
	{4, 0x03, 1, 1, 3, 1},	-- maridia fly and yellow blob room at the bottom
	{4, 0x31, 1, 0, 4, 2},	-- maridia mocktroid and big shell guy area
}


local function drawRoom(ctx, room, m)
	local mapimg = ctx.mapimg
	local mapBinImage = ctx.mapBinImage
	local blocks = room.blocks
	local w = room.width / blocksPerRoom
	local h = room.height / blocksPerRoom
	local ofsx, ofsy = ofsPerRegion[m.ptr.region+1](m.ptr)
	local xofs = roomSizeInPixels * (ofsx - 4)
	local yofs = roomSizeInPixels * (ofsy + 1)
	local firstcoord

	for j=0,h-1 do
		for i=0,w-1 do
			local ignore
			for _,info in ipairs(mapDrawExcludeMapBlocks) do
				local region, index, mx, my, mw, mh = table.unpack(info)
				if region == m.ptr.region
				and index == m.ptr.index
				and i >= mx and i < mx + mw 
				and j >= my and j < my + mh
				then
					ignore = true
					break
				end
			end
			if not ignore then
				for ti=0,blocksPerRoom-1 do
					for tj=0,blocksPerRoom-1 do
						local dx = ti + blocksPerRoom * i
						local dy = tj + blocksPerRoom * j
						local di = dx + blocksPerRoom * w * dy
						-- blocks is 1-based
						local d1 = blocks[0 + 3 * di] or 0
						local d2 = blocks[1 + 3 * di] or 0
						local d3 = blocks[2 + 3 * di] or 0
				
						-- empty background tiles:
						-- ff0000
						-- ff0083
						-- ff00ff
						-- ff8300
						-- ff8383
						-- ff83ff
						if d1 == 0xff
						--and d2 == 0x00
						and (d2 == 0x00 or d2 == 0x83)
						and (d3 == 0x00 or d3 == 0x83 or d3 == 0xff)
						then
						else
							for pi=0,blockSizeInPixels-1 do
								for pj=0,blockSizeInPixels-1 do
									local y = yofs + pj + blockSizeInPixels * (tj + blocksPerRoom * (m.ptr.y + j))
									local x = xofs + pi + blockSizeInPixels * (ti + blocksPerRoom * (m.ptr.x + i))
					--for y=(m.ptr.y + j)* roomSizeInPixels + yofs, (m.ptr.y + h) * roomSizeInPixels - 1 + yofs do
					--	for x=m.ptr.x * roomSizeInPixels + xofs, (m.ptr.x + w) * roomSizeInPixels - 1 + xofs do
									if x >= 0 and x < mapimg.width
									and y >= 0 and y < mapimg.height 
									then
										if not firstcoord then
											firstcoord = {x,y}
										end
										
										mapimg.buffer[0+3*(x+mapimg.width*y)] = colormap[tonumber(d1)]
										mapimg.buffer[1+3*(x+mapimg.width*y)] = colormap[tonumber(d2)]
										mapimg.buffer[2+3*(x+mapimg.width*y)] = colormap[tonumber(d3)]
									end
								end
							end
						end

						
						
						-- write out solid tiles only

						-- TODO isSolid will overlap between a few rooms
						local isBorder = room:isBorderAndNotCopy(dx,dy)
						do --if isBorder or isSolid then
							local isSolid = room:isSolid(dx,dy)
							for pi=0,blockSizeInPixels-1 do
								for pj=0,blockSizeInPixels-1 do
									local y = yofs + pj + blockSizeInPixels * (tj + blocksPerRoom * (m.ptr.y + j))
									local x = xofs + pi + blockSizeInPixels * (ti + blocksPerRoom * (m.ptr.x + i))
									if x >= 0 and x < mapimg.width
									and y >= 0 and y < mapimg.height 
									then
										mapBinImage.buffer[0+3*(x+mapBinImage.width*y)] = isBorder and 0xff or 0x00
										mapBinImage.buffer[1+3*(x+mapBinImage.width*y)] = isSolid and 0xff or 0x00
										mapBinImage.buffer[2+3*(x+mapBinImage.width*y)] = 0xff
									end
								end
							end
						end
					end
				end
			end
		end
	end

	drawstr(mapimg, firstcoord[1], firstcoord[2], ('%x-%02x'):format(m.ptr.region, m.ptr.index))
	drawstr(mapimg, firstcoord[1], firstcoord[2]+6, ('$%04x'):format(m.addr))
end

local function drawline(mapimg, x1,y1,x2,y2, r,g,b)
	r = r or 0xff
	g = g or 0xff
	b = b or 0xff
	local dx = x2 - x1
	local dy = y2 - y1
	local adx = math.abs(dx)
	local ady = math.abs(dy)
	local d = math.max(adx, ady) + 1
	for k=1,d do
		local s = (k-.5)/d
		local t = 1 - s
		local x = math.round(s * x1 + t * x2)
		local y = math.round(s * y1 + t * y2)
		if x >= 0 and x < mapimg.width
		and y >= 0 and y < mapimg.height 
		then
			mapimg.buffer[0+3*(x+mapimg.width*y)] = r
			mapimg.buffer[1+3*(x+mapimg.width*y)] = g
			mapimg.buffer[2+3*(x+mapimg.width*y)] = b
		end
	end
end

local function drawRoomDoors(ctx, room)
	local mapimg = ctx.mapimg
	local blocks = room.blocks
	-- for all blocks in the room, if any are xx9xyy, then associate them with exit yy in the door_t list (TODO change to exit_t)	
	-- then, cycle through exits, and draw lines from each block to the exit destination

	for _,srcm in ipairs(room.mdbs) do
		local srcm_ofsx, srcm_ofsy = ofsPerRegion[srcm.ptr.region+1](srcm.ptr)
		local srcm_xofs = roomSizeInPixels * (srcm_ofsx - 4)
		local srcm_yofs = roomSizeInPixels * (srcm_ofsy + 1)
		for exitIndex,blockpos in pairs(room.blocksForExit) do
--print('in mdb '..('%02x/%02x'):format(srcm.ptr.region, srcm.ptr.index)..' looking for exit '..exitIndex..' with '..#blockpos..' blocks')
			-- TODO lifts will mess up the order of this, maybe?
			local door = srcm.doors[exitIndex+1]
			if not door then
--print('found no door')
			elseif door.ctype ~= 'door_t' then
--print("door isn't a ctype")
			-- TODO handle lifts?
			else
				local dstm = assert(door.dest_mdb)
				local dstm_ofsx, dstm_ofsy = ofsPerRegion[dstm.ptr.region+1](dstm.ptr)
				local dstm_xofs = roomSizeInPixels * (dstm_ofsx - 4)
				local dstm_yofs = roomSizeInPixels * (dstm_ofsy + 1)
			
				-- draw an arrow or something on the map where the door drops us off at
				-- door.dest_mdb is the mdb
				-- draw it at door.ptr.screenX by door.ptr.screenY
				-- and offset it according to direciton&3 and distToSpawnSamus (maybe)

				local i = door.ptr.screenX
				local j = door.ptr.screenY
				local dir = bit.band(door.ptr.direction, 3)	-- 0-based
				local ti, tj = 0, 0	--table.unpack(doorPosForDir[dir])
					
				local k=blockSizeInPixels*3-1 
					
				local pi, pj
				if dir == 0 then		-- enter from left
					pi = k
					pj = bit.rshift(roomSizeInPixels, 1)
				elseif dir == 1 then	-- enter from right
					pi = roomSizeInPixels - k
					pj = bit.rshift(roomSizeInPixels, 1)
				elseif dir == 2 then	-- enter from top
					pi = bit.rshift(roomSizeInPixels, 1)
					pj = k
				elseif dir == 3 then	-- enter from bottom
					pi = bit.rshift(roomSizeInPixels, 1)
					pj = roomSizeInPixels - k
				end
			
				-- here's the pixel x & y of the door destination
				local x1 = dstm_xofs + pi + blockSizeInPixels * (ti + blocksPerRoom * (dstm.ptr.x + i))
				local y1 = dstm_yofs + pj + blockSizeInPixels * (tj + blocksPerRoom * (dstm.ptr.y + j))

				for _,pos in ipairs(blockpos) do
					-- now for src block pos
					local x2 = srcm_xofs + blockSizeInPixels/2 + blockSizeInPixels * (pos[1] + blocksPerRoom * srcm.ptr.x)
					local y2 = srcm_yofs + blockSizeInPixels/2 + blockSizeInPixels * (pos[2] + blocksPerRoom * srcm.ptr.y)
					drawline(mapimg,x1,y1,x2,y2)
				end
			end
		end
	end
end

function drawRoomPLMs(ctx, room)
	local mapimg = ctx.mapimg
	for _,rs in ipairs(room.roomStates) do
		local m = rs.m
		local ofsx, ofsy = ofsPerRegion[m.ptr.region+1](m.ptr)
		local xofs = roomSizeInPixels * (ofsx - 4)
		local yofs = roomSizeInPixels * (ofsy + 1)
		if rs.plmset then
			for _,plm in ipairs(rs.plmset.plms) do
				local x = xofs + blockSizeInPixels/2 + blockSizeInPixels * (plm.x + blocksPerRoom * m.ptr.x)
				local y = yofs + blockSizeInPixels/2 + blockSizeInPixels * (plm.y + blocksPerRoom * m.ptr.y)
				drawline(mapimg,x+2,y,x-2,y, 0x00, 0xff, 0xff)
				drawline(mapimg,x,y+2,x,y-2, 0x00, 0xff, 0xff)
				drawstr(mapimg, x+5, y, ('$%x'):format(plm.cmd))
			end
		end
		if rs.enemySpawnSet then
			for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do
				local x = math.round(xofs + blockSizeInPixels/2 + blockSizeInPixels * (enemySpawn.x / 16 + blocksPerRoom * m.ptr.x))
				local y = math.round(yofs + blockSizeInPixels/2 + blockSizeInPixels * (enemySpawn.y / 16 + blocksPerRoom * m.ptr.y))
				drawline(mapimg,x+2,y,x-2,y, 0xff, 0x00, 0xff)
				drawline(mapimg,x,y+2,x,y-2, 0xff, 0x00, 0xff)
				drawstr(mapimg, x+5, y, ('$%x'):format(enemySpawn.enemyAddr))
			end
		end
	end
end


function SMMap:mapSaveImage(filenamePrefix)
	local Image = require 'image'
	
	filenamePrefix = filenamePrefix or 'map'

	local w = roomSizeInPixels*68
	local h = roomSizeInPixels*58
	local mapimg = Image(w, h, 3, 'unsigned char')
	local mapBinImage = Image(w, h, 3, 'unsigned char')
	local ctx = {
		mapimg = mapimg,
		mapBinImage = mapBinImage,
	}

	for _,room in ipairs(self.rooms) do
		for _,m in ipairs(room.mdbs) do
			drawRoom(ctx, room, m)
		end
	end

	for _,room in ipairs(self.rooms) do
		drawRoomDoors(ctx, room)
		drawRoomPLMs(ctx, room)
	end

	mapimg:save(filenamePrefix..'.png')
	mapBinImage:save(filenamePrefix..'-mask.png')
end


function SMMap:mapPrintRooms()
	-- print/draw rooms
	print()
	print'all rooms'
	for _,room in ipairs(self.rooms) do
		local w,h = room.width, room.height
		for _,m in ipairs(room.mdbs) do
			io.write(' '..('%02x/%02x'):format(m.ptr.region, m.ptr.index))
		end
		print()

		local function printblock(data, width)
			for i=1,ffi.sizeof(data) do
				io.write((('%02x'):format(tonumber(data[i-1])):gsub('0','.')))
				if i % width == 0 then print() end 
			end
			print()
		end

		printblock(room.head, 2) 
		printblock(room.blocks, 3*w) 
		print('found '..#room.doors..' door references in the blocks')
		for _,door in ipairs(room.doors) do
			print(' '..tolua(door))
		end
		print('blocksForExit'..tolua(room.blocksForExit))	-- exit information
		print' roomstate scrolldata:'
		for _,rs in ipairs(room.roomStates) do
			if rs.scrollData then
				print(('  $%06x'):format(ffi.cast('uint8_t*',rs.ptr)-sm.rom))
				printblock(tableToByteArray(rs.scrollData), w/16)
			end
		end
	end
end

function SMMap:mapWriteGraphDot()
	local rom = self.rom

	local f = assert(io.open('roomgraph-random.dot', 'w'))
	f:write'digraph G {\n'
	local showRoomStates = false
	local showDoors = false
	if showRoomStates then
		f:write'\tcompound=true;\n'
		f:write'\trankdir=TB;\n'
		f:write'\tnode [pin=true];\n'
		f:write'\toverlap=false;\n'
	end
	local nl = '\\n'	-- these work in labels, but clusters?
	--local nl = '-'
	local levelsep = '/'	-- doesn't work with cluster labels
	--local levelsep = ''
	local function getMDBName(m)
		return 
			--('$%06x'):format(ffi.cast('uint8_t*', m.ptr) - rom)
--			('%04x'):format(bit.band(0xffff, ffi.cast('uint8_t*', m.ptr) - rom))..nl..
			('%02x'..levelsep..'%02x'):format(m.ptr.region, m.ptr.index)
	end
	local function getClusterName(mdbName)
		-- graphviz clusters have to have 'cluster' as a prefix
		return 'cluster_'..mdbName
	end
	local function getRoomStateName(rs)
		return ('%04x'):format(bit.band(0xffff,ffi.cast('uint8_t*',rs.ptr)-rom))
	end
--print'building graph'			
	local edges = table()
	--for _,m in ipairs(self.mdbs) do
	for _,room in ipairs(self.rooms) do
		for _,m in ipairs(room.mdbs) do
			local mdbName = getMDBName(m)
			
			if showRoomStates then
				local itemIndex = 0
				f:write('\tsubgraph "',getClusterName(mdbName),'" {\n')
				f:write('\t\trank="same";\n')
				--f:write('\t\tlabel="', mdbName, '";\n')
				f:write('\t\t"', mdbName, '" [pos="0,0" shape=box];\n')
				for i,rs in ipairs(m.roomStates) do
					local rsName = getRoomStateName(rs)
					local rsNodeName = mdbName..nl..rsName
					f:write('\t\t"', rsNodeName, '"')
					f:write(' [pos="0,',tostring(-i),'" shape=box label="',rsName,'"]')
					f:write(';\n')
					
					-- TODO make roomState a subcluster of the room ...
					if rs.plmset then
						for plmIndex,plm in ipairs(rs.plmset.plms) do
							local plmname = sm.plmCmdNameForValue[plm.cmd]
							if plmname and plmname:match'^item_' then
								local itemNodeName = mdbName..nl..rsName..nl..plmIndex
								f:write('\t\t"', itemNodeName, '" [pos="1,',tostring(-itemIndex),'" shape=box label="', plmname, '"];\n')
								itemIndex = itemIndex + 1
							
								edges:insert('"'..itemNodeName..'" -> "'..rsNodeName..'"')
							end
						end
					end
				end
			end
			
			-- for each mdb door, find the room door with a matching index
			-- TODO maybe I should go by room doors.  room doors are based on map tiles, and they reference the mdb door with their index.
			-- however lifts are not specified by room doors, but they are always the last mdb door.
			-- and open exits are not room doors either ... this is where room.blocksForExit comes in handy 
			for exitIndex, blockpos in pairs(room.blocksForExit) do
				local mdbDoor = m.doors[exitIndex+1]
				
				if mdbDoor 
				and mdbDoor.ctype == 'door_t' 	-- otherwise, lift_t is a suffix of a lift door_t
				then

					assert(mdbDoor.dest_mdb)
					local destMdbName = getMDBName(mdbDoor.dest_mdb)
				
					-- if there is no matching roomDoor then it could just be a walk-out-of-the-room exit
					local color
					
					-- notice, if we reverse the search, and cycle through all room.doors and then lookup the associated mdb.door, we come up with only one room door that doesn't have a mdb door ...
					-- !!! WARNING !!! 02/3d roomDoorIndex=1 has no associated MDB door
					local _, roomDoor = room.doors:find(nil, function(roomDoor)
						-- TODO is this always true?  the blockpos exitIndex matches the roomDoor.index?
						return roomDoor.index == exitIndex
					end)
					if roomDoor then
						-- if there is a room door then the exit is a blue door by default ... unless we find a plm for the door
						color = 'blue'

						-- we're getting multiple edges here
						-- room pertains to block data, and it will be repeated for reused block data rooms (like save points, etc)
						-- now this means room.roomStates will have as many roomStates as there are multiple mdbs which reference it
						-- so we only want to look through the roomStates that pertain to our current mdb
						--for _,rs in ipairs(room.roomStates) do
						for _,rs in ipairs(m.roomStates) do	
							local rsName = getRoomStateName(rs)
--print('  roomstate_t: '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' '..rs.ptr[0]) 
						
							local color
							local doorarg = 0
							
							if rs.plmset then
								for _,plm in ipairs(rs.plmset.plms) do
--local plmname = sm.plmCmdNameForValue[plm.cmd]
--print('   plm_t: '..plmname..' '..plm)
									-- find a matching door plm
									if plm.x == roomDoor.x and plm.y == roomDoor.y then
										local plmname = assert(sm.plmCmdNameForValue[plm.cmd], "expected door plm to have a valid name "..plm)
										color = plmname:match'^door_([^_]*)'
										doorarg = plm.args
									end
								end
							end
							color = color or 'blue'
							if color == 'eye' then color = 'darkseagreen4' end
							
							if showDoors then
								local srcNodeName = mdbName
								local dstNodeName = destMdbName
								local doorName = 'door'..('%04x'):format(mdbDoor.addr)
								local doorNodeName = mdbName..':'..doorName
								local colorTag = '[color='..color..']'
								local labelTag = color == 'blue' and '[label=""]' or ('[label="'..('%04x'):format(doorarg)..'"]') 
								f:write('\t"', doorNodeName, '"', colorTag, labelTag, ';\n')
								-- TODO connect the src door with the dest door
								-- look at the mdbDoor destination information
								-- compare it to the room doors xy in the destination room 
								-- just like in the drawRoomDoors code
								-- if you have a match then pair the doors together
								-- then TODO store this elsewhere
								-- and TODO TODO then with a bidirectional graph, next add some extra nodes to that graph based on obstructions, and last use this graph for placement and traversal of items
								edges:insert('"'..srcNodeName..'" -> "'..doorNodeName..'"'..colorTag)
								edges:insert('"'..doorNodeName..'" -> "'..dstNodeName..'"'..colorTag)
							else
								-- create door edges from each roomstate to each mdb
								local srcNodeName = mdbName
								local dstNodeName = destMdbName
								if showRoomStates then
									srcNodeName = srcNodeName .. nl .. rsName
									--local dstRSName = getRoomStateName(assert(mdbDoor.dest_mdb.roomStates[1]))	-- TODO how to determine destination room state?
									--dstNodeName = dstNodeName .. nl .. dstRSName
								end
								local edgecode = '"'..srcNodeName..'" -> "'..dstNodeName..'" ['
								if showRoomStates then
									--edgecode = edgecode..'lhead="'..getClusterName(destMdbName)..'" '
								end
								edgecode = edgecode .. 'color=' .. color 
								if color ~= 'blue' then
									edgecode = edgecode .. ' label="' .. ('%04x'):format(doorarg)..'"'
								end
								edgecode = edgecode .. ']'
								edges:insert(edgecode)
							end
						end
					else	-- no roomDoor, so it's just a walk-out-the-wall door or a lift
						if showDoors then
							local srcNodeName = mdbName
							local dstNodeName = destMdbName
							local doorName = 'door'..('%04x'):format(mdbDoor.addr)
							local doorNodeName = mdbName..':'..doorName
							local colorTag = ''
							local labelTag = '[label=""]'
							f:write('\t"', doorNodeName, '"', colorTag, labelTag, ';\n')
							edges:insert('"'..srcNodeName..'" -> "'..doorNodeName..'"'..colorTag)
							edges:insert('"'..doorNodeName..'" -> "'..dstNodeName..'"'..colorTag)
						else
							--if m.doors:last().ctype == 'lift_t' then
							--local mdbDoor = m.doors[#m.doors-1]
							local destMdbName = getMDBName(mdbDoor.dest_mdb)
							-- create door edges from each roomstate to each mdb
							local srcNodeName = mdbName
							local dstNodeName = destMdbName
							if showRoomStates then
								--local srcRSName = getRoomStateName(assert(m.roomStates[1]))
								--srcNodeName = srcNodeName .. nl .. srcRSName
								--local dstRSName = getRoomStateName(assert(mdbDoor.dest_mdb.roomStates[1]))
								--dstNodeName = dstNodeName .. nl .. dstRSName
							end
							local edgecode = '"'..srcNodeName..'" -> "'..dstNodeName..'" ['
							if showRoomStates then
								--edgecode = edgecode
								--	..'lhead="'..getClusterName(destMdbName)..'" '
								--	..'ltail="'..getClusterName(mdbName)..'" '
							end
							edgecode = edgecode .. ']'
							edges:insert(edgecode)
						end
					end
				end
			end
			
			if showRoomStates then
				f:write('\t}\n')
			end
		end	
	end
	for _,edge in ipairs(edges) do
		f:write('\t', edge, ';\n')
	end
	f:write'}\n'
	f:close()
	-- I would use sfdp, but it groups all the nodes into one tiny location.  If I could just multiply their positions by 100 then it would look fine I'm sure.
	-- fds looks good, but it goes slow
	-- dot looks horrible for clusters.  
	--  fds looks better, but doesn't respet the lhead/ltail attributes.
	--  this could be fixed if I could find out where doors' target roomStates are stored.
	-- ok now dot is crashing when showRoomStates is enabled
	exec'dot -Tsvg -o roomgraph-random.svg roomgraph-random.dot'
end

function SMMap:mapPrint()
	local rom = self.rom
	print()
	print("all plm_t's:")
	for _,plmset in ipairs(self.plmsets) do
		print(' '
			..(plmset.addr and ('$%06x'):format(plmset.addr) or 'nil')
			..' mdbs: '..plmset.roomStates:map(function(rs)
				local m = rs.m
				return ('%02x/%02x'):format(m.ptr.region, m.ptr.index)
			end):concat' '
		)
		for _,plm in ipairs(plmset.plms) do
			io.write('  '..plm)
			local plmName = self.plmCmdNameForValue[plm.cmd]
			if plmName then io.write(' ',plmName) end
			print()
		end
	end

	-- [[ debugging - show all rooms that each plm cmd is used in
	local allPLMCmds = table()
	for _,plmset in ipairs(self.plmsets) do
		local rsstrs = table()
		for _,rs in ipairs(plmset.roomStates) do
			local region = assert(tonumber(rs.m.ptr.region))
			local index = assert(tonumber(rs.m.ptr.index))
			rsstrs:insert(('%02x/%02x'):format(region, index))
		end
		rsstrs = rsstrs:concat', '
		for _,plm in ipairs(plmset.plms) do
			local plmcmd = assert(tonumber(plm.cmd))
			allPLMCmds[plmcmd] = true
		end
	end
	
	print'room per plm_t cmd:'
	for _,plmcmd in ipairs(table.keys(allPLMCmds):sort()) do
		io.write(('%x: '):format(plmcmd))
		local sep = ''
		
		for _,plmset in ipairs(self.plmsets) do
			local rsstrs = table()
			for _,rs in ipairs(plmset.roomStates) do
				local region = assert(tonumber(rs.m.ptr.region))
				local index = assert(tonumber(rs.m.ptr.index))
				rsstrs:insert(('%02x/%02x'):format(region, index))
			end
			rsstrs = rsstrs:concat', '
			for _,plm in ipairs(plmset.plms) do
				local oplmcmd = assert(tonumber(plm.cmd))
				if oplmcmd == plmcmd then
					io.write(sep, rsstrs)
					sep = ', '
				end
			end
		end	
		
		print()
	end
	--]]

	print()
	print"all enemySpawn_t's:"
	self.enemySpawnSets:sort(function(a,b) return a.addr < b.addr end)
	for _,enemySpawnSet in ipairs(self.enemySpawnSets) do
		print(' '..('$%06x'):format(enemySpawnSet.addr)..' '..tolua{
			enemiesToKill = enemySpawnSet.enemiesToKill, 
		}
			..' mdbs: '..enemySpawnSet.roomStates:map(function(rs)
				return ('%02x/%02x'):format(rs.m.ptr.region, rs.m.ptr.index)
			end):concat' '
		)
		for _,enemySpawn in ipairs(enemySpawnSet.enemySpawns) do	
			io.write('  '..enemySpawn)
			local enemyName = (self.enemyForAddr[enemySpawn.enemyAddr] or {}).name
			if enemyName then
				io.write(' '..enemyName)
			end
			print()
		end
	end

	print()
	print"all enemyGFX_t's:"
	self.enemyGFXSets:sort(function(a,b) return a.addr < b.addr end)
	for _,enemyGFXSet in ipairs(self.enemyGFXSets) do
		print(' '..('$%06x'):format(enemyGFXSet.addr)..': '..enemyGFXSet.name
			..' mdbs: '..enemyGFXSet.roomStates:map(function(rs)
				return ('%02x/%02x'):format(rs.m.ptr.region, rs.m.ptr.index)
			end):concat' '
		)
		for _,enemyGFX in ipairs(enemyGFXSet.enemyGFXs) do
			io.write('  '..enemyGFX)
			local enemyName = (self.enemyForAddr[enemyGFX.enemyAddr] or {}).name
			if enemyName then
				io.write(' '..enemyName)
			end
			print()
		end
	end

	-- print fx1 info
	print()
	print("all fx1_t's:")
	self.fx1s:sort(function(a,b) return a.addr < b.addr end)
	for _,fx1 in ipairs(self.fx1s) do
		print(' '..('$%06x'):format(fx1.addr)..': '..fx1.ptr[0]
			..' mdbs: '..fx1.mdbs:map(function(m)
				return ('%02x/%02x'):format(m.ptr.region, m.ptr.index)
			end):concat' '
		)
	end

	-- print bg info
	print()
	print("all bg_t's:")
	self.bgs:sort(function(a,b) return a.addr < b.addr end)
	for _,bg in ipairs(self.bgs) do
		print(' '..('$%06x'):format(bg.addr)..': '..bg.ptr[0]
			..' mdbs: '..bg.mdbs:map(function(m)
				return ('%02x/%02x'):format(m.ptr.region, m.ptr.index)
			end):concat' '
		)
	end

	-- print mdb info
	print()
	print("all mdb_t's:")
	for _,m in ipairs(self.mdbs) do
		print(' mdb_t '..('$%06x'):format(ffi.cast('uint8_t*', m.ptr) - rom)..' '..m.ptr[0])
		for _,rs in ipairs(m.roomStates) do
			print('  roomstate_t: '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' '..rs.ptr[0]) 
			
			local selectStr = rs.select_ctype == 'uint16_t' 
				and ('%04x'):format(rs.select[0])
				or tostring(rs.select[0])
			print('  '..rs.select_ctype..': '..('$%06x'):format(ffi.cast('uint8_t*', rs.select) - rom)..' '..selectStr)
			-- [[
			if rs.plmset then
				for _,plm in ipairs(rs.plmset.plms) do
					io.write('   plm_t: ')
					local plmName = self.plmCmdNameForValue[plm.cmd]
					if plmName then io.write(plmName..': ') end
					print(plm)
				end
				for _,scrollmod in ipairs(rs.plmset.scrollmods) do
					print('   plm scrollmod: '..('$%06x'):format(scrollmod.addr)..': '..scrollmod.data:map(function(x) return ('%02x'):format(x) end):concat' ')
				end
			end
			--]]
			for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do	
				print('   enemySpawn_t: '
					..((self.enemyForAddr[enemySpawn.enemyAddr] or {}).name or '')
					..': '..enemySpawn)
			end
			print('   enemyGFXSet: '..rs.enemyGFXSet.name)	--:match'\0*(.*)')
			for _,enemyGFX in ipairs(rs.enemyGFXSet.enemyGFXs) do
				print('    enemyGFX_t: '
					..((self.enemyForAddr[enemyGFX.enemyAddr] or {}).name or '')
					..': '..enemyGFX)
			end
			for _,fx1 in ipairs(rs.fx1s) do
				print('   fx1_t: '..('$%06x'):format( ffi.cast('uint8_t*',fx1.ptr)-rom )..': '..fx1.ptr[0])
			end
			for _,bg in ipairs(rs.bgs) do
				print('   bg_t: '..('$%06x'):format( ffi.cast('uint8_t*',bg.ptr)-rom )..': '..bg.ptr[0])
			end
		end
		for _,door in ipairs(m.doors) do
			print('  '..door.ctype..': '
				..('$83:%04x'):format(door.addr)
				..' '..door.ptr[0])
			if door.doorCode then
				print('   code: '..door.doorCode:mapi(function(c) return ('%02x'):format(c) end):concat())
			end
		end
	end

	--[[ print plmset information
	-- half this is in the all plms_ts and the other half is in all mdb_ts
	print()
	print'all plmsets:'
	for i,plmset in ipairs(self.plmsets) do
		print(' plmset '..('$%06x'):format(plmset.addr))
		for _,rs in ipairs(plmset.roomStates) do
			print('  roomstate_t: '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' '..rs.ptr[0]) 
		end
		for _,plm in ipairs(plmset.plms) do
			io.write('  plm_t: ')
			local plmName = self.plmCmdNameForValue[plm.cmd]
			if plmName then io.write(plmName..': ') end
			print(plm)
		end
		for _,scrollmod in ipairs(plmset.scrollmods) do
			print('  plm scrollmod: '..('$%06x'):format(scrollmod.addr)..': '..scrollmod.data:map(function(x) return ('%02x'):format(x) end):concat' ')
		end
	end
	--]]

	-- [[ debugging: print out a graphviz dot file of the rooms and doors
	self:mapWriteGraphDot()
	--]]

	self:mapPrintRooms()

	--[[ debugging: print all unique door codes
	local doorcodes = table()
	for _,m in ipairs(self.mdbs) do
		for _,door in ipairs(m.doors) do
			if door.ctype == 'door_t' then
				doorcodes[door.ptr.code] = true
			end
		end
	end
	print('unique door codes:')
	for _,doorcode in ipairs(doorcodes:keys():sort()) do
		print(('$%04x'):format(doorcode))
	end
	--]]
end

function SMMap:mapBuildMemoryMap(mem)
	local rom = self.rom
	for _,m in ipairs(self.mdbs) do
		local addr = topc(self.mdbBank, m.addr)	
		mem:add(addr, ffi.sizeof'mdb_t', 'mdb_t', m)
		for _,rs in ipairs(m.roomStates) do
			assert(rs.select)
			mem:add(ffi.cast('uint8_t*', rs.select) - rom, ffi.sizeof(rs.select_ctype), 'roomselect', m)
			mem:add(ffi.cast('uint8_t*', rs.ptr) - rom, ffi.sizeof'roomstate_t', 'roomstate_t', m)
			if rs.scrollData then
				-- sized mdb width x height
				local addr = topc(self.scrollBank, rs.ptr.scroll)
				mem:add(addr, #rs.scrollData, 'scrolldata', m)
			end
			
			mem:add(topc(self.fx1Bank, rs.ptr.fx1), #rs.fx1s * ffi.sizeof'fx1_t' + (rs.fx1term and 2 or 0), 'fx1_t', m)
			mem:add(topc(self.bgBank, rs.ptr.bgdata), #rs.bgs * ffi.sizeof'bg_t' + 8, 'bg_t', m)
		end
		
		mem:add(topc(self.doorAddrBank, m.ptr.doors), #m.doors * 2, 'dooraddrs', m)
		for _,door in ipairs(m.doors) do
			mem:add(ffi.cast('uint8_t*',door.ptr)-rom, ffi.sizeof(door.ctype), door.ctype, m)
			if door.doorCode then
				mem:add(door.doorCodeAddr, #door.doorCode, 'door code', m)
			end
		end
	end

	for _,layerHandling in ipairs(self.layerHandlings) do
		mem:add(layerHandling.addr, #layerHandling.code, 'layer handling code', layerHandling.roomStates[1].m)
	end

	for _,enemySpawnSet in ipairs(self.enemySpawnSets) do
		mem:add(enemySpawnSet.addr, 3 + #enemySpawnSet.enemySpawns * ffi.sizeof'enemySpawn_t', 'enemySpawn_t', enemySpawnSet.roomStates[1].m)
	end
	for _,enemyGFXSet in ipairs(self.enemyGFXSets) do
		-- 10 = 8 for name, 2 for term
		mem:add(enemyGFXSet.addr - 8, 10 + #enemyGFXSet.enemyGFXs * ffi.sizeof'enemyGFX_t', 'enemyGFX_t', enemyGFXSet.roomStates[1].m)
	end

	for _,plmset in ipairs(self.plmsets) do
		local m = plmset.roomStates[1].m
		--[[ entry-by-entry
		local addr = plmset.addr
		for _,plm in ipairs(plmset.plms) do
			mem:add(addr, ffi.sizeof'plm_t', 
				'plm_t',
				--'plm '..ffi.cast('plm_t*',rom+addr)[0], 
				m)
			addr = addr + ffi.sizeof'plm_t'
		end
		mem:add(addr, 2, 
			'plm_t term',
			--'plm '..ffi.cast('uint16_t*',rom+addr)[0], 
			m)
		--]]
		-- [[ all at once
		local len = 2 + #plmset.plms * ffi.sizeof'plm_t'
		mem:add(plmset.addr, len, 'plm_t', m)
		--]]
		for _,scrollmod in ipairs(plmset.scrollmods) do	
			mem:add(scrollmod.addr, #scrollmod.data, 'plm scrollmod', m)
		end
	end
	for _,room in ipairs(self.rooms) do
		mem:add(room.addr, room.compressedSize, 'room', room.mdbs[1])
	end
end

function SMMap:mapWritePLMs()
	local rom = self.rom
	
	-- [[ re-indexing the doors
	--[=[
	notes on doors:
	plm_t of door_* has an x and y that matches up with the door region in the map
	the plm arg low byte of each (non-blue) door is a unique index, contiguous 0x00..0x60 and 0x80..0xac
	(probably used wrt savefiles, to know what doors have been opened)
	certain grey doors have nonzero upper bytes, either  0x00, 0x04, 0x08, 0x0c, 0x18, 0x90, 0x94
	
	TODO the plm is associated with a sm.rooms[i].doors[j]
	is the plm:door relation always 1-1, or can you have multiple plms per door, as you can have multiple roomStates per room?
	in that case, should I be duplicating IDs between PLMs?
	or perhaps I should not reindex here, but instead I should use the PLM's index to look up the associated sm.rooms[].doors[]?
	--]=]
	print'all door plm ids:'
	-- re-id all door plms?
	local doorid = 0
	for _,plmset in ipairs(self.plmsets) do
		local eyeparts
		local eyedoor
		for _,plm in ipairs(plmset.plms) do
			local name = self.plmCmdNameForValue[plm.cmd]
			if name 
			and name:match'^door_' 
			then
				-- if it's an eye door part then
				--  find the associated eye door, and make sure their ids match up
				if name:match'^door_eye_.*_part' then
					eyeparts = eyeparts or table()
					eyeparts:insert(plm)
				elseif name:match'^door_eye_' then
					assert(not eyedoor, "one eye door per room, I guess")
					eyedoor = plm
				end

				plm.args = bit.bor(
					bit.band(0xff00, plm.args),
					bit.band(0xff, doorid)
				)

				doorid = doorid + 1
			end
		end
		if eyedoor then 
			assert(eyeparts and #eyeparts > 0)
			for _,part in ipairs(eyeparts) do
				part.args = eyedoor.args
			end
		end
	end
print("used a total of "..doorid.." special and non-special doors")	
	-- notice, I only see up to 0xac used, so no promises there is even 0xff available in memory
	if doorid > 0xff then
		print("!!! WARNING !!! we made more doors than the save state could handle: "..doorid)
	end
	--]]

	-- [[ re-indexing the items ...
	-- what about duplicate roomStates with separate item plms in each state?
	-- in the origial metroid, there is only 1 item per unique name -- no reuised item ids spanning multiple plmsets
	-- how about incorportaing this into sm-items as well? maybe.
	-- how about not doing this at all, since sm-items will just rearrange things but not inc/dec?
	-- how about when I do item-scavenger and I duplicate items across their multiple PLMs?
	--  then I want to write the item id there and not here ...
	local itemid = 0
	for _,plmset in ipairs(self.plmsets) do
		for _,plm in ipairs(plmset.plms) do
			local name = self.plmCmdNameForValue[plm.cmd]
			if name and name:match'^item_' then
				plm.args = itemid
				itemid = itemid + 1 
			end
		end
	end
	--assert(itemid <= 100, "too many items (I think?)")
	--]]

	-- [[ optimizing plms ... 
	-- if a plmset is empty then clear all rooms that point to it, and remove it from the plmset master list
	for _,plmset in ipairs(self.plmsets) do
		if #plmset.plms == 0 then
			for j=#plmset.roomStates,1,-1 do
				local rs = plmset.roomStates[j]
				rs.ptr.plm = 0
				rs:setPLMSet(nil)
			end
		end
	end
	--]]
	-- [[ remove empty plmsets
	for i=#self.plmsets,1,-1 do
		local plmset = self.plmsets[i]
		if #plmset.plms == 0 then
			print('!!! removing empty plmset !!! '..('%06x'):format(plmset.addr))
			self.plmsets:remove(i)
		end
	end
	--]]
	-- [[ remove plmsets not referenced by any roomstates
	for i=#self.plmsets,1,-1 do
		local plmset = self.plmsets[i]
		if #plmset.roomStates == 0 then
			print('!!! removing plmset that is never referenced !!! '..('%06x'):format(plmset.addr))
			self.plmsets:remove(i)
		end
	end
	--]]
	-- [[ if two plms point to matching scrollmods then point them to the same scrollmod
	local allScrollMods = table()
	for _,plmset in ipairs(self.plmsets) do
		for _,scrollmod in ipairs(plmset.scrollmods) do
			allScrollMods:insert(scrollmod)
		end
	end
	local remapScrollModAddr = table()	--[fromAddr] = toAddr
	for i=1,#allScrollMods-1 do
		local si = allScrollMods[i]
		for j=#allScrollMods,i+1,-1 do
			local sj = allScrollMods[j]
			if tablesAreEqual(si.data, sj.data) then
				local siaddr = bit.band(0xffff, si.addr)
				local sjaddr = bit.band(0xffff, sj.addr)
				print('scrollmod #'..i..' addr '..('%04x'):format(siaddr)..' and #'..j..' addr '..('%04x'):format(sjaddr)..' data matches ... removing the latter')
				allScrollMods:remove(j)
				remapScrollModAddr[sjaddr] = siaddr
			end
		end
	end
	for _,plmset in ipairs(self.plmsets) do
		for _,plm in ipairs(plmset.plms) do
			if plm.cmd == self.plmCmdValueForName.scrollmod then
				plm.args = remapScrollModAddr[plm.args] or plm.args
			end
		end
	end
	for i=#allScrollMods,1,-1 do
		local scrollmod = allScrollMods[i]
		local addr = bit.band(scrollmod.addr, 0xffff)
		if remapScrollModAddr[addr] then
			print('TODO remove scrollmod at '..('%04x'):format(addr)..' to save '..('0x%x'):format(#scrollmod.data)..' bytes')
			allScrollMods:remove(i)
		end
	end
	--]]
	-- get rid of any duplicate plmsets ... there are none by default
	for i=1,#self.plmsets-1 do
		local pi = self.plmsets[i]
		for j=i+1,#self.plmsets do
			local pj = self.plmsets[j]
			if #pi.plms == #pj.plms 
			-- a lot of zero-length plms match ... but what about non-zero-length plms? none match
			and #pi.plms > 0
			then
				local differ
				for k=1,#pi.plms do
					if pi.plms[k] ~= pj.plms[k] then
						differ = true
						break
					end
				end
				if not differ then
					local piaddr = ('$%06x'):format(pi.addr)
					local pjaddr = ('$%06x'):format(pj.addr)
					print('plmsets '..piaddr..' and '..pjaddr..' are matching -- removing '..pjaddr)
					for _,rs in ipairs(table(pj.roomStates)) do
						rs.ptr.plm = bit.band(0xffff, pi.addr)
						rs:setPLMSet(pi)
					end
					self.plmsets:remove(j)
					break
				end
			end
		end
	end
	--]]

	-- [[ writing back plms...
	--[=[
	plm memory ranges:
	 0/ 0: $078000..$079193 (plm_t x174) 
	 3/ 0: $07c215..$07c230 (plm_t x2) 
		... 20 bytes of padding ...
	 3/ 3: $07c245..$07c2fe (plm_t x15) 
		... 26 bytes of padding ...
	 3/ 3: $07c319..$07c8c6 (plm_t x91) 
		... 199 bytes of padding ...
	--]=]
	-- where plms were written before, so should be safe, right?
	-- ranges are inclusive
	local plmWriteRanges = WriteRange('plm_t', {
		{0x78000, 0x79193},	
		-- then comes 100 bytes of layer handling code
		-- then mdb's (see mdbWriteRanges {0x791f8, 0x7b769})
		-- then comes door codes 0x7b971 to end of 0x7c0fa routine
		{0x7c215, 0x7c8c6},
		-- next comes 199 bytes of layer handling code, which is L12 data, and then more mdb's
		-- then comes door codes 0x7e1d8 to end of 0x7e513 routine
		{0x7e87f, 0x7e880},	-- a single plm_t 2-byte terminator ...
		
		-- TODO don't use this until you're sure of what it is.
		-- then comes a lot of unknown data 
		-- this is listed as 'free data' in the metroid rom map
		-- however $7ff00 is where the wake_zebes.ips door code of room 01/0e points to... which is the door_t on the right side of the blue brinstar morph ball room
		{0x7e99b, 0x7ffff},	
	
		-- TODO write the map rooms first.  that is compressing at 50% of the original.  there is room to spare there.
	})

	-- TODO any code that points to a PLM needs to be updated as well
	-- like whatever changes doors around from blue to grey, etc
	-- otherwise you'll find grey doors where you don't want them
	print()
	for _,plmset in ipairs(self.plmsets) do
		local bytesToWrite = #plmset.plms * ffi.sizeof'plm_t' + 2	-- +2 for null term
		local addr, endaddr = plmWriteRanges:get(bytesToWrite)
		plmset.addr = addr 

		-- write
		for _,plm in ipairs(plmset.plms) do
			ffi.cast('plm_t*', rom + addr)[0] = plm
			addr = addr + ffi.sizeof'plm_t'
		end
		-- write term
		ffi.cast('uint16_t*', rom+addr)[0] = 0
		addr = addr + ffi.sizeof'uint16_t'
		assert(addr == endaddr)

		local newofs = bit.band(0xffff, plmset.addr)
		for _,rs in ipairs(plmset.roomStates) do
			if newofs ~= rs.ptr.plm then
				--print('updating roomstate plm from '..('%04x'):format(rs.ptr.plm)..' to '..('%04x'):format(newofs))
				rs.ptr.plm = newofs
			end
		end
	end
	plmWriteRanges:print()
	--]]
end

function SMMap:mapWriteEnemySpawnSets()
	local rom = self.rom

	-- preserve order
	self.enemySpawnSets:sort(function(a,b) return a.addr < b.addr end)
	
	-- [[ get rid of duplicate enemy spawns
	-- this currently crashes the game
	-- notice that re-writing the enemy spawns is working fine
	-- but removing the duplicates crashes as soon as the first room with monsters is encountered 
	for i=1,#self.enemySpawnSets-1 do
		local pi = self.enemySpawnSets[i]
		for j=#self.enemySpawnSets,i+1,-1 do
			local pj = self.enemySpawnSets[j]
			if #pi.enemySpawns == #pj.enemySpawns 
			and pi.enemiesToKill == pj.enemiesToKill 
			then
				local differ
				for k=1,#pi.enemySpawns do
					if pi.enemySpawns[k] ~= pj.enemySpawns[k] then
						differ = true
						break
					end
				end
				if not differ then
					local piaddr = ('$%06x'):format(pi.addr)
					local pjaddr = ('$%06x'):format(pj.addr)
					print('enemySpawns '..piaddr..' and '..pjaddr..' are matching -- removing '..pjaddr)
					for _,rs in ipairs(table(pj.roomStates)) do
						print('updating roomState '..('%06x'):format(ffi.cast('unsigned char*',rs.ptr)-rom))
						rs.ptr.enemySpawn = bit.band(0xffff, pi.addr)
						rs:setEnemySpawnSet(pi)
					end
					self.enemySpawnSets:remove(j)
					break
				end
			end
		end
	end
	--]]

	-- [[ update enemy spawn
	local enemySpawnWriteRanges = WriteRange('enemySpawn_t', {
		-- original spawns goes up to $10ebd0, but the super metroid ROM map says the end of the bank is free
		{0x108000, 0x10ffff},
	})
	for _,enemySpawnSet in ipairs(self.enemySpawnSets) do
		local bytesToWrite = #enemySpawnSet.enemySpawns * ffi.sizeof'enemySpawn_t' + 3 	-- 2 for term, 1 for enemiesToKill
		local addr, endaddr = enemySpawnWriteRanges:get(bytesToWrite)
		enemySpawnSet.addr = addr
	
		-- write
		for i,enemySpawn in ipairs(enemySpawnSet.enemySpawns) do
			ffi.cast('enemySpawn_t*', rom + addr)[0] = enemySpawn
			addr = addr + ffi.sizeof'enemySpawn_t'
		end
		-- write term
		ffi.cast('uint16_t*', rom + addr)[0] = 0xffff
		addr = addr + 2
		-- write enemiesToKill
		rom[addr] = enemySpawnSet.enemiesToKill
		addr = addr + 1

		assert(addr == endaddr)
		local newofs = bit.band(0xffff, enemySpawnSet.addr)
		for _,rs in ipairs(enemySpawnSet.roomStates) do
			if newofs ~= rs.ptr.enemySpawn then
				--print('updating roomstate enemySpawn addr from '..('%04x'):format(rs.ptr.enemySpawn)..' to '..('%04x'):format(newofs))
				rs.ptr.enemySpawn = newofs
			end
		end
	end
	enemySpawnWriteRanges:print()
	--]]
end
	
function SMMap:mapWriteEnemyGFXSets()
	local rom = self.rom
	
	-- preserve order
	self.enemyGFXSets:sort(function(a,b) return a.addr < b.addr end)
	
	-- [[ update enemy set
	-- I'm sure this will fail.  there's lots of mystery padding here.
	local enemyGFXWriteRanges = WriteRange('enemyGFX_t', {
		{0x1a0000, 0x1a12c5},
		-- next comes a debug routine, listed as $9809-$981e
		-- then next comes a routine at $9961 ...
	})
	for j,enemyGFXSet in ipairs(self.enemyGFXSets) do
		-- special case for the first one -- it has no name so we don't need 8 bytes preceding
		-- it also has no entries, so that makes things easy
		if j == 0 then
			assert(enemyGFXSet.addr == 0)
			assert(#enemyGFXSet.enemyGFXs == 0)
		end 
		local saveName = j ~= 0
		
		local addr, endaddr = enemyGFXWriteRanges:get(2 + #enemyGFXSet.enemyGFXs * ffi.sizeof'enemyGFX_t' + (saveName and 8 or 0))
		if saveName then
			local name = enemyGFXSet.name
			for i=1,#name do
				rom[addr+i-1] = name:byte(i,i)
			end
			addr = addr + 8
		end
	
		enemyGFXSet.addr = addr
		for i,enemyGFX in ipairs(enemyGFXSet.enemyGFXs) do
			ffi.cast('enemyGFX_t*', rom + addr)[0] = enemyGFX
			addr = addr + ffi.sizeof'enemyGFX_t'
		end
		ffi.cast('uint16_t*', rom + addr)[0] = 0xffff	-- term
		addr = addr + 2

		assert(addr == endaddr)
		local newofs = bit.band(0x7fff, enemyGFXSet.addr) + 0x8000
		for _,rs in ipairs(enemyGFXSet.roomStates) do
			if newofs ~= rs.ptr.enemyGFX then
				--print('updating roomstate enemyGFX addr from '..('%04x'):format(rs.ptr.enemyGFX)..' to '..('%04x'):format(newofs))
				rs.ptr.enemyGFX = newofs
			end
		end
	end
	enemyGFXWriteRanges:print()
	--]]
end


function SMMap:mapWriteMDBs()
	local rom = self.rom
	
	
	-- [[ if two roomstates point to matching scrolldata then point them to the same scrolldata
	-- notice this is nearly identical to the plms + scrollmod testing
	local allScrollDatas = table()
	for _,m in ipairs(self.mdbs) do
		for _,rs in ipairs(m.roomStates) do
			if rs.ptr.scroll > 0x0001 and rs.ptr.scroll ~= 0x8000 then
				assert(rs.scrollData)
				allScrollDatas:insert{
					addr=rs.ptr.scroll,
					data=rs.scrollData,
				}
			else
				assert(not rs.scrollData)
			end
		end
	end
	local remapScrollDataAddr = table()	--[fromAddr] = toAddr
	for i=1,#allScrollDatas-1 do
		local si = allScrollDatas[i]
		for j=#allScrollDatas,i+1,-1 do
			local sj = allScrollDatas[j]
			if tablesAreEqual(si.data, sj.data) then
				local siaddr = si.addr
				local sjaddr = sj.addr
				--print('scrolldata #'..i..' addr '..('%04x'):format(siaddr)..' and #'..j..' addr '..('%04x'):format(sjaddr)..' data matches ... removing the latter')
				allScrollDatas:remove(j)
				remapScrollDataAddr[sjaddr] = siaddr
			end
		end
	end
	for _,m in ipairs(self.mdbs) do
		for _,rs in ipairs(m.roomStates) do
			if rs.ptr.scroll > 0x0001 and rs.ptr.scroll ~= 0x8000 then
				rs.ptr.scroll = remapScrollDataAddr[rs.ptr.scroll] or rs.ptr.scroll
			end
		end
	end
	for i=#allScrollDatas,1,-1 do
		local scrollData = allScrollDatas[i]
		if remapScrollDataAddr[scrollData.addr] then
			print('TODO remove scrolldata at '..('%04x'):format(scrollData.addr)..' to save '..('0x%x'):format(#scrollData.data)..' bytes')
			--allScrollDatas:remove(i)
		end
	end
	--]]
	
	
	
	-- writing back mdb_t
	-- if you move a mdb_t
	-- then don't forget to reassign all mdb.dooraddr.door_t.dest_mdb
	local mdbWriteRanges = WriteRange('mdb_t', {
		{0x791f8, 0x7b769},	-- mdbs of regions 0-2
		-- then comes bg_t's 
		-- then comes door codes 0x7b971 to end of 0x7c0fa routine
		-- then comes plm_t's
		{0x7c98e, 0x7e0fc},	-- mdbs of regions 3-6
		-- then comes db_t's 
		-- then comes door codes 0x7e1d8 to end of 0x7e513 routine
		{0x7e82c, 0x7e85a},	-- single mdb of region 7
		-- then comes door code
	})

	-- compress roomstates ...
	-- for all plm scrollmods, if they have matching data then combine their addresses

	for _,m in ipairs(self.mdbs) do
		-- write the mdb_t
		-- write the roomselects
		-- write the roomstates
		-- write the dooraddrs
		-- write the scrolldata ... (who points to this?)
		-- write the plm scrollmod stuff ... (who points to this?)
	end
end

function SMMap:mapWriteRooms()
	local rom = self.rom
	-- [[ write back compressed data
	local roomWriteRanges = WriteRange('room', {
		--[=[ there are some bytes outside compressed regions but between a few roomdatas
		-- the metroid rom map says these are a part of the room data
		-- this includes those breaks
		{0x2142bb, 0x235d76},
		{0x235ee0, 0x244da8},
		{0x24559c, 0x272502},
		{0x272823, 0x27322d},
		--]=]
		-- [=[ and this doesn't -- one giant contiguous region
		{0x2142bb, 0x277fff},
		--]=]
	})
	-- ... reduces to 56% of the original compressed data
	-- but goes slow
	local totalOriginalCompressedSize = 0
	local totalRecompressedSize = 0
	print()
	for _,room in ipairs(self.rooms) do
		local data = room:getData()
		local recompressed = lz.compress(data)
	--	print('recompressed size: '..ffi.sizeof(recompressed)..' vs original compressed size '..room.compressedSize)
	-- this doesn't matter
	--	assert(ffi.sizeof(recompressed) <= room.compressedSize, "recompressed to a larger size than the original.  recompressed "..ffi.sizeof(recompressed).." vs original "..room.compressedSize)
		totalOriginalCompressedSize = totalOriginalCompressedSize + room.compressedSize
		totalRecompressedSize = totalRecompressedSize + ffi.sizeof(recompressed)
		
		data = recompressed
		room.compressedSize = ffi.sizeof(recompressed)
		--[=[ now write back to the original location at addr
		ffi.copy(rom + room.addr, data, ffi.sizeof(data))
		--]=]
		-- [=[ write back at a contiguous location
		-- (don't forget to update all roomstate_t's roomBank:roomAddr's to point to this
		-- TODO this currently messes up the scroll change in wrecked ship, when you go to the left to get the missile in the spike room
		local fromaddr, toaddr = roomWriteRanges:get(ffi.sizeof(data))

		-- do the write
		ffi.copy(rom + fromaddr, data, ffi.sizeof(data))
		-- update room addr
	--	print('updating room address '
	--		..('%02x/%02x'):format(room.mdbs[1].ptr.region, room.mdbs[1].ptr.index)
	--		..' from '..('$%06x'):format(room.addr)..' to '..('$%06x'):format(fromaddr))
		room.addr = fromaddr
		-- update any roomstate_t's that point to this data
		for _,rs in ipairs(room.roomStates) do
			rs.ptr.roomBank = bit.rshift(room.addr, 15) + 0x80 
			rs.ptr.roomAddr = bit.band(room.addr, 0x7fff) + 0x8000
		end
		--]=]

	--[=[ verify that compression works by decompressing and re-compressing
		local data2, compressedSize2 = lz.decompress(rom, room.addr, 0x10000)
		assert(compressedSize == compressedSize2)
		assert(ffi.sizeof(data) == ffi.sizeof(data2))
		for i=0,ffi.sizeof(data)-1 do
			assert(data[i] == data2[i])
		end
	--]=]
	end
	print()
	print('rooms recompressed from '..totalOriginalCompressedSize..' to '..totalRecompressedSize..
		', saving '..(totalOriginalCompressedSize - totalRecompressedSize)..' bytes '
		..'(new data is '..math.floor(totalRecompressedSize/totalOriginalCompressedSize*100)..'% of original size)')

	-- output memory ranges
	roomWriteRanges:print()
	--]]
end

-- write back changes to the ROM
-- right now my structures are mixed between ptrs and by-value copied objects
-- so TODO eventually have all ROM writing in this routine
function SMMap:mapWrite()
	-- [[ write these before writing roomstates
	-- write rooms first so the rest can use the free space?
	--  too bad, they use a different bank from the others
	self:mapWriteRooms()
	self:mapWritePLMs()
	self:mapWriteEnemyGFXSets()
	self:mapWriteEnemySpawnSets()
	--]]

	self:mapWriteMDBs()	-- not yet
end

return SMMap
