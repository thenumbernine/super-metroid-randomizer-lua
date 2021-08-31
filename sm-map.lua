-- https://github.com/tewtal/smlib especially SMLib/ROMHandler.cs
-- metroidconstruction.com/SMMM
-- https://github.com/dansgithubuser/dansSuperMetroidLibrary/blob/master/sm.hpp
-- http://forum.metroidconstruction.com/index.php?topic=2476.0
-- http://www.metroidconstruction.com/SMMM/plm_disassembly.txt

--[[
tile graphics TODO's:
1) bug rooms are showing up black. 
2) ceres 1st and last room tileset show up black... $11, $12, $13, $14 
--]]

local ffi = require 'ffi'
local struct = require 'struct'
local lz = require 'lz'
local vector = require 'ffi.cpp.vector'
local WriteRange = require 'writerange'
local disasm = require 'disasm'


local mapSaveMode7TileSets = true
local mapSaveWorldImage = true
local mapSaveTileSets = true
local mapSaveLayer2Backgrounds = true
local mapSaveBackgrounds = true

local SMMap = {}


SMMap.fx1Bank = 0x83
SMMap.doorBank = 0x83

-- each room and its roomstates, dooraddrs, and scrolldata are stored grouped together
SMMap.roomBank = 0x8f
SMMap.roomStateBank = 0x8f	-- bank for roomselect_t.roomStateAddr
SMMap.doorAddrBank = 0x8f	-- bank for room_t.doors
SMMap.scrollBank = 0x8f		-- if scrolldata is stored next to room, roomstate, and dooraddr, then why does it have a separate bank?
-- then between groups of rooms (and their content) are groups of bg_t's and doorcodes
SMMap.bgBank = 0x8f			
SMMap.doorCodeBank = 0x8f
-- then comes a group o fplms, and then comes a group of layer handling
SMMap.layerHandlingBank = 0x8f
-- TODO use a bank? isn't it the same as the roomBank?  0x8f.
SMMap.plmBaseAddress = 0x70000
-- and then we go back to some more rooms

SMMap.enemySpawnBank = 0xa1
SMMap.enemyGFXBank = 0xb4


local commonRoomSubtileAddr = 0x1c8000
local commonRoomTilemapAddr = 0x1ca09d


local blocksPerRoom = 16
local blockSizeInPixels = 16
local debugImageRoomSizeInPixels = blocksPerRoom * blockSizeInPixels

-- 128x128 tile indexes (0-255), each tile is [256][8][8]
local graphicsTileSizeInPixels = 8
local graphicsTileSizeInBytes = graphicsTileSizeInPixels * graphicsTileSizeInPixels / 2	-- 4 bits per pixel
local numMode7Tiles = 256
local mode7sizeInGraphicTiles = 128
assert(mode7sizeInGraphicTiles * mode7sizeInGraphicTiles == numMode7Tiles * graphicsTileSizeInPixels * graphicsTileSizeInPixels)


-- the 'mdb' defined in section 6 of metroidconstruction.com/SMMM
local room_t = struct{
	name = 'room_t',
	fields = {	-- aka mdb, aka mdb_header
		{index = 'uint8_t'},
		{region = 'uint8_t'},
		{x = 'uint8_t'},
		{y = 'uint8_t'},
		{width = 'uint8_t'},
		{height = 'uint8_t'},
		{upScroller = 'uint8_t'},
		{downScroller = 'uint8_t'},
		{gfxFlags = 'uint8_t'},
		{doors = 'uint16_t'},
	},
}

-- roomselect testCodeAddr is stored from $e5e6 to $e689 (inclusive)

local roomselect1_t = struct{
	name = 'roomselect1_t',
	fields = {
		{testCodeAddr = 'uint16_t'},
	},
}

local roomselect2_t = struct{
	name = 'roomselect2_t',
	fields = {
		{testCodeAddr = 'uint16_t'},
		{roomStateAddr = 'uint16_t'},
	},
}

-- this is how the mdb_format.txt describes it, but it looks like the structure might be a bit more conditional...
local roomselect3_t = struct{
	name = 'roomselect3_t',
	fields = {
		{testCodeAddr = 'uint16_t'},		-- ptr to test code in bank $8f
		{testvalue = 'uint8_t'},
		{roomStateAddr = 'uint16_t'},		-- ptr to roomstate in bank $8f
	},
}

local roomstate_t = struct{
	name = 'roomstate_t',
	fields = {
		{roomBlockAddr24 = 'addr24_t'},		-- points to block data.  bank is $c2 to $c9
		{tileSet = 'uint8_t'},				-- tile graphics data
		{musicTrack = 'uint8_t'},
		{musicControl = 'uint8_t'},
		{fx1Addr = 'uint16_t'},				-- $83
		{enemySpawnAddr = 'uint16_t'},		-- TODO "enemySpawnSetAddr". points to an array of enemySpawn_t
		{enemyGFXAddr = 'uint16_t'},		-- holds palette info on the enemies used?  points to an array of enemyGFX_t's ... which are just pairs of enemyClass_t's + palettes
	
		--[[
		From https://wiki.metroidconstruction.com/doku.php?id=super:technical_information:data_structures:
				
			The layer 2 scroll X/Y is a value that determines whether or not custom layer 2 is used, and how fast layer 2 scrolls compared to layer 1 (parallax effect)
				In binary, let layer 2 scroll X/Y = sssssssb
				If b = 1, then the library background is used, otherwise custom layer 2 (defined in level data) is used
				s = 0 is a special case that depends on b
					If b = 0 (custom layer 2), then layer 2 and layer 1 scroll together at the same speed (like an extension of layer 1)
					If b = 1 (library background), then layer 2 does not scroll at all (static image background)
				Otherwise (if s != 0), layer 2 scroll speed = (layer 1 scroll speed) * (s / 0x80)
		
		... I'm really not sure what this means.  Not sure if the 'sssb' means 'b' is bit0 or bit7 ... or bit15 since it's referering to a uint16_t .... smh 
		--]]
		{layer2scrollXY = 'uint16_t'},	-- TODO
		
		--[[
		scroll is either a constant, or an offset in bank $8f to 1 byte per map block
		if scroll is 0 or 1 then it is a constant -- to fill all map blocks with that scroll value
		otherwise it is a ptr to an array of scroll values for each map block.
		0 = don't scroll up/down, or past the scroll==0 boundaries at all
		1 = scroll anywhere, but clip the top & bottom 2 blocks (which will hide vertical exits)
		2 = scroll anywhere at all ... but keeps samus in the middle, which makes it bad for hallways
		--]]
		{scrollAddr = 'uint16_t'},
		
		--[[
		this is only used by the grey torizo room, and points to the extra data after room_t
		--]]
		{roomvarAddr = 'uint16_t'},				
		{fx2Addr = 'uint16_t'},					-- TODO - aka 'main asm ptr'
		{plmAddr = 'uint16_t'},
		{bgAddr = 'uint16_t'},				-- offset to bg_t's
		{layerHandlingAddr = 'uint16_t'},
	},
}

-- plm = 'post-load modification'
-- this is a non-enemy object in a map.
local plm_t = struct{
	name = 'plm_t',
	fields = {
		{cmd = 'uint16_t'},			-- TODO rename to plmAddr?  but that is ambiguous with this struct's name.  How to keep this analogous with enemyAddr vs enemyClass_t vs enemySpawn_t ... maybe rename this to plmSpawn_t ? hmm...
		{x = 'uint8_t'},
		{y = 'uint8_t'},
		{args = 'uint16_t'},
	},
}

-- this is a single spawn location of an enemy.
-- also called "enemy population" in some notes
local enemySpawn_t = struct{
	name = 'enemySpawn_t',
	fields = {
		{enemyAddr = 'uint16_t'},	-- matches enemies[].addr, instance of enemyClass_t
		{x = 'uint16_t'},			-- fixed_t pixel:subpixel
		{y = 'uint16_t'},			-- fixed_t
		{initGFX = 'uint16_t'},		-- init param / tilemaps / orientation
		{prop1 = 'uint16_t'},		-- special
		{prop2 = 'uint16_t'},		-- graphics
		{roomArg1 = 'uint16_t'},	-- speed
		{roomArg2 = 'uint16_t'},	-- speed2
	},
}

-- enemy sets have a list of entries
-- each entry points to an enemy and a palette
local enemyGFX_t = struct{
	name = 'enemyGFX_t',
	fields = {
		{enemyAddr = 'uint16_t'},	-- matches enemies[].addr
		{palette = 'uint16_t'},
	},
}

--[[
https://wiki.metroidconstruction.com/doku.php?id=super%3Atechnical_information%3Adata_structures
values used: 
00: lots
02: lots
04: lots
06: lots
08: 01/01 01/08 01/09 01/16
0a: 00/00
0c: 00/12 00/13 00/30
24: 01/06 01/21 02/4b
26: 00/33
28: 06/05
2a: 06/00
--]]
local fx1Types = {
	none = 0,
	lava = 2,
	acid = 4,
	water = 6,
	spores = 8,
	rain = 0xa,
	fog = 0xc,
	scrollingSky = 0x20,
	--unused = 0x22,	-- a lot more values than just 0x22 are unused ...
	fireflea = 0x24,
	tourianEntranceStatue = 0x26,
	ceresRidley = 0x28,
	ceresElevator = 0x2a,
	haze = 0x2c,
}

--[[
fx1 a b values:
https://wiki.metroidconstruction.com/doku.php?id=super%3Atechnical_information%3Adata_structures
2/Eh/20h	Normal. BG1/BG2/sprites are drawn with BG3 added on top	
4	Normal, but BG2 is disabled	Used by Phantoon
6	Normal, but sprites aren't affected by BG3 and sprites are added to BG1/BG2 (instead of hidden)	Unused
8	Normal, but BG1/sprites aren't affected by BG3 and sprites are added to BG2 (instead of hidden)	Used in some power off Wrecked Ship rooms
Ah	Normal, but BG1 isn't affected by BG3	Used with FX layer 3 type = spores
Ch	Normal, but BG3 is disabled and colour math is subtractive	Used with FX layer 3 type = fireflea
10h/12h	Normal, but BG3 is disabled inside window 1	Used by morph ball eye and varia/gravity suit pickup
14h/22h	Normal, but BG1 isn't affected by BG3 and colour math is subtractive	Sometimes use with FX layer 3 type = water
16h	BG1/sprites are drawn after the result of drawing BG2/BG3 is subtracted	Sometimes use with FX layer 3 type = water
18h/1Eh/30h	BG3 is drawn with the result of drawing BG1/BG2/sprites added on top	Used with FX layer 3 type = lava / acid / fog / Tourian entrance statue, sometimes use with FX layer 3 type = water
1Ah	Normal, but BG2 and BG3 have reversed roles	Used by Phantoon
1Ch	Normal, but BG2 and BG3 have reversed roles, colour addition is halved and backdrop is disabled	Unused
24h	BG1/BG2/sprites are drawn the backdrop is added on top inside window 1	Used by Mother Brain
26h	Normal, but colour addition is halved	Unused
28h	Normal, but BG3 is disabled, colour math is subtractive, and the backdrop subtracts red if there is no power bomb explosion	Used in some default state Crateria rooms, some power off Wrecked Ship rooms, pre plasma beam rooms
2Ah	Normal, but BG3 is disabled, colour math is subtractive, and the backdrop subtracts orange if there is no power bomb explosion	Used in blue Brinstar rooms, Kraid's lair entrance, n00b tube side rooms, plasma beam room, some sand falls rooms
2Ch	Normal, but BG3 is disabled	Used by FX layer 3 type = haze and torizos
2Eh	Normal, but colour math is subtractive	Unused
32h	Normal, but BG1 isn't affected by BG3 and colour math is subtractive	Unused
34h	Normal, but power bombs don't affect BG2	Unused
--]]

-- http://metroidconstruction.com/SMMM/fx_values.txt
local fx1_t = struct{
	name = 'fx1_t',
	fields = {
		-- bank $83, ptr to door data.  0 means no door-specific fx
		{doorAddr = 'uint16_t'},				-- 0
		-- starting height of water/lava/acid
		-- aka "base y position"
		{liquidStarHeight = 'uint16_t'},		-- 2
		-- ending height of water
		-- aka "target y position"
		{liquidEndHeight = 'uint16_t'},			-- 4

		--[[ from metroidconstruction.com/SMMM:
		how long until the water/lava/acid starts to rise or lower. For rooms with liquid, you must use a value between 01 (instantly) and FF (a few seconds). For rooms with no liquid, use 00.
		For liquids moving up, use a surface speed value between FE00-FFFF. Examples: FFFE (absolute slowest), FFD0 (slow), FFD0 (decent speed), and FE00 (very fast).
		For liquids moving down, use a surface speed value between 0001-0100. Examples: 0001 (absolute slowest), 0020 (slow), 0040 (decent speed), 0100 (very fast). 
		--]]
		-- aka "y velocity"
		{liquidYVel = 'uint16_t'},				-- 6
		
		{timer = 'uint8_t'},					-- 8

		-- liquid, fog, spores, rain, etc
		{fxType = 'uint8_t'},					-- 9
		
		-- lighting options: 02 = normal, 28 = dark visor room, 2a = darker yellow-visor room
		-- "default layer blending configuration"
		{a = 'uint8_t'},						-- 0xa
		
		-- prioritize/color layers
		-- "fx layer 3 blending configuration"
		{b = 'uint8_t'},						-- 0xb
		
		-- liquid options
		--[[
		https://wiki.metroidconstruction.com/doku.php?id=super%3Atechnical_information%3Adata_structures
		1	Liquid flows (leftwards)
		2	Layer 2 is wavy
		4	Liquid physics are disabled (used in n00b tube room)
		40h	Big tide (liquid fluctuates up and down, a la the gauntlet)
		80h	Small tide (liquid fluctuates up and down)		
		--]]
		{c = 'uint8_t'},						-- 0xc
		
		{paletteFXFlags = 'uint8_t'},			-- 0xd
		
		{tileAnimateFlags = 'uint8_t'},			-- 0xe
		
		{paletteBlend = 'uint8_t'},				-- 0xf
	},											-- 0x10
}

--[[
now using http://patrickjohnston.org/bank/8F#fB76A
bg headers:
0000 = 2 bytes = terminator
0002 = 9 bytes
0004 = 7 bytes
0006 = 2 bytes (not used?)
0008 = 9 bytes
000a = 2 bytes
000c = 2 bytes (only used once)
000e = 11 bytes

explanation here: https://wiki.metroidconstruction.com/doku.php?id=super:technical_information:data_structures
--]]

--[[
used by 0, a, c
header==0x0 => terminator
header==0x6 => clear layer 3 (is this used?)
header==0xa => clear layer 2
header==0xc => clear kraid's layer 2
--]]
local bg_header_t = struct{
	name = 'bg_header_t',
	fields = {
		{header = 'uint16_t'},
	},
}

--[[
header==0x2 => copy len bytes from .addr24 to VRAM:.dstOfs
header==0x8 => copy len bytes from .addr24 to VRAM:.dstOfs ... and set bg3 tile base addr to $2000
--]]
local bg_2_8_t = struct{
	name = 'bg_2_8_t',
	fields = {
		{header = 'uint16_t'},
		{addr24 = 'addr24_t'},
		{dstOfs = 'uint16_t'},
		{len = 'uint16_t'},
	},
}

--[[
header==0x4 => decompress from .addr24 to $7e:.dstOfs
--]]
local bg_4_t = struct{
	name = 'bg_4_t',
	fields = {
		{header = 'uint16_t'},
		{addr24 = 'addr24_t'},
		{dstOfs = 'uint16_t'},
	},
}

--[[
header==0xe => copy len bytes from .addr24 to VRAM:.dstOfs if the current doorAddr == .doorAddr
--]]
local bg_e_t = struct{
	name = 'bg_e_t',
	fields = {
		{header = 'uint16_t'},
		{doorAddr = 'uint16_t'},
		{addr24 = 'addr24_t'},
		{dstOfs = 'uint16_t'},
		{len = 'uint16_t'},
	},
}

local bgCTypeForHeader = {
	[0x0] = bg_header_t,
	[0x2] = bg_2_8_t,
	[0x4] = bg_4_t,
	[0x6] = bg_header_t,
	[0x8] = bg_2_8_t,
	[0xa] = bg_header_t,
	[0xc] = bg_header_t,
	[0xe] = bg_e_t,
}



-- described in section 12 of metroidconstruction.com/SMMM
-- if a user touches a xx-9x-yy tile then the number in yy (3rd channel) is used to lookup the door_t to see where to go
-- This isn't the door so much as the information associated with its destination.
-- This doesn't reference the in-room door object so much as vice-versa.
-- I'm tempted to call this 'exit_t' ... since you don't need a door
local door_t = struct{
	name = 'door_t',
	fields = {
		{destRoomAddr = 'uint16_t'},				-- 0: points to the room_t to transition into
		
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
		
		{capX = 'uint8_t'},					-- 4	target room x offset lo to place you at
		{capY = 'uint8_t'},					-- 5	target room y offset lo
		{screenX = 'uint8_t'},				-- 6	target room x offset hi
		{screenY = 'uint8_t'},				-- 7	target room y offset hi
		{distToSpawnSamus = 'uint16_t'},	-- 9	distance from door to spawn samus
		{code = 'uint16_t'},				-- A	custom asm for the door
	},
}

-- this is what the metroid ROM map says ... "Elevator thing"
-- two dooraddrs point to a uint16_t of zero, at $0188fc and $01a18a, and they point to structs that only take up 2 bytes
-- you find it trailing the door_t corresponding with the lift
local lift_t = struct{
	name = 'lift_t',
	fields = {
		{zero = 'uint16_t'},
	},
}


-- http://patrickjohnston.org/bank/80
local loadStation_t = struct{
	name = 'loadStation_t',
	fields = {
		{roomAddr = 'uint16_t'},
		{doorAddr = 'uint16_t'},
		{doorBTS = 'uint16_t'},
		{screenX = 'uint16_t'},
		{screenY = 'uint16_t'},
		{offsetX = 'uint16_t'},
		{offsetY = 'uint16_t'},
	},
}

-- http://patrickjohnston.org/bank/82
local demoRoom_t = struct{
	name = 'demoRoom_t',
	fields = {
		{roomAddr = 'uint16_t'},
		{doorAddr = 'uint16_t'},
		{doorSlot = 'uint16_t'},
		{screenX = 'uint16_t'},
		{screenY = 'uint16_t'},
		{offsetX = 'uint16_t'},
		{offsetY = 'uint16_t'},
		{demoLength = 'uint16_t'},
		{codeAddr = 'uint16_t'},
	},
}

local tileSetCount = 29	-- this is the # that are used in metroid.

--[[
the first two bytes at 0x07e6a0 are the uint16 value 0xdc8, 
which equals 9 * 392 
... but adding that to the tileSetBaseOffset would overlap with plm_t data
which bank is this? $8f
--]]
local tileSetBaseOffset = 0x07e6a2 

--[[
this is a tilemapElem+graphicsTile+palette triplet
so if i wanted to optimize this then i should keep track of what tiles are used per each 'tile' and 'graphicsTile'
and that means i should try to decompress each into 16x16 bmps separately
and store separately sets of which are being referenced, for optimizations sake
--]]
local tileSet_t = struct{
	name = 'tileSet_t',
	fields = {
		{tileAddr24 = 'addr24_t'},
		{graphicsTileAddr24 = 'addr24_t'},
		{paletteAddr24 = 'addr24_t'},
	},
}
assert(ffi.sizeof'tileSet_t' == 9)

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


local Room = class()
function Room:init(args)
	self.roomStates = table()
	self.doors = table()
	for k,v in pairs(args) do
		self[k] = v
	end
end
function Room:setAddr(sm, addr)
	assert(addr >= 0 and addr < 0xffff, "expects a 16-bit page offset, not 24-bit")
	self.ptr = sm.rom + topc(sm.roomBank, addr)
end
function Room:getAddr(sm)
	assert(self.ptr, "you can't get the addr if you don't know the ptr")
	return bit.band(0xffff, ffi.cast('uint8_t*', self.ptr) - sm.rom)
end
function Room:findDoorTo(destRoom)
	local _, door = self.doors:find(nil, function(door) 
		return door.destRoom == destRoom
	end)
	return door
end

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
function RoomState:setRoomBlockData(roomBlockData)
	if self.roomBlockData then
		self.roomBlockData.roomStates:removeObject(self)
		self.roomBlockData:refreshRooms()
	end
	self.roomBlockData = roomBlockData
	if self.roomBlockData then
		self.roomBlockData.roomStates:insert(self)
		self.roomBlockData:refreshRooms()
	end
end
function RoomState:setTileSet(tileSet)
	if self.tileSet then
		self.tileSet.roomStates:removeObject(self)
	end
	self.tileSet = tileSet
	if self.tileSet then
		self.tileSet.roomStates:insert(self)
	end
end


--[[
alright, I'm just going to make plms as pure lua objects
so I can add optional extra data loke scrollmod directly to the plm
expected fields (from plm_t, so just use plm_t:toLua()):
	cmd
	x
	y
	args
	ptr
	scrollmod (optional)
--]]
local PLM = class()
SMMap.PLM = PLM

function PLM:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	assert(self.cmd)
	assert(self.x)
	assert(self.y)
	assert(self.args)
end

function PLM:getName()
	return sm.plmCmdNameForValue[self.cmd]
end

function PLM:toC()
	--return ffi.new('plm_t', self)
	return ffi.new('plm_t', {
		cmd = self.cmd,
		x = self.x,
		y = self.y,
		args = self.args,
	})
end

function PLM.__eq(a,b)
	--return a:toC() == b:toC()
	return a.cmd == b.cmd
		and a.x == b.x
		and a.y == b.y
		and a.args == b.args
end

function PLM.__concat(a,b) 
	return tostring(a) .. tostring(b) 
end

function PLM:__tostring()
	-- TODO don't forget about scrollmod
	-- sorted in order of data addresses
	--return tostring(self:toC())
	-- sorted in alphabetic order (and includes optional fields like 'scrollmod')
	return tolua(self) -- ... but it's not hex ...
end


local PLMSet = class()

function PLMSet:init(args)
	self.addr = args.addr	--optional
	self.plms = table(args.plms)
	self.roomStates = table()
end


local Door = class()
SMMap.Door = Door

-- args: 
-- 	just 'addr' right now - points to the door structure
--	and 'sm' for the super metroid hack global info
function Door:init(args)
	self.addr = assert(args.addr)
	local sm = args.sm
	local rom = sm.rom

	-- derived fields:
	local addr = topc(sm.doorBank, self.addr)
	local data = rom + addr 
	local destRoomAddr = ffi.cast('uint16_t*', data)[0]
	-- if destRoomAddr == 0 then it is just a 2-byte 'lift' structure ...
	local doorType = destRoomAddr == 0 and 'lift_t' or 'door_t'
	self.ctype = doorType
	self.ptr = ffi.cast(doorType..'*', data)
	if doorType == 'door_t' 
	and self.ptr.code > 0x8000 
	then
		self.doorCodeAddr = topc(sm.doorCodeBank, self.ptr.code)
		self.doorCode = disasm.readCode(rom, self.doorCodeAddr, 0x100)
	end
end

function Door:setDestRoom(room)
	self.ptr.destRoomAddr = bit.band(0xffff, room.addr)
	self.destRoom = room
end

-- TODO make common with mapAddTileSetTilemap
function SMMap:mapAddBGTilemap(addr)
	for _,tilemap in ipairs(self.bgTilemaps) do
		if tilemap.addr == addr then return tilemap end
	end
	
	local tilemap = {}
	tilemap.addr = addr
	self.bgTilemaps:insert(tilemap)

	--[[
	bg tilemap.size is 0x800 / 2048 or 0x1000 / 4096
	with 2 bytes per tilemapElem_t's, that means
	most are tilemap.size==0x800 <=> uint16_t tilemapElem[height=32][width=32]
	some are tilemap.size==0x1000 <=> uint16_t tilemapElem[height=64][width=32]
	--]]
	
	tilemap.data, tilemap.compressedSize = lz.decompress(self.rom, tilemap.addr, 0x10000)
	-- TODO ambiguous ... how about sizeInBytes?
	-- or about just using 'count' or 'len'
	tilemap.size = ffi.sizeof(tilemap.data)	

	local sizeofElem = ffi.sizeof'tilemapElem_t'
	assert(tilemap.size % sizeofElem == 0)
	local count = tilemap.size / sizeofElem		-- number of tilemaps
	tilemap.width = 32
	tilemap.height = count / tilemap.width
	assert(tilemap.width * tilemap.height * sizeofElem == tilemap.size)

	return tilemap
end

function SMMap:mapAddRoom(pageofs, buildRecursively)
	local _,m = self.rooms:find(nil, function(m) return m.addr == pageofs end)
	if m then return m end

	local absaddr = topc(self.roomBank, pageofs)

	local rom = self.rom
	local data = rom + absaddr
	local mptr = ffi.cast('room_t*', data)
	local m = Room{
	-- TODO bank-offset addr vs pc addr for all my structures ...
		addr = pageofs,
		
		-- switch over to this from ptr, and then to pure lua from this
		obj = ffi.new('room_t', mptr[0]),
		
		ptr = mptr,
	}	
	self.rooms:insert(m)
	
	data = data + ffi.sizeof'room_t'

	-- roomstates
	while true do
		local testCodeAddr = ffi.cast('uint16_t*',data)[0]
		
		local select_ctype
		if testCodeAddr == 0xe5e6 then 
			select_ctype = 'roomselect1_t'	-- default / end of the list
		elseif testCodeAddr == 0xe612
		or testCodeAddr == 0xe629
		or testCodeAddr == 0xe5eb
		then
			select_ctype = 'roomselect3_t'	-- this is for doors.  but it's not used. so whatever.
		else
			select_ctype = 'roomselect2_t'
		end
		local selptr = ffi.cast(select_ctype..'*', data)
		local rs = RoomState{
			room = m,
			select_ptr = selptr,
			select = ffi.new(select_ctype, selptr[0]),
			select_ctype = select_ctype,	-- using for debug print only
		}
		m.roomStates:insert(rs)
		
		data = data + ffi.sizeof(select_ctype)

		if select_ctype == 'roomselect1_t' then break end	-- term
	end

	-- after the last roomselect is the first roomstate_t
	local rs = m.roomStates:last()
	-- uint16_t select means a terminator
	assert(rs.select_ctype == 'roomselect1_t')
	rs.ptr = ffi.cast('roomstate_t*', data)
	rs.obj = ffi.new('roomstate_t', rs.ptr[0])
	data = data + ffi.sizeof'roomstate_t'

	-- then the rest of the roomstates come
	for _,rs in ipairs(m.roomStates) do
		if rs.select_ctype ~= 'roomselect1_t' then
			assert(not rs.ptr)
			local addr = topc(self.roomStateBank, rs.select.roomStateAddr)
			rs.ptr = ffi.cast('roomstate_t*', rom + addr)
			rs.obj = ffi.new('roomstate_t', rs.ptr[0])
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
		if rs.obj.scrollAddr > 0x0001 and rs.obj.scrollAddr ~= 0x8000 then
			local addr = topc(self.scrollBank, rs.obj.scrollAddr)
			local size = m.obj.width * m.obj.height
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
		if rs.obj.plmAddr ~= 0 then
			local addr = topc(self.plmBank, rs.obj.plmAddr)
			local plmset = self:mapAddPLMSetFromAddr(addr, m)
			rs:setPLMSet(plmset)
		end
	end

	-- enemySpawnSet
	-- but notice, for writing back enemy spawn sets, sometimes there's odd padding in there, like -1, 3, etc
	for _,rs in ipairs(m.roomStates) do
		local enemySpawnSet = self:mapAddEnemySpawnSet(topc(self.enemySpawnBank, rs.obj.enemySpawnAddr))
		rs:setEnemySpawnSet(enemySpawnSet)
	end
	
	for _,rs in ipairs(m.roomStates) do
		rs:setEnemyGFXSet(self:mapAddEnemyGFXSet(topc(self.enemyGFXBank, rs.obj.enemyGFXAddr)))
	end

	-- some rooms use the same fx1 ptr
	-- and from there they are read in contiguous blocks until a term is encountered
	-- so I should make these fx1sets (like plmsets)
	-- unless -- another optimization -- is, if one room's fx1's (or plms) are a subset of another,
	-- then make one set and just put the subset's at the end
	-- (unless the order matters...)
	for _,rs in ipairs(m.roomStates) do
		local startaddr = topc(self.fx1Bank, rs.obj.fx1Addr)
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
local done = fx1.ptr.doorAddr == 0 
				fx1.rooms:insert(m)
				rs.fx1s:insert(fx1)
				
				addr = addr + ffi.sizeof'fx1_t'

-- term of 0 past the first entry
if done then break end
			end
		end
	end

	for _,rs in ipairs(m.roomStates) do
		if rs.obj.bgAddr > 0x8000 then
			local addr = topc(self.bgBank, rs.obj.bgAddr)
			while true do
				local bg = self:mapAddBG(addr, rom)
				bg.roomStates:insert(rs)
				rs.bgs:insert(bg)
				addr = addr + ffi.sizeof(bg.ctype.name)
				if bg.obj.header == 0 then break end
			end
		end
	end

	for _,rs in ipairs(m.roomStates) do
		if rs.obj.layerHandlingAddr > 0x8000 then
			local addr = topc(self.layerHandlingBank, rs.obj.layerHandlingAddr)
			rs.layerHandlingAddr = self:mapAddLayerHandling(addr)
			rs.layerHandlingAddr.roomStates:insert(rs)
		end
		
		local addr = rs.obj.roomBlockAddr24:topc()
		rs:setRoomBlockData(self:mapAddRoomBlockData(addr, m))
	end

	-- door addrs
	local startaddr = topc(self.doorAddrBank, m.obj.doors)
	local addr = startaddr
	local doorAddr = ffi.cast('uint16_t*', rom + addr)[0]
	addr = addr + 2
	while doorAddr > 0x8000 do
		m.doors:insert(Door{
			sm = self,
			addr = doorAddr,
		})
		doorAddr = ffi.cast('uint16_t*', rom + addr)[0]
		addr = addr + 2
	end
	-- exclude terminator
	addr = addr - 2
	local len = addr - startaddr
	

	-- $079804 - 00/15 - grey torizo room - has 14 bytes here 
	-- pointed to by room[00/15].roomstate_t[#1].roomvarAddr
	-- has data @$986b: 0f 0a 52 00 | 0f 0b 52 00 | 0f 0c 52 00 | 00 00
	-- this is the rescue animals roomstate
	-- so this data has to do with the destructable wall on the right side
	--if roomAddr == 0x79804 then
	for _,rs in ipairs(m.roomStates) do
		if rs.obj.roomvarAddr ~= 0 then
			local d = rom + self.plmBaseAddress + rs.obj.roomvarAddr
			local roomvar = table()
			repeat
				roomvar:insert(d[0])	-- x
				roomvar:insert(d[1])	-- y
				if ffi.cast('uint16_t*', d)[0] == 0 then break end
				roomvar:insert(d[2])	-- mod 1 == 0x52
				roomvar:insert(d[3])	-- mod 2 == 0x00
				-- TODO insert roomvar_t and uint16_t term (or omit term)
				d = d + 4
			until false
			-- TODO should be roomstate
			rs.roomvar = roomvar
		end
	end

	-- try to load tile graphics from rs.tileSet
	-- TODO cache this per tileSet, since there are only 256 possible, and probably much less used?
	for _,rs in ipairs(m.roomStates) do
		local tileSetIndex = rs.obj.tileSet
		local tileSet = assert(self.tileSets[tileSetIndex+1])
		assert(tileSet.index == tileSetIndex)
		rs:setTileSet(tileSet)
	end

	if buildRecursively then
		for _,door in ipairs(m.doors) do
			if door.ctype == 'door_t' then
				door.destRoom = self:mapAddRoom(door.ptr.destRoomAddr, true)
			end
		end
	end

	return m
end

function SMMap:mapRemoveRoom(m)
	if not m then return end
	
	local i = self.rooms:find(m)
	assert(i, "tried to remove a room that I couldn't find")
	
	-- TODO in theory a room state could be pointed to by more than one room (if its roomselect's point to the same one), but in practice this is not true so I don't need to consider it
	for _,rs in ipairs(m.roomStates) do
		rs:setPLMSet(nil)
		-- technically these should never be nil, so only do this if we're getting rid of the roomstate
		rs:setEnemySpawnSet(nil)
		rs:setEnemyGFXSet(nil)
		rs:setRoomBlockData(nil)
	end
	-- TODO do the occluding in mapWrite, and just clear the pointers here?
	for j=#self.bgs,1,-1 do
		local bg = self.bgs[j]
		for _,rs in ipairs(m.roomStates) do
			bg.roomStates:removeObject(rs)
		end
		if #bg.roomStates == 0 then
			self.bgs:remove(j)
		end
	end
	for j=#self.fx1s,1,-1 do
		local fx1 = self.fx1s[j]
		fx1.rooms:removeObject(m)
		if #fx1.rooms == 0 then
			self.fx1s:remove(j)
		end
	end
	
	-- TODO remove all doors targetting this room?
	self.rooms:remove(i)
end

function SMMap:mapFindRoom(region, index)
	for _,m in ipairs(sm.rooms) do
		if m.obj.region == region and m.obj.index == index then return m end
	end
	return false, "couldn't find "..('%02x/%02x'):format(region, index)
end

function SMMap:mapClearDoorColor(region, roomIndex, x,y)
	print('searching for door to remove at '..('%02x/%02x %d,%d'):format(region, roomIndex, x,y))
	local room = assert(self:mapFindRoom(region, roomIndex))
	for _,rs in ipairs(room.roomStates) do
		if rs.plmset then
			for j=#rs.plmset.plms,1,-1 do
				local plm = rs.plmset.plms[j]
				local name = plm:getName()
				if name and name:match'^door_' then
					local dx = plm.x - x
					local dy = plm.y - y
					local l0 = math.abs(dx) + math.abs(dy)
					local linf = math.max(math.abs(dx), math.abs(dy))
					if linf < 8 then
						print('...removing door')
						rs.plmset.plms:remove(j)
					end
				end
			end
		end
	end
end


function SMMap:newPLMSet(args)
	local plmset = PLMSet(args)
	self.plmsets:insert(plmset)
	return plmset
end

-- table of all unique plm regions
-- m is only used for MemoryMap.  you have to add to plmset.rooms externally
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
		-- luajit requires this, ptr[0] isn't good enough 
		--local plm = ffi.new('plm_t', ptr[0])
		local plm = PLM(ptr[0]:toLua())
		plm.ptr = ptr
		plms:insert(plm)
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
			local startaddr = self.plmBaseAddress + plm.args
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
			plm.scrollmod = data
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


--[[
table of all unique bgs.
each entry has .addr and .ptr = (bg_t*)(rom+addr)
doesn't create duplicates -- returns a previous copy if it exists

b9:a634 -> $1ca634
--]]
function SMMap:mapAddBG(addr, rom)
	local _,bg = self.bgs:find(nil, function(bg) return bg.addr == addr end)
	if bg then return bg end
	
	local header = ffi.cast('uint16_t*', rom + addr)[0]
	local ctype = bgCTypeForHeader[header]
	if not ctype then
		error("failed to find ctype for bg_t header "..('%x'):format(header)..' addr '..('%06x'):format(addr))
	end
	local ptr = ffi.cast(ctype.name..'*', rom + addr)

	bg = {
		addr = addr,
		ctype = ctype,
		ptr = ptr,
		-- list of all m's that use this bg
		roomStates = table(),
	}
	bg.obj = ffi.new(ctype.name, bg.ptr[0])
	
	self.bgs:insert(bg)

	if header == 4 then
		local tilesetAddr = ptr.addr24:topc()
print('decoding bg addr '..('%06x'):format(addr)..' tileset '..('%06x'):format(tilesetAddr))
		bg.tilemap = self:mapAddBGTilemap(tilesetAddr)
		bg.tilemap.bg = bg	-- is this 1:1?
	end

	return bg
end


function SMMap:mapAddFX1(addr)
	local _,fx1 = self.fx1s:find(nil, function(fx1) return fx1.addr == addr end)
	if fx1 then return fx1 end
	fx1 = {
		addr = addr,
		ptr = ffi.cast('fx1_t*', self.rom + addr),
		rooms = table(),
	}
	self.fx1s:insert(fx1)
	return fx1
end


local RoomBlocks = class()
SMMap.RoomBlocks = RoomBlocks

function RoomBlocks:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.rooms = table()
	self.roomStates = table()
end

function RoomBlocks:getData()
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

	local tomerge = table{self.head, ch12, ch3}
	tomerge:insert(self.layer2blocks)
	tomerge:insert(self.tail)
	return mergeByteArrays(tomerge:unpack())
end

function RoomBlocks:refreshRooms()
	self.rooms = table()
	for _,rs in ipairs(self.roomStates) do
		self.rooms:insertUnique(assert(rs.room))
	end
end

--[[ for the room tile data:
looks like this is channel 2:
lower nibble channel 2 bits:
bit 0
bit 1 = foreground (not background)
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
RoomBlocks.tileTypes = {
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
-- this is ch2hi:ch3lo
RoomBlocks.extTileTypes = {
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
	spike_solid3_1x1		= 0xa1,	-- used in the hallway to kraid
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
	--powerbomb_1x1_regen	= 0xc8
	powerbomb_1x1			= 0xc9,
	supermissile_1x1_regen	= 0xca,
	supermissile_1x1		= 0xcb,
	beam_door				= 0xcf,
	grappling				= 0xe0,
	grappling_break_regen 	= 0xe1,
	grappling_break			= 0xe2,
	grappling2				= 0xe3,		-- \_ these two alternate in the roof of the room before the wave room
	grappling3				= 0xef,		-- /
	bombable_1x1_regen		= 0xf0,
	bombable_2x1_regen		= 0xf1,
	bombable_1x2_regen		= 0xf2,
	bombable_2x2_regen		= 0xf3,
	bombable_1x1			= 0xf4,
	bombable_2x1			= 0xf5,
	bombable_1x2			= 0xf6,
	bombable_2x2			= 0xf7,
}
RoomBlocks.extTileTypeNameForValue = setmetatable(table.map(RoomBlocks.extTileTypes, function(v,k) return k,v end), nil)

RoomBlocks.oobType = RoomBlocks.tileTypes.solid -- consider the outside to be solid

function RoomBlocks:getTileData(x,y)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = 3 * (x + self.width * y)
	local ch1 = self.blocks[0 + bi]
	local ch2 = self.blocks[1 + bi]
	local ch3 = self.blocks[2 + bi]
	return ch1, ch2, ch3
end

function RoomBlocks:setTileData(x,y,ch1,ch2,ch3)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = 3 * (x + self.width * y)
	self.blocks[0 + bi] = ch1
	self.blocks[1 + bi] = ch2
	self.blocks[2 + bi] = ch3
end


-- for position x,y, returns the real x,y that the tile type is determined by
function RoomBlocks:getCopySource(x,y)
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
function RoomBlocks:isCopy(x,y)
	-- don't use getTileType because this uses the copy_*
	local _, ch2 = self:getTileData(x,y)
	local ch2hi = bit.band(0xf, bit.rshift(ch2, 4))
	return ch2hi == self.tileTypes.copy_left 
		or ch2hi == self.tileTypes.copy_up
end

-- returns true if this is targetted by a 'copy up / left' tile
function RoomBlocks:isCopied(x,y)
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
function RoomBlocks:getAllCopyLocs(x,y)
	local locs = table{x,y}
	local checked = table{x,y}
	while #checked > 0 do
		local ch = checked:remove()
		local _, ch2R = self:getTileData(x+1,y)
error'finish me - but you might have to redo all copies'
	end
end

-- if a block is a copy or is copied then replace it and all copies with its copy source
function RoomBlocks:splitCopies(x,y)
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
considers copies
--]]
function RoomBlocks:getTileType(x,y)
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

function RoomBlocks:getExtTileType(x,y)
	return select(2, self:getTileType(x,y))
end

-- set the 'ett' 
function RoomBlocks:setExtTileType(x,y,ett)
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
function RoomBlocks:isSolid(x,y) 
	return self:getTileType(x,y) == self.tileTypes.solid
end

function RoomBlocks:isAccessible(x,y) 
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
function RoomBlocks:isBorder(x,y, incl, excl)
	incl = incl or self.isSolid
	excl = excl or self.isAccessible
	
	--if x == 0 or y == 0 or x == self.width-1 or y == self.height-1 then return false end
	if incl(self,x,y) then
		for i,offset in ipairs{
			{1,0},
			{-1,0},
			{0,1},
			{0,-1},
		} do
			if excl(self,x+offset[1], y+offset[2]) then 
				return true
			end
		end
	end
	return false
end

function RoomBlocks:isBorderAndNotCopy(x,y)
	return self:isBorder(x,y) 
		and not self:isCopy(x,y) 
		and not self:isCopied(x,y)
end



-- this is the block data of the rooms
function SMMap:mapAddRoomBlockData(addr, m)
	local _,roomBlockData = self.roomblocks:find(nil, function(roomBlockData) 
		return roomBlockData.addr == addr 
	end)
	if roomBlockData then 
		-- rooms can come from separate room_t's
		-- which means they can have separate widths & heights
		-- so here, assert that their width & height matches
		assert(16 * m.obj.width == roomBlockData.width, "expected room width "..roomBlockData.width.." but got "..m.obj.width)
		assert(16 * m.obj.height == roomBlockData.height, "expected room height "..roomBlockData.height.." but got "..m.obj.height)
		return roomBlockData 
	end
	
	local roomaddrstr = ('$%06x'):format(addr)
--print('roomaddr '..roomaddrstr)
	
	-- then we decompress the next 0x10000 bytes ...
--print('decompressing address '..('0x%06x'):format(addr))
	local data, compressedSize = lz.decompress(self.rom, addr, 0x10000)
--print('decompressed from '..compressedSize..' to '..ffi.sizeof(data))
	
	local ofs = 0
	local head = byteArraySubset(data, ofs, 2) ofs=ofs+2
	local w = m.obj.width * blocksPerRoom
	local h = m.obj.height * blocksPerRoom
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
	local dataSize = ffi.sizeof(data)
	if ofs > dataSize then
		error("didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..dataSize)
	end
	local layer2blocks
	local tail
	-- if there's still more to read...
	if ofs < dataSize then
		layer2blocks = byteArraySubset(data, ofs, 2*w*h) ofs=ofs+2*w*h
		if ofs > dataSize then
			error("didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..dataSize)
		end
		-- in all cases that there is some tailing data, there's always enough for uint16_t[width][height]
		-- in 243 of 245 rooms this is all that's there.  in the other 2 rooms there's even more.
		if ofs < dataSize then
			tail = byteArraySubset(data, ofs, dataSize - ofs)
		end	
	end

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
-- look for 0x9x in ch2 of of roomBlockData.blocks
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
				elseif j < h-3	-- TODO assert this
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

	local roomBlockData = RoomBlocks{
		addr = addr,
		-- this is just 16 * room's (width, height)
		width = w,
		height = h,
		-- rule of thumb: do not exceed this
		compressedSize = compressedSize,
		-- decompressed data (in order):
		head = head,	-- first 2 bytes of data
		blocks = blocks,	-- interleaved 2-byte and 1-byte bts into 3-byte room block data
		layer2blocks = layer2blocks,	-- layer2 background if present
		tail = tail,					-- last bytes after blocks 
		-- extra stuff I'm trying to keep track of
		doors = doors,
		blocksForExit = blocksForExit,
	}
	self.roomblocks:insert(roomBlockData)
	return roomBlockData
end


function SMMap:mapAddLayerHandling(addr)
	local _,layerHandling = self.layerHandlings:find(nil, function(layerHandling)
		return layerHandling.addr == addr
	end)
	if layerHandling then return layerHandling end
	local layerHandling = {
		addr = addr,
		code = disasm.readCode(self.rom, addr, 0x100),
		roomStates = table(),
	}
	self.layerHandlings:insert(layerHandling)
	return layerHandling
end

--[[
alright naming
graphicsTile_t = 8x8 rendered block
tilemapElem_t = uint16_t element of the tilemap that references which 8*8 graphics tile to use
	maybe tile table element? etc?
--]]
local tilemapElem_t = struct{
	name = 'tilemapElem_t',
	fields = {
		{graphicsTileIndex = 'uint16_t:10'},	-- graphics tile index
		{colorIndexHi = 'uint16_t:4'},			-- high nibble color index to write throughout the graphics tile
		{xflip = 'uint16_t:1'},					-- whether to 'not'/flip x 
		{yflip = 'uint16_t:1'},					-- whether to 'not'/flip y
	},
}
assert(ffi.sizeof'tilemapElem_t' == 2)

-- index into the graphicsTile buffer shl 1 (to include the nibble address as the lsb)
local graphicsTileOffset_t = struct{
	name = 'graphicsTileOffset_t',
	fields = {
		{x = 'uint16_t:3'},
		{y = 'uint16_t:3'},
		{graphicsTileIndex = 'uint16_t:10'},
	},
}
assert(ffi.sizeof'graphicsTileOffset_t' == 2)

--[[
convert a 2D array of tilemap elements, plus a list of graphics tiles, into a bitmap

dst = destination, in uint8_t[count][tilemapElemSizeY*graphicsTileSizeInPixels][tilemapElemSizeX*graphicsTileSizeInPixels]
tilemapElem = source tilemap element array, tilemapElem_t[count][tilemapElemSizeY][tilemapElemSizeX] ... for each graphicsTile reference
graphicsTiles = source graphicsTile data ... usu 0x4800 or 0x8000 incl common data
tilemapElemSizeX = 8*8 graphicsTiles wide
tilemapElemSizeY = 8*8 graphicsTiles high
count = number of 8 * 8 * tilemapElemSizeX * tilemapElemSizeY tiles ... honestly this coule be multiplied into tilemapElemSizeY

dst should be the destination indexed bitmap
tilemapElem is read from tileSet.tilemapByteVec.v (sets of 2x2), bg.tilemap.data (sets of 32x32), or whatever else
graphicsTiles should be tileSet.graphicsTileVec.v
count should be tileSet.tilemapByteVec.size/8 for tiles (4 corner graphicsTiles x 2 bytes per graphicsTile lookup), or 1 for bg_t's, or whatever else

--]]
function SMMap:convertTilemapToBitmap(
	dst,
	tilemap,
	graphicsTiles,
	tilemapElemSizeX,
	tilemapElemSizeY,
	count
)
	local dst = ffi.cast('uint8_t*', dst)
	graphicsTiles = ffi.cast('uint8_t*', graphicsTiles)
	local dstbase = dst
	local tilemapElem = ffi.cast('uint16_t*', tilemap)
	--local graphicsTileOffset = ffi.new'graphicsTileOffset_t'
	
	for tileIndex=0,count-1 do
		for dstSubtileY=0,tilemapElemSizeY-1 do
			--local col = dst
			for dstSubtileX=0,tilemapElemSizeX-1 do
				local tileInfo = tilemapElem[dstSubtileX + tilemapElemSizeX * dstSubtileY + tilemapElemSizeX * tilemapElemSizeY * tileIndex]
				local xflip = bit.band(tileInfo, 0x4000) ~= 0 and 7 or 0
				local yflip = bit.band(tileInfo, 0x8000) ~= 0 and 7 or 0
				local colorIndexHi = bit.rshift(bit.band(tileInfo, 0x1c00), 6)			-- 1c00h == 0001 1100:0000 0000 b, 1c00h >> 6 == 0000 0000:0111 0000
				for y=0,7 do
					for x=0,7 do
						-- graphicsTileOffset = cccc cccc:ccbb baaa
						-- a = x or ~x depending on xflip
						-- b = y or ~y depending on yflip
						-- c = tilemapElem.graphicsTileIndex
						local graphicsTileOffset = bit.bor(
							bit.bxor(x, xflip),
							bit.lshift(bit.bxor(y, yflip), 3),
							bit.lshift(bit.band(tileInfo, 0x3ff), 6)
						)
						--graphicsTileOffset.x = bit.bxor(x, xflip)
						--graphicsTileOffset.y = bit.bxor(y, xflip)
						--graphicsTileOffset.graphicsTileIndex = tilemapElem.graphicsTileIndex
						-- graphicsTileOffset is a nibble index
						-- so the real byte index into the graphicsTiles is ... 0ccc cccc:cccb bbaa
						-- and that means the graphicsTiles are 32 bytes each ... 8 * 8 * 4bpp / 8 bits/byte = 32 bytes
						-- and that last 0'th bit of a == (x or ~x depending on xflip) determines which nibble to use
						local colorIndexLo = graphicsTiles[bit.rshift(graphicsTileOffset, 1)]
						if bit.band(graphicsTileOffset, 1) ~= 0 then colorIndexLo = bit.rshift(colorIndexLo, 4) end
						colorIndexLo = bit.band(colorIndexLo, 0xf)
						-- so if graphicsTileOffset & 1 == 1 (i.e. if tilemapElem.x & 1 == 1) then we <<= 2
						--colorIndexLo = bit.band(bit.rshift(colorIndexLo, bit.lshift(bit.band(graphicsTileOffset.ptr[0], 1), 2)), 0xf)
						dst[x + 8 * dstSubtileX + 8 * tilemapElemSizeX * (y + 8 * dstSubtileY) + 8 * 8 * tilemapElemSizeX * tilemapElemSizeY * tileIndex] = bit.bor(colorIndexHi, colorIndexLo)
					end
				end
				
				--col = col + graphicsTileSizeInPixels
				--tilemapElem = tilemapElem + 1
			end
			--dst = dst + graphicsTileSizeInPixels * graphicsTileSizeInPixels * tilemapElemSizeX
		end
	end
	-- [[
	-- what is this used for?  
	-- dest paletteIndex bit 1<<7 has both values 0 and 1 ...  
	-- and all palettes are 128 entries so that bit shouldn't be needed
	for i=0,tilemapElemSizeX*tilemapElemSizeY*graphicsTileSizeInPixels*graphicsTileSizeInPixels*count-1 do
		dstbase[i] = bit.band(dstbase[i], 0x7f)
	end
	--]]
end

function SMMap:indexedBitmapToRGB(dstRgbBmp, srcIndexedBmp, imgwidth, imgheight, tileSet)
	for y=0,imgheight-1 do
		for x=0,imgwidth-1 do
			local i = x + imgwidth * y
			local paletteIndex = srcIndexedBmp[i]
			if bit.band(paletteIndex, 0xf) > 0 then	-- is this always true?
				local rgb = tileSet.palette.colors[paletteIndex]
				dstRgbBmp[0 + 3 * i] = math.floor(rgb.r*255/31)
				dstRgbBmp[1 + 3 * i] = math.floor(rgb.g*255/31)
				dstRgbBmp[2 + 3 * i] = math.floor(rgb.b*255/31)
			else
				dstRgbBmp[0 + 3 * i] = 0
				dstRgbBmp[1 + 3 * i] = 0
				dstRgbBmp[2 + 3 * i] = 0
			end
		end
	end
end


-- right now I'm un-interleaving the input data
-- but maybe I should just leave it as is and cast it to this?
local mode7entry_t = struct{
	name = 'mode7entry_t',
	fields = {
		{paletteIndex = 'uint8_t'},
		{mode7tileIndex = 'uint8_t'},
	},
}
assert(ffi.sizeof'mode7entry_t' == 2)


function SMMap:mapAddTileSetPalette(addr)
	for _,palette in ipairs(self.tileSetPalettes) do
		if palette.addr == addr then return palette end
	end

	local palette = {}
	self.tileSetPalettes:insert(palette)
	palette.tileSets = table()
	
	-- what do I call this?  abs-addr (as opposed to 24-bit addrs)?  file-offset?
	palette.addr = addr
	local data, compressedSize = lz.decompress(self.rom, palette.addr, 0x200)
	palette.compressedSize = compressedSize 
	local len = ffi.sizeof(data)
	assert(len % ffi.sizeof'rgb_t' == 0)
	palette.size = len / ffi.sizeof'rgb_t'	-- TODO "count" or "len" to not be ambiguous?
	assert(palette.size == 128)	-- always true
--[[ this seems to free the original data once it leaves scope
	palette.colors = ffi.cast('uint16_t*', data)
--]]
-- [[
	palette.colors = ffi.new('rgb_t[?]', palette.size)
	ffi.copy(palette.colors, data, palette.size * ffi.sizeof'rgb_t')
--]]
	return palette
end

function SMMap:mapAddTileSetGraphicsTileSet(addr)
	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		if graphicsTileSet.addr == addr then return graphicsTileSet end
	end

	local graphicsTileSet = {}
	graphicsTileSet.addr = addr
	graphicsTileSet.tileSets = table()
	self.tileSetGraphicsTileSets:insert(graphicsTileSet)
	
	-- NOTICE this buffer is SEPARATE of tileSet.graphicsTileVec
	-- tileSet.graphicsTileVec starts with this, pads it, appends the commonRoomGraphicsTileVec, 
	-- and even right now does some in-place stuff to it
	-- SO if you modify that, don't forget to update this buffer as well (somehow)
	graphicsTileSet.data, graphicsTileSet.compressedSize = lz.decompress(self.rom, graphicsTileSet.addr, 0x10000)	-- TODO how big?
	graphicsTileSet.size = ffi.sizeof(graphicsTileSet.data)	-- stored for debugging only
	
	return graphicsTileSet
end

-- TODO make this a class and common with mapAddBGTilemap
function SMMap:mapAddTileSetTilemap(addr)
	for _,tilemap in ipairs(self.tileSetTilemaps) do
		if tilemap.addr == addr then return tilemap end
	end
	
	local tilemap = {}
	tilemap.addr = addr
	tilemap.tileSets = table()
	self.tileSetTilemaps:insert(tilemap)
			
	tilemap.data, tilemap.compressedSize = lz.decompress(self.rom, tilemap.addr, 0x10000)
	tilemap.size = ffi.sizeof(tilemap.data)	-- stored for debugging only

	return tilemap
end

local TileSet = class()
function TileSet:init(args)
	local rom = args.sm.rom
	self.index = args.index
	self.addr = tileSetBaseOffset + self.index * ffi.sizeof'tileSet_t'
	self.ptr = ffi.cast('tileSet_t*', rom + self.addr)
	self.obj = ffi.new('tileSet_t', self.ptr[0])

	-- have each room write keys here coinciding blocks
	self.roomStates = table()	-- which roomStates use this tileset
end
function TileSet:setPalette(palette)
	if self.palette then
		self.palette.tileSets:removeObject(self)
	end
	self.palette = palette
	if self.palette then
		self.palette.tileSets:insert(self)
	end
end
function TileSet:setGraphicsTileSet(graphicsTileSet)
	if self.graphicsTileSet then
		self.graphicsTileSet.tileSets:removeObject(self)
	end
	self.graphicsTileSet = graphicsTileSet
	if self.graphicsTileSet then
		self.graphicsTileSet.tileSets:insert(self)
	end
end
function TileSet:setTilemap(tilemap)
	if self.tilemap then
		self.tilemap.tileSets:removeObject(self)
	end
	self.tilemap = tilemap
	if self.tilemap then
		self.tilemap.tileSets:insert(self)
	end
end


function SMMap:mapReadTileSets()
	local rom = self.rom

	do
		local buffer
		buffer, self.commonRoomGraphicsTileCompressedSize = lz.decompress(rom, commonRoomSubtileAddr, 0x10000) --common room elements
		self.commonRoomGraphicsTileVec = vector'uint8_t'
		self.commonRoomGraphicsTileVec:insert(self.commonRoomGraphicsTileVec:iend(), buffer, buffer + ffi.sizeof(buffer))
		-- size is 0x3000
print('self.commonRoomGraphicsTileVec size', ('$%x'):format(self.commonRoomGraphicsTileVec.size))
	end

	do
		local buffer
		buffer, self.commonRoomTilemapCompressedSize = lz.decompress(rom, commonRoomTilemapAddr, 0x10000) --common room elements
		self.commonRoomTilemapByteVec = vector'uint8_t'
		self.commonRoomTilemapByteVec:insert(self.commonRoomTilemapByteVec:iend(), buffer, buffer + ffi.sizeof(buffer))
		-- size is 0x800 ... so 256 8bit tile infos
		-- in my 32-tiles-per-row pics, this is 8 rows
print('self.commonRoomTilemapByteVec size', ('$%x'):format(self.commonRoomTilemapByteVec.size))
	end

	-- load all the tileset address info that is referenced by per-room stuff
	-- do this before any mapAddRoom calls
	for tileSetIndex=0,tileSetCount-1 do
		local tileSet = TileSet{
			index = tileSetIndex,
			sm = self,
		}
		self.tileSets:insert(tileSet)

		tileSet:setPalette(self:mapAddTileSetPalette(tileSet.obj.paletteAddr24:topc()))

		--[[
		region 6 tilesets used:
		room $00: $11 $12
		room $01: $0f $10
		room $02: $0f $10
		room $03: $0f $10
		room $04: $0f $10
		room $05: $13 $14
		... all are only used in region 6
	
		rooms used:
		tileSet index $0f: 06/01, 06/02, 06/03, 06/04
		tileSet index $10: 06/01, 06/02, 06/03, 06/04
		tileSet index $11: 06/00
		tileSet index $12: 06/00
		tileSet index $13: 06/05
		tileSet index $14: 06/05
		
		so there you have it,
		ceres rooms is 1:1 with tileSets 0f-14
		and specifically
			ceres room 6-01 thru 6-04 is 1:1 with tileSets 0f-10
			ceres room 6-00 is 1:1 with tileSets 11-12
			ceres room 6-05 is 1:1 with tileSets 13-14
		--]]
		--local loadCommonRoomElements = rs.room.obj.region ~= 6 and #mode7TileSet == 0
		local isCeres = tileSetIndex >= 0x0f and tileSetIndex <= 0x14		-- all ceres
		local isCeresRidleyRoom = tileSetIndex == 0x13 or tileSetIndex == 0x14
		local loadMode7 = tileSetIndex >= 0x11 and tileSetIndex <= 0x14		-- ceres rooms 6-00 and 6-05
		local loadCommonRoomElements = not isCeres
			

		tileSet:setGraphicsTileSet(self:mapAddTileSetGraphicsTileSet(tileSet.obj.graphicsTileAddr24:topc()))


		--[[
		key by address, keep track of decompressed data, so that we don't have to re-decompress them
		and so I can keep track of tilesets used per decompressed region (so I can remove unused ones)

		EXCEPT for ceres space station (tileSet 0f-14)
		 all tileSet_t tileAddr24's match with graphicsTileAddr24's
		for tileSets 0f-14 we find that 0f & 10, 11 & 12, and 13 & 14 have graphicsTileAddr24 matching each other but separate of the rest of 0f-14
		... and of those, rooms 11-12 are all black, and 13-14 are garbage

		which means that for the rest, which do use common tilesets, i can save this
		--]]


		--[[
		tileSet_t has 3 pointers in it: palette, tile, and graphicsTile
		paletteAddr24 is independent of roomstate_t
		but the other two are not, so, load them with the roomstate_t

		here in the roomstate_t, load the tile data that coincides with the 
		TODO instead of determining by roomstate info, determine by which tileSet_t it is
		that way we don't get so many multiples of the same tileSet_t's

		funny thing, these only seem to be writing for ceres space station anyways
		so I wonder if that mode7 tileSetIndex if condition is even needed
		--]]
		local graphicsTileVec = vector'uint8_t'
		graphicsTileVec:insert(graphicsTileVec:iend(), tileSet.graphicsTileSet.data, tileSet.graphicsTileSet.data + tileSet.graphicsTileSet.size)

		-- for tileSet 0x11-0x14
		-- tileSet 0x11, 0x12 = room 06/00
		-- tileSet 0x13, 0x14 = room 06/05
		-- for these rooms, the tileSet.tilemap.addr points to the mode7 data
		if loadMode7 then
			print('mode7 graphicsTileVec.size '..('%x'):format(graphicsTileVec.size))			
			-- uint8_t mode7tileSet[256][8][8], values are 0-255 palette index
			tileSet.mode7TileSet = ffi.new('uint8_t[?]', graphicsTileSizeInPixels * graphicsTileSizeInPixels * numMode7Tiles)
			for mode7tileIndex=0,numMode7Tiles-1 do
				for x=0,graphicsTileSizeInPixels-1 do
					for y=0,graphicsTileSizeInPixels-1 do
						tileSet.mode7TileSet[x + graphicsTileSizeInPixels * (y + graphicsTileSizeInPixels * mode7tileIndex)] 
							= graphicsTileVec.v[1 + 2 * (x + graphicsTileSizeInPixels * (y + graphicsTileSizeInPixels * mode7tileIndex))]
					end
				end
			end

			-- who uses this?
			-- just a few rooms in Ceres space station -- the rotating room, and the rotating image of Ridley flying away
			-- uint8_t mode7tiles[128][128], values are 0-255 lookup of the mode7tileSet
			tileSet.mode7tiles = ffi.new('uint8_t[?]', mode7sizeInGraphicTiles * mode7sizeInGraphicTiles)
			for i=0,mode7sizeInGraphicTiles-1 do
				for j=0,mode7sizeInGraphicTiles-1 do
					tileSet.mode7tiles[i + mode7sizeInGraphicTiles * j] 
						= graphicsTileVec.v[0 + 2 * (i + mode7sizeInGraphicTiles * j)]
				end
			end
			
			--[[ vanilla ceres ridley room layer handling, when layerHandlingAddr == $c97b
			used with roomstate_t's $07dd95, $07dd7b
			which are only for room_t $07dd69 06/05 -- and they are the only roomstates_t's of that room, so I can check via room
			roomstate_t $07dd95 => tileSet $14 ... used by no one else
			roomstate_t $07dd7b => tileSet $13 ... used by no one else
			so we can instead test by tileSetIndex here
			
			room 06/05's block tileIndex data is all value $1f anyways,
			so regardless of fixing this tileset, we still have nothing to display.
			--]]
			--if rs.layerHandlingAddr == 0xc97b then
			graphicsTileVec:resize(0x5000)
			ffi.fill(graphicsTileVec.v, graphicsTileVec.size, 0)
			if isCeresRidleyRoom then
				ffi.copy(graphicsTileVec.v, rom + 0x182000, 0x2000)
				-- TODO mem:add for this ... once I get these Ceres rooms to even show up, to verify this is even right			
			end
		else
			--get graphicsTiles
			-- also notice that the tileSets used for mode7 are not used for this (unless 06/05 happens to also be)
			--[[
			dansSuperMetroidLibrary has this resize, for tileSets other than $26 
			... which is interseting because it means that, for tileSet $11 and $12 (only used in Ceres) we are sizing down from 0x8000 to 0x5000
			otherwise, for tileSets $0-$10, $13-$19, $1b, $1c  this is resized up from 0x4800 to 0x5000
			so ... should $11 and $12 be resized down?
			--]]
			-- all (except for $11-$14 above) tileSets are 0x4800 in size, except Kraid's room that alone uses tileSet $0a, which is 0x8000 in size
			-- so the rest have to be sized up the extra 0x200 bytes ... how many 16x16 blocks is that?
			--[[
			TODO if this does go here then there should be an equivalent resizing of the tilemapByteVec
			... however I'm not seeing it
			... and as a result of the mismatch, you see the commonRoomElements get lost
			but on the flip side, with the mismatch and garbled tileset texture,
			the room does decode correctly
			--]]	
			if graphicsTileVec.size < 0x5000 then
				graphicsTileVec:resize(0x5000)
			end
		end
		if loadCommonRoomElements then-- this is going after the graphicsTile 0x5000 / 0x8000
			graphicsTileVec:insert(graphicsTileVec:iend(), self.commonRoomGraphicsTileVec:begin(), self.commonRoomGraphicsTileVec:iend())
		end
		
		-- rearrange the graphicsTiles ... but why?  why not keep them in their original order? and render the graphicsTiles + tilemap => bitmap using the original format?
		local copy = ffi.new('uint8_t[?]', graphicsTileSizeInBytes)
		local line = ffi.new('uint8_t[?]', 4)
		local uint32 = ffi.new('uint32_t[1]', 0)
		local uint8 = ffi.cast('uint8_t*', uint32)
		for i=0,graphicsTileVec.size-1,graphicsTileSizeInBytes do
			ffi.copy(copy, graphicsTileVec.v + i, graphicsTileSizeInBytes)
			-- in place convert, row by row ... why are we converting ?
			ffi.fill(graphicsTileVec.v + i, graphicsTileSizeInBytes, 0)
			for y=0,7 do
				ffi.cast('uint16_t*', line)[0] = ffi.cast('uint16_t*', copy + 2*y)[0]
				ffi.cast('uint16_t*', line)[1] = ffi.cast('uint16_t*', copy + 2*y)[8]
				for x=0,7 do
					local shift = bit.lshift(7 - x, 2)
					uint32[0] = 0
					for j=0,3 do
						uint32[0] = bit.bor(
							uint32[0],
							bit.lshift(
								bit.band(bit.rshift(line[j], x), 1),
								bit.bor(shift, j)
							)
						)
					end
					for j=0,3 do
						graphicsTileVec.v[j + 4*y + i] = bit.bor(
							graphicsTileVec.v[j + 4*y + i],
							uint8[j]
						)
					end
				end
			end
		end

		tileSet:setTilemap(self:mapAddTileSetTilemap(tileSet.obj.tileAddr24:topc()))

		local tilemapByteVec = vector'uint8_t'
		if loadCommonRoomElements then
			tilemapByteVec:insert(tilemapByteVec:iend(), self.commonRoomTilemapByteVec:begin(), self.commonRoomTilemapByteVec:iend())
		end
		tilemapByteVec:insert(tilemapByteVec:iend(), tileSet.tilemap.data, tileSet.tilemap.data + tileSet.tilemap.size)
		
		-- 0x2000 size means 32*32*16*16 pixel sprites, so 8 bytes per 16x16 tile
		print('tilemapByteVec.size', ('$%x'):format(tilemapByteVec.size))
		tileSet.tileGfxCount = bit.rshift(tilemapByteVec.size, 3)
		-- store as 16 x 16 x index rgb
		tileSet.tileGfxBmp = ffi.new('uint8_t[?]', blockSizeInPixels * blockSizeInPixels * tileSet.tileGfxCount)

		self:convertTilemapToBitmap(
			tileSet.tileGfxBmp,
			tilemapByteVec.v,		-- tilemapElem_t[tileGfxCount][2][2]
			graphicsTileVec.v,		-- each 32 bytes is a distinct 8x8 graphics tile, each pixel is a nibble
			2,
			2,
			tileSet.tileGfxCount)	

		-- bg_t's need this
		-- ... will they need this, or just the non-common portion of it?
		tileSet.graphicsTileVec = graphicsTileVec

		-- TODO here - map from the graphicsTile address (should be 32-byte-aligned) to the tileIndex
		-- this way, if a background uses a graphicsTile, then we can flag all tileIndexes that are also used
		-- (it will have to map to multiple tileIndexes)
		-- used for tileIndex removal/optimization
	end
end


function SMMap:mapInit()
	local rom = self.rom

	-- check where the PLM bank is
	-- TODO this will affect the items.lua addresses
	-- default is 0x8f
	self.plmBank = rom[0x204ac]

	self.rooms = table()
	self.roomblocks = table()
	self.bgs = table()
	self.bgTilemaps = table()
	self.fx1s = table()
	self.layerHandlings = table()
	
	self.plmsets = table()
	self.enemySpawnSets = table()
	self.enemyGFXSets = table()

	self.tileSets = table()
	self.tileSetPalettes = table()
	self.tileSetGraphicsTileSets = table()
	self.tileSetTilemaps = table()

	self:mapReadTileSets()

	--[[
	from $078000 to $079193 is plm_t data
	the first room_t is at $0791f8
	from there it is a dense structure of ...
	room_t
	roomselect's (in reverse order)
	roomstate_t's (in forward order)
	dooraddrs
	... then comes extra stuff, sometimes:
	scrolldata (which is in one place wedged into nowhere)
	plm scrollmod

	TODO don't check *every* byte from 0x8000 to 0xffff
	instead start with one room_t - wherever you start: $079202 
	- from room's, read all roomstates, and read all their rooms, and read all their door rooms
	--]]
	--[[ method #1: scan every possible byte from $078000 to $079193
	for pageofs=0x8000,0xffff do
		local ptr = rom + topc(self.roomBank, pageofs)
		local mptr = ffi.cast('room_t*', ptr)
		if (
			(ptr[12] == 0xE5 or ptr[12] == 0xE6) 
			and mptr.region < 8 
			and (mptr.width ~= 0 and mptr.width < 20) 
			and (mptr.height ~= 0 and mptr.height < 20)
			and mptr.gfxFlags < 0x10 
			and mptr.doors > 0x7F00
		) then
			self:mapAddRoom(pageofs, false)
		end
	end
	-- link all doors to their rooms
	for _,m in ipairs(self.rooms) do
		for _,door in ipairs(m.doors) do
			if door.ctype == 'door_t' then
				local destRoom = assert(
					select(2, self.rooms:find(nil, function(m) 
						return m.addr == door.ptr.destRoomAddr 
					end)), 
					'!!!! door '..('%06x'):format(ffi.cast('uint8_t*',door.ptr)-rom)..' points nowhere')
				-- points to the dest room
				door.destRoom = destRoom
			end
		end
	end
	--]]
	-- [[ method #2: recursively construct, starting at room 00/00 at $0791f8
	assert(self:mapAddRoom(0x91f8, true))	-- Zebes
	assert(self:mapAddRoom(0xdf45, true))	-- Ceres
	--]]

--[[ these are not first bg tilemaps of rooms..  where are they stored? 
-- some are garbage
	self:mapAddBGTilemap(topc(0xb9, 0xa75e))
	self:mapAddBGTilemap(topc(0xb9, 0xd56a))
	self:mapAddBGTilemap(topc(0xb9, 0xd5a1))
	self:mapAddBGTilemap(topc(0xb9, 0xd99c))
	self:mapAddBGTilemap(topc(0xb9, 0xde11))
	self:mapAddBGTilemap(topc(0xb9, 0xe94f))
	self:mapAddBGTilemap(topc(0xb9, 0xf11d))
	self:mapAddBGTilemap(topc(0xb9, 0xf70d))
	self:mapAddBGTilemap(topc(0xb9, 0xf72e))
	self:mapAddBGTilemap(topc(0xb9, 0xff4e))
	self:mapAddBGTilemap(topc(0xba, 0x9023))
	self:mapAddBGTilemap(topc(0xba, 0xc620))
--]]


	--[[ get a table of doors based on their plm arg low byte
	self.doorPLMForID = table()
	for _,plmset in ipairs(self.plmsets) do
		for _,plm in ipairs(plmset.plms) do
			local name = plm:getName()
			if name and name:match'^door_' then
				local id = bit.band(plm.args, 0xff)
				assert(not self.doorPLMForID[id])
				self.doorPLMForID[id] = plm
			end	
		end
	end
	--]]

	-- [[ -------------------------------- ASSERT STRUCT ---------------------------------
	-- asserting underlying contiguousness of structure of the room_t's...
	-- verify that after each room_t, the roomselect / roomstate_t / dooraddrs are packed together

	-- before the first room_t is 174 plm_t's, 
	-- then 100 bytes of something
	assert(self.rooms)
	for j,m in ipairs(self.rooms) do
		local d = ffi.cast('uint8_t*',m.ptr)
		local roomaddr = d - rom
		d = d + ffi.sizeof'room_t'
		-- last roomselect should always be 2 byte term
		--assert(m.roomStates:last().select_ctype == 'roomselect1_t')
		-- if there's only 1 roomState then it is a term, and
		for i=1,#m.roomStates do
			assert(d == ffi.cast('uint8_t*', m.roomStates[i].select_ptr))
			d = d + ffi.sizeof(m.roomStates[i].select_ctype)
		end
		-- next should always match the last room
		for i=#m.roomStates,1,-1 do
			assert(d == ffi.cast('uint8_t*', m.roomStates[i].ptr))
			d = d + ffi.sizeof'roomstate_t'
		end
		-- for a single room there is an extra 26 bytes of padding between the roomstate_t's and the dooraddrs
		-- and that room is $07ad1b, the speed booster room
		-- the memory map at http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
		-- says it is just part of the speed booster room
		-- the memory map at http://patrickjohnston.org/bank/8F
		-- doesn't say it is anything
		if roomaddr == 0x07ad1b then
--[[ if you want to keep it ...
			local data = ffi.new('uint8_t[?]', 26)
			ffi.copy(data, d, 26)
			m.speedBoosterRoomExtraData = data
print('speed booster room extra trailing data at '..('$%06x'):format(d - rom)..': '..byteArrayToHexStr(data))
--]]			
			d = d + 26
		end
		local dooraddr = topc(self.doorAddrBank, m.obj.doors)
		assert(d == rom + dooraddr)
		d = d + 2 * #m.doors
		
		-- now expect all scrolldatas of all rooms of this room_t
		-- the # of unique scrolldatas is either 0 or 1
		local scrolls = m.roomStates:map(function(rs)
			return true, rs.obj.scrollAddr
		end):keys():filter(function(scroll)
			return scroll > 1 and scroll ~= 0x8000
		end):sort()
		assert(#scrolls <= 1)
		-- room_t $07adad -- room before wave room -- has its scrolldata overlap with the dooraddr
		-- so... shouldn't this assertion fail?
		for _,scroll in ipairs(scrolls) do
			local addr = topc(self.scrollBank, scroll)
			assert(d == rom + addr)
			d = d + m.obj.width * m.obj.height
		end
	end


	--]] --------------------------------------------------------------------------------

	-- TODO switch to graphicsTile indexes used, per 8x8 block
	-- collect all unique indexes of each roomblockdata	
	for _,roomBlockData in ipairs(self.roomblocks) do
		roomBlockData.tileIndexesUsed = roomBlockData.tileIndexesUsed or {}
		local blocks = roomBlockData.blocks
		local w = roomBlockData.width / blocksPerRoom
		local h = roomBlockData.height / blocksPerRoom
		for j=0,h-1 do
			for i=0,w-1 do
				for ti=0,blocksPerRoom-1 do
					for tj=0,blocksPerRoom-1 do
						local dx = ti + blocksPerRoom * i
						local dy = tj + blocksPerRoom * j
						local di = dx + blocksPerRoom * w * dy
						-- blocks is 0-based
						local d1 = blocks[0 + 3 * di]
						local d2 = blocks[1 + 3 * di]
						local d3 = blocks[2 + 3 * di]	
						local tileIndex = bit.bor(d1, bit.lshift(bit.band(d2, 0x03), 8))
						roomBlockData.tileIndexesUsed[tonumber(tileIndex)] = true
						-- TODO convert tileIndexes into its 4 graphicsTile indexes and mark those
					end
				end
			end
		end
	end

	-- now do the same for tilesets 
	for _,tileSet in ipairs(self.tileSets) do
		tileSet.tileIndexesUsed = {}
	end
	for _,m in ipairs(self.rooms) do
		for _,rs in ipairs(m.roomStates) do
			for tileIndex,_ in pairs(rs.roomBlockData.tileIndexesUsed) do
				rs.tileSet.tileIndexesUsed[tileIndex] = true
			end
		end
	end

	--[[
	ok here
	we can compress away the tile indexes
	skip the common tile elements, so only optimize indexes 0x100 thru 0x3ff
	bit 0x400 is used for flipping the tile horz
	bit 0x800 is used for flipping the tile vert
	mind you, bit 0x200 set is for foreground
	that means that only values 0x100-0x1ff (256) are background tiles?
	and the rest of 0x200-0x3ff (512) are foreground
	
	--]]


	-- load stations
	-- http://patrickjohnston.org/bank/82
	self.loadStations = table()
	local ptr = rom + topc(0x80, 0xc4c5)
	local loadStationCountr = 151
	for i=0,loadStationCountr-1 do
		local ls = {}
		ls.ptr = ffi.cast('loadStation_t*', ptr)
		ls.obj = ffi.new('loadStation_t', ls.ptr[0])

		if ls.ptr.roomAddr ~= 0 
		and ls.ptr.roomAddr ~= 0xe82c	-- debug rooms.  I think with the sweep based method, I miss out on section 7.  tehn again, mabye this isn't seciton 7
		then
			ls.room = assert(select(2, self.rooms:find(nil, function(room)
				return room:getAddr(self) == ls.ptr.roomAddr
			end)), "failed to find the room for addr "..('%04x'):format(ls.ptr.roomAddr))
		end
		-- TODO similar pointer for door_t? though I don't move doors yet.
		
--print('loadStation_t'..ls.obj..' '..(ls.room and ('room_t'..ls.room.obj) or ''))
		self.loadStations[i+1] = ls
		ptr = ptr + ffi.sizeof'loadStation_t'
	end
end



local debugImageBlockSizeInPixels = 4
local debugImageRoomSizeInPixels = blocksPerRoom * debugImageBlockSizeInPixels

local debugImageColorMap = range(254)
--debugImageColorMap = shuffle(debugImageColorMap)
debugImageColorMap[0] = 0
debugImageColorMap[255] = 255
-- data is sized 32*m.width x 16*m.width
local ofsPerRegion = {
	function(m) 
		-- special case for Crateria right of Wrecked Ship
		if m.region == 0	-- Crateria
		and m.x > 45 
		then
			return 6,1
		end
		return -1,1
	end,	-- crateria
	function(m) return -4,19 end,	-- brinstar
	function(m) return 27,39 end,	-- norfair
	function(m) return 33,-9 end,	-- wrecked ship
	function(m) return 24,19 end,	-- maridia
	function(m) return -4,1 end,	-- tourian
	function(m) return -9,26 end,	-- ceres
	function(m) return 3,48 end,	-- testing
}


-- it'd be really nice to draw the room region/index next to the room ...
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

local function drawstr(img, posx, posy, s)
	for i=1,#s do
		local ch = digits[s:sub(i,i)]
		if ch then
			for pj=0,4 do
				for pi=0,2 do
					local c = ch[pj+1]:byte(pi+1) == (' '):byte() and 0 or 255
					if c ~= 0 then	
						local x = posx + pi + (i-1)*4
						local y = posy + pj
					
						if x >= 0 and x < img.width
						and y >= 0 and y < img.height 
						then
							img.buffer[0+3*(x+img.width*y)] = c
							img.buffer[1+3*(x+img.width*y)] = c
							img.buffer[2+3*(x+img.width*y)] = c
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
	{0, 0x00, 0, 0, 1, 2},	-- crateria intro, out of bounds backgrounds
	{0, 0x00, 0, 3, 1, 1},	-- "
	{0, 0x12, 2, 8, 1, 1},	-- crateria down hall to mother brain overlapping mother brain 1st room
	{1, 0x08, 0, 1, 4, 5},	-- brinstar pink speed fall room
	{1, 0x09, 0, 0, 1, 1},	-- brinstar pink big room
	{1, 0x09, 0, 1, 2, 2},	-- "
	{1, 0x0e, 0, 0, 5, 2},	-- brinstar blue first room
	{1, 0x13, 2, 0, 3, 1},	-- brinstar bottom flea room
	{1, 0x24, 1, 4, 1, 1},	-- red room ascending to lift to brinstar, blocks save to the right
	{1, 0x2c, 0, 1, 1, 1},	-- brinstar kraid fly room
	{2, 0x04, 0, 0, 3, 3},	-- norfair speed room to ice
	{2, 0x04, 4, 3, 3, 1},	-- "
	{2, 0x07, 1, 0, 1, 1},	-- norfair room before ice
	{2, 0x07, 1, 2, 1, 1},	-- "
	{2, 0x14, 5, 0, 3, 2},	-- norfair room before grappling
	{2, 0x21, 0, 0, 2, 2},	-- norfair lava rise room run to wave
	{2, 0x25, 3, 2, 1, 1},	-- norfair entrance to lower norfair lava swim, lower right corner occuldes room 2-3c, even though there are gfx tiles here
	{2, 0x35, 2, 0, 1, 1},	-- chozo morph to lower acid room, upper right overlaps with room to the right
--	{2, 0x36, 5, 0, 3, 2},	-- norfair lower first room ... i guess this would overlap with the norfair entrance to lower norfair, but i'm not seeing it now ...
	{2, 0x3e, 0, 0, 2, 3},	-- norfair lower return from gold chozo loop
	{2, 0x45, 1, 0, 2, 4},	-- norfair room after acid raise run room, upper right blocks room to the right
	{2, 0x48, 0, 0, 1, 2},	-- norfair lower escape last room
	{2, 0x4b, 0, 1, 1, 5},	-- norfair lower escape first room
	{3, 0x00, 0, 0, 2, 1},	-- wrecked ship bowling chozo room
	{3, 0x00, 0, 2, 1, 1},	-- "
	{3, 0x04, 0, 0, 4, 5},	-- wrecked ship main shaft
	{3, 0x04, 5, 0, 1, 6},	-- "
	{4, 0x03, 1, 1, 3, 1},	-- maridia fly and yellow blob room at the bottom
	{4, 0x04, 2, 7, 1, 1},	-- maridia big climb upper left room, block over its door right to crabs 
	{4, 0x31, 1, 0, 4, 2},	-- maridia mocktroid and big shell guy area
}

local dumpworldTileTypes = {
	empty = 0,
	solid = 1,
	slope45_ul_diag45 = 2,
	slope45_ur_diag45 = 3,
	slope45_dl_diag45 = 4, 
	slope45_dr_diag45 = 5,
	slope27_ul2_diag27 = 6, 
	slope27_ul1_diag27 = 7,
	slope27_ur2_diag27 = 8, 
	slope27_ur1_diag27 = 9, 
	slope27_dl2_diag27 = 10, 
	slope27_dl1_diag27 = 11,
	slope27_dr2_diag27 = 12, 
	slope27_dr1_diag27 = 13, 
	water = 14,
	ladder = 15,
	blasterbreak = 16,
	plasmabreak = 17,
	skillsawbreak = 18,
	missilebreak = 19,
	grenadebreak = 20,
	speedbreak = 21,
	spikes = 22,
	blasterbreak_regen = 23,
	plasmabreak_regen = 24,
	skillsawbreak_regen = 25,
	missilebreak_regen = 26,
	grenadebreak_regen = 27,
	speedbreak_regen = 28,
	fallbreak = 29,
	fallbreak_regen = 30,
}

local function drawRoomBlocks(ctx, roomBlockData, rs)
	local m = rs.room
	local debugMapImage = ctx.debugMapImage
	local debugMapMaskImage = ctx.debugMapMaskImage
	local blocks = roomBlockData.blocks
	local w = roomBlockData.width / blocksPerRoom
	local h = roomBlockData.height / blocksPerRoom
	local ofscalc = assert(ofsPerRegion[m.obj.region+1], "couldn't get offset calc func for room:\nptr "..m.ptr[0].."\nobj "..m.obj)
	local ofsInRoomBlocksX, ofsInRoomBlocksY = ofscalc(m.ptr)
	local firstcoord
						
	local tileSet = rs.tileSet
	-- TODO first bg with a tileset ... but for now there's only 1 anyways
	local _, bg = rs.bgs:find(nil, function(bg) return bg.tilemap end)
	local bgTilemap = bg and bg.tilemap
	local bgBmp = bgTilemap and ctx.sm.getBitmapForTileSetAndTileMap(tileSet, bgTilemap)
	
	for j=0,h-1 do
		for i=0,w-1 do
			local ignore
			for _,info in ipairs(mapDrawExcludeMapBlocks) do
				local region, index, mx, my, mw, mh = table.unpack(info)
				if region == m.obj.region
				and index == m.obj.index
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
						-- blocks is 0-based
						local d1 = blocks[0 + 3 * di]
						local d2 = blocks[1 + 3 * di]
						local d3 = blocks[2 + 3 * di]
				
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
							for pj=0,debugImageBlockSizeInPixels-1 do
								local y = pj + debugImageBlockSizeInPixels * (tj + blocksPerRoom * (m.obj.y + j + ofsInRoomBlocksY))
								for pi=0,debugImageBlockSizeInPixels-1 do
									local x = pi + debugImageBlockSizeInPixels * (ti + blocksPerRoom * (m.obj.x + i + ofsInRoomBlocksX))
									if x >= 0 and x < debugMapImage.width
									and y >= 0 and y < debugMapImage.height 
									then
										if not firstcoord then
											firstcoord = {x,y}
										end
										
										debugMapImage.buffer[0+3*(x+debugMapImage.width*y)] = debugImageColorMap[tonumber(d1)]
										debugMapImage.buffer[1+3*(x+debugMapImage.width*y)] = debugImageColorMap[tonumber(d2)]
										debugMapImage.buffer[2+3*(x+debugMapImage.width*y)] = debugImageColorMap[tonumber(d3)]
									end
								end
							end
						end
						
						if tileSet then				
							
							-- TODO seems omitting tileIndexes >= tileGfxCount and just using modulo tileGfxCount makes no difference
							--and tileIndex < tileSet.tileGfxCount
-- [[ draw background?
							if bgBmp then
								for pj=0,blockSizeInPixels-1 do
									local y = pj + blockSizeInPixels * (tj + blocksPerRoom * (m.obj.y + j + ofsInRoomBlocksY))
									for pi=0,blockSizeInPixels-1 do
										local x = pi + blockSizeInPixels * (ti + blocksPerRoom * (m.obj.x + i + ofsInRoomBlocksX))
										if x >= 0 and x < ctx.mapTexImage.width
										and y >= 0 and y < ctx.mapTexImage.height 
										then
											local bgw = graphicsTileSizeInPixels * bgTilemap.width
											local bgh = graphicsTileSizeInPixels * bgTilemap.height
											local bgx = x % bgw
											local bgy = y % bgh
											local paletteIndex = bgBmp.dataBmp[bgx + bgw * bgy]
											if bit.band(paletteIndex, 0xf) > 0 then
												local src = tileSet.palette.colors[paletteIndex]
												local dstIndex = x + ctx.mapTexImage.width * y
												local dst = ctx.mapTexImage.buffer + 3 * dstIndex
												dst[0] = math.floor(src.r*255/31)
												dst[1] = math.floor(src.g*255/31)
												dst[2] = math.floor(src.b*255/31)
											end
										end
									end
								end
							end
--]]
-- [[ layer 2 tilemap
							if roomBlockData.layer2blocks then
								local tileIndex = ffi.cast('uint16_t*', roomBlockData.layer2blocks)[ti + blocksPerRoom * i + blocksPerRoom * w * (tj + blocksPerRoom * j)]
								local pimask = bit.band(tileIndex, 0x400) ~= 0 and 15 or 0
								local pjmask = bit.band(tileIndex, 0x800) ~= 0 and 15 or 0
								tileIndex = bit.band(tileIndex, 0x3ff)
								
								for pj=0,blockSizeInPixels-1 do
									for pi=0,blockSizeInPixels-1 do
										local x = pi + blockSizeInPixels * (ti + blocksPerRoom * (m.obj.x + i + ofsInRoomBlocksX))
										local y = pj + blockSizeInPixels * (tj + blocksPerRoom * (m.obj.y + j + ofsInRoomBlocksY))
										if x >= 0 and x < ctx.mapTexImage.width
										and y >= 0 and y < ctx.mapTexImage.height 
										then
											-- for loop here
											--local dst = img.buffer + 3 * (pi + blockSizeInPixels * x + pixw * (pj + blockSizeInPixels * y))
											local spi = bit.bxor(pi, pimask)
											local spj = bit.bxor(pj, pjmask)
											local srcIndex = spi + blockSizeInPixels * (spj + blockSizeInPixels * tileIndex)
											local paletteIndex = tileSet.tileGfxBmp[srcIndex]
											if bit.band(paletteIndex, 0xf) > 0 then
												local src = tileSet.palette.colors[paletteIndex]
												local dstIndex = x + ctx.mapTexImage.width * y
												local dst = ctx.mapTexImage.buffer + 3 * dstIndex
												dst[0] = math.floor(src.r*255/31)
												dst[1] = math.floor(src.g*255/31)
												dst[2] = math.floor(src.b*255/31)
											end
										end
									end
								end
							end
--]]
							do
								local tileIndex = bit.bor(d1, bit.lshift(bit.band(d2, 0x03), 8))
								local pimask = bit.band(d2, 4) ~= 0 and 15 or 0
								local pjmask = bit.band(d2, 8) ~= 0 and 15 or 0
								
								for pj=0,blockSizeInPixels-1 do
									local y = pj + blockSizeInPixels * (tj + blocksPerRoom * (m.obj.y + j + ofsInRoomBlocksY))
									for pi=0,blockSizeInPixels-1 do
										local x = pi + blockSizeInPixels * (ti + blocksPerRoom * (m.obj.x + i + ofsInRoomBlocksX))
										if x >= 0 and x < ctx.mapTexImage.width
										and y >= 0 and y < ctx.mapTexImage.height 
										then
											local spi = bit.bxor(pi, pimask)
											local spj = bit.bxor(pj, pjmask)
											local srcIndex = spi + blockSizeInPixels * (spj + blockSizeInPixels * tileIndex)
											local paletteIndex = tileSet.tileGfxBmp[srcIndex]
											-- now which determines transparency?
											if bit.band(paletteIndex, 0xf) > 0 then	-- why does lo==0 coincide with a blank tile? doesn't that mean colors 0, 16, 32, etc are always black?
												local src = tileSet.palette.colors[paletteIndex]
												local dstIndex = x + ctx.mapTexImage.width * y
												local dst = ctx.mapTexImage.buffer + 3 * dstIndex
												dst[0] = math.floor(src.r*255/31)
												dst[1] = math.floor(src.g*255/31)
												dst[2] = math.floor(src.b*255/31)
											end
										end
									end
								end
							end
--[[ want to see what tileIndex each block is?
							drawstr(ctx.mapTexImage,
								2 + blockSizeInPixels * (ti + blocksPerRoom * (m.obj.x + i + ofsInRoomBlocksX)),
								8 + blockSizeInPixels * (tj + blocksPerRoom * (m.obj.y + j + ofsInRoomBlocksY)),
								('%02x'):format(tileIndex))
--]]						
						end

						-- TODO isSolid will overlap between a few rooms
						local isBorder = roomBlockData:isBorderAndNotCopy(dx,dy)
						do --if isBorder or isSolid then
							local isSolid = roomBlockData:isSolid(dx,dy)
							
							do
								local x = ti + blocksPerRoom * (m.obj.x + i + ofsInRoomBlocksY)
								local y = tj + blocksPerRoom * (m.obj.y + j + ofsInRoomBlocksX)
								if x >= 0 and x < ctx.dumpworldTileImg.width
								and y >= 0 and y < ctx.dumpworldTileImg.height 
								then
									local dstIndex = x + ctx.dumpworldTileImg.width * y
								

-- [==[
										local foreground = bit.band(d2, 2) == 2
										-- TODO determine foreground vs background info here
										local sx, sy = dx,dy
										if roomBlockData:isCopy(dx,dy) then
											sx, sy = roomBlockData:getCopySource(dx,dy)
										end
										-- this function will do getCopySource if you want
										local tt, ett = roomBlockData:getTileType(sx,sy)
										local copych1, copych2, copych3 = roomBlockData:getTileData(sx,sy)
										local dtt = dumpworldTileTypes.empty
-- [====[
										if tt == RoomBlocks.tileTypes.empty then
											dtt = dumpworldTileTypes.empty
										elseif tt == RoomBlocks.tileTypes.slope then
											--[[ TODO pick the right one
											-- also note, SM has 1:3 slopes as well, I only have 1:1 and 1:2
											-- I could just do half blocks in all 4 directions to turn 1:3 into 1:2's
											slope45_ul_diag45 = 2,
											slope45_ur_diag45 = 3,
											slope45_dl_diag45 = 4, 
											slope45_dr_diag45 = 5,
											slope27_ul2_diag27 = 6, 
											slope27_ul1_diag27 = 7,
											slope27_ur2_diag27 = 8, 
											slope27_ur1_diag27 = 9, 
											slope27_dl2_diag27 = 10, 
											slope27_dl1_diag27 = 11,
											slope27_dr2_diag27 = 12, 
											slope27_dr1_diag27 = 13, 
											--]]
											dtt = dumpworldTileTypes.slope45_ul_diag45
										elseif tt == RoomBlocks.tileTypes.spikes then
											--[[ TODO
											spike_solid_1x1			= 0x20,
											spike_notsolid_1x1		= 0x22,
											--]]
											dtt = dumpworldTileTypes.spikes
										elseif tt == RoomBlocks.tileTypes.push then
											--[[ TODO
											push_quicksand1			= 0x30,
											push_quicksand2			= 0x31,
											push_quicksand3			= 0x32,
											push_quicksand4			= 0x33,
											push_quicksand1_2		= 0x35,
											push_conveyor_right		= 0x38,
											push_conveyor_left		= 0x39,
											--]]
											dtt = dumpworldTileTypes.empty
										elseif tt == RoomBlocks.tileTypes.copy_left then
											error("I thought I got the copy offset location")
										elseif tt == RoomBlocks.tileTypes.solid  then
											dtt = dumpworldTileTypes.solid
										elseif tt == RoomBlocks.tileTypes.door then
											-- this is represented as an object in dumpworld
											-- and for what it's worth it is an object in super metroid also
											dtt = dumpworldTileTypes.empty
										elseif tt == RoomBlocks.tileTypes.spikes_or_invis then
											if ett == RoomBlocks.extTileTypes.spike_solid2_1x1 then
												dtt = dumpworldTileTypes.spikes
											elseif ett == RoomBlocks.extTileTypes.spike_solid3_1x1 then
												dtt = dumpworldTileTypes.spikes
											elseif ett == RoomBlocks.extTileTypes.spike_notsolid2_1x1 then
												dtt = dumpworldTileTypes.spikes
											elseif ett == RoomBlocks.extTileTypes.invisble_solid	then
												dtt = dumpworldTileTypes.solid
											elseif ett == RoomBlocks.extTileTypes.spike_notsolid3_1x1 then
												dtt = dumpworldTileTypes.spikes
											else
												error'here'
											end
										elseif tt == RoomBlocks.tileTypes.crumble_or_speed then
											if ett == RoomBlocks.extTileTypes.crumble_1x1_regen then
												dtt = dumpworldTileTypes.fallbreak_regen
											elseif ett == RoomBlocks.extTileTypes.crumble_2x1_regen then
												dtt = dumpworldTileTypes.fallbreak_regen
											elseif ett == RoomBlocks.extTileTypes.crumble_1x2_regen then
												dtt = dumpworldTileTypes.fallbreak_regen
											elseif ett == RoomBlocks.extTileTypes.crumble_2x2_regen then
												dtt = dumpworldTileTypes.fallbreak_regen
											elseif ett == RoomBlocks.extTileTypes.crumble_1x1 then
												dtt = dumpworldTileTypes.fallbreak
											elseif ett == RoomBlocks.extTileTypes.crumble_2x1 then
												dtt = dumpworldTileTypes.fallbreak
											elseif ett == RoomBlocks.extTileTypes.crumble_1x2 then
												dtt = dumpworldTileTypes.fallbreak
											elseif ett == RoomBlocks.extTileTypes.crumble_2x2 then
												dtt = dumpworldTileTypes.fallbreak
											elseif ett == RoomBlocks.extTileTypes.speed_regen then
												dtt = dumpworldTileTypes.speedbreak_regen
											elseif ett == RoomBlocks.extTileTypes.speed then
												dtt = dumpworldTileTypes.speedbreak
											else
												error'here'
											end
										elseif tt == RoomBlocks.tileTypes.breakable then
											if ett == RoomBlocks.extTileTypes.beam_1x1_regen then
												dtt = dumpworldTileTypes.blasterbreak_regen
											elseif ett == RoomBlocks.extTileTypes.beam_2x1_regen then
												dtt = dumpworldTileTypes.blasterbreak_regen
											elseif ett == RoomBlocks.extTileTypes.beam_1x2_regen then
												dtt = dumpworldTileTypes.blasterbreak_regen
											elseif ett == RoomBlocks.extTileTypes.beam_2x2_regen then
												dtt = dumpworldTileTypes.blasterbreak_regen
											elseif ett == RoomBlocks.extTileTypes.beam_1x1 then
												dtt = dumpworldTileTypes.blasterbreak
											elseif ett == RoomBlocks.extTileTypes.beam_2x1 then
												dtt = dumpworldTileTypes.blasterbreak
											elseif ett == RoomBlocks.extTileTypes.beam_1x2 then
												dtt = dumpworldTileTypes.blasterbreak
											elseif ett == RoomBlocks.extTileTypes.beam_2x2 then
												dtt = dumpworldTileTypes.blasterbreak
											elseif ett == RoomBlocks.extTileTypes.powerbomb_1x1 then
												dtt = dumpworldTileTypes.plasmabreak
											elseif ett == RoomBlocks.extTileTypes.supermissile_1x1_regen then
												dtt = dumpworldTileTypes.grenadebreak_regen
											elseif ett == RoomBlocks.extTileTypes.supermissile_1x1 then
												dtt = dumpworldTileTypes.grenadebreak
											elseif ett == RoomBlocks.extTileTypes.beam_door then
												dtt = dumpworldTileTypes.solid
											else
											
												error'here'
											end
										elseif tt == RoomBlocks.tileTypes.copy_up  then
											error("I thought I got the copy offset location")
										elseif tt == RoomBlocks.tileTypes.grappling then
											if ett == RoomBlocks.extTileTypes.grappling then
												dtt = dumpworldTileTypes.solid
											elseif ett == RoomBlocks.extTileTypes.grappling_break_regen then
												dtt = dumpworldTileTypes.solid
											elseif ett == RoomBlocks.extTileTypes.grappling_break then
												dtt = dumpworldTileTypes.solid
											elseif ett == RoomBlocks.extTileTypes.grappling2 then
												dtt = dumpworldTileTypes.solid
											elseif ett == RoomBlocks.extTileTypes.grappling3 then
												dtt = dumpworldTileTypes.solid
											else
--[===[
												print('here with ext tiletype '..tolua{
													region = ('%02x'):format(m.obj.region),
													index = ('%02x'):format(m.obj.index),
													i = i,
													j = j,
													ti = ti,
													tj = tj,
													dx = dx,
													dy = dy,
													sx = sx,
													sy = sy,
													tt = ('%02x'):format(tt),
													ett = ('%02x'):format(ett),
													d1 = ('%02x'):format(d1),
													d2 = ('%02x'):format(d2),
													d3 = ('%02x'):format(d3),
													copych1 = ('%02x'):format(copych1),
													copych2 = ('%02x'):format(copych2),
													copych3 = ('%02x'):format(copych3),
												})
--]===]											
												error'here'
											end
											-- TODO grappling blocks eh
											dtt = dumpworldTileTypes.solid
										elseif tt == RoomBlocks.tileTypes.bombable then
											if ett == RoomBlocks.extTileTypes.bombable_1x1_regen then
												dtt = dumpworldTileTypes.skillsawbreak_regen
											elseif ett == RoomBlocks.extTileTypes.bombable_2x1_regen then
												dtt = dumpworldTileTypes.skillsawbreak_regen
											elseif ett == RoomBlocks.extTileTypes.bombable_1x2_regen then
												dtt = dumpworldTileTypes.skillsawbreak_regen
											elseif ett == RoomBlocks.extTileTypes.bombable_2x2_regen then
												dtt = dumpworldTileTypes.skillsawbreak_regen
											elseif ett == RoomBlocks.extTileTypes.bombable_1x1 then
												dtt = dumpworldTileTypes.skillsawbreak
											elseif ett == RoomBlocks.extTileTypes.bombable_2x1 then
												dtt = dumpworldTileTypes.skillsawbreak
											elseif ett == RoomBlocks.extTileTypes.bombable_1x2 then
												dtt = dumpworldTileTypes.skillsawbreak
											elseif ett == RoomBlocks.extTileTypes.bombable_2x2 then
												dtt = dumpworldTileTypes.skillsawbreak
											else
												error'here'
											end
										else
											error'here'
										end
--]====]										

										-- write out a dumpworld map
										ctx.dumpworldTileImg.buffer[0+3*dstIndex] = dtt
										ctx.dumpworldTileImg.buffer[1+3*dstIndex] = 0
										ctx.dumpworldTileImg.buffer[2+3*dstIndex] = 0
										
										if foreground then
											ctx.dumpworldTileFgImg.buffer[0+3*dstIndex] = d1
											ctx.dumpworldTileFgImg.buffer[1+3*dstIndex] = bit.band(d2, 0x03)
											ctx.dumpworldTileFgImg.buffer[2+3*dstIndex] = 0
										else
											ctx.dumpworldTileBgImg.buffer[0+3*dstIndex] = d1
											ctx.dumpworldTileBgImg.buffer[1+3*dstIndex] = bit.band(d2, 0x03)
											ctx.dumpworldTileBgImg.buffer[2+3*dstIndex] = 0
										end
--]==]
								end
							end


							for pi=0,debugImageBlockSizeInPixels-1 do
								for pj=0,debugImageBlockSizeInPixels-1 do
									local x = pi + debugImageBlockSizeInPixels * (ti + blocksPerRoom * (m.obj.x + i + ofsInRoomBlocksX))
									local y = pj + debugImageBlockSizeInPixels * (tj + blocksPerRoom * (m.obj.y + j + ofsInRoomBlocksY))
									if x >= 0 and x < debugMapImage.width
									and y >= 0 and y < debugMapImage.height 
									then
										local dstIndex = x + debugMapMaskImage.width * y
										-- write out solid tiles only
										debugMapMaskImage.buffer[0+3*dstIndex] = isBorder and 0xff or 0x00
										debugMapMaskImage.buffer[1+3*dstIndex] = isSolid and 0xff or 0x00
										debugMapMaskImage.buffer[2+3*dstIndex] = 0xff
									end
								end
							end
						end
					end
				end
			end
		end
	end

	drawstr(debugMapImage, firstcoord[1], firstcoord[2], ('%x-%02x'):format(m.obj.region, m.obj.index))
	drawstr(debugMapImage, firstcoord[1], firstcoord[2]+6, ('$%04x'):format(m.addr))
end

local function drawline(img, x1,y1,x2,y2, r,g,b)
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
		if x >= 0 and x < img.width
		and y >= 0 and y < img.height 
		then
			img.buffer[0+3*(x+img.width*y)] = r
			img.buffer[1+3*(x+img.width*y)] = g
			img.buffer[2+3*(x+img.width*y)] = b
		end
	end
end

local function drawRoomBlockDoors(ctx, roomBlockData)
	local debugMapImage = ctx.debugMapImage
	local blocks = roomBlockData.blocks
	-- for all blocks in the room, if any are xx9xyy, then associate them with exit yy in the door_t list (TODO change to exit_t)	
	-- then, cycle through exits, and draw lines from each block to the exit destination

	for _,rs in ipairs(roomBlockData.roomStates) do
		local srcRoom = rs.room
		local srcRoom_ofsx, srcRoom_ofsy = ofsPerRegion[srcRoom.obj.region+1](srcRoom.ptr)
		local srcRoom_xofs = debugImageRoomSizeInPixels * srcRoom_ofsx
		local srcRoom_yofs = debugImageRoomSizeInPixels * srcRoom_ofsy
		for exitIndex,blockpos in pairs(roomBlockData.blocksForExit) do
--print('in room '..('%02x/%02x'):format(srcRoom.obj.region, srcRoom.obj.index)..' looking for exit '..exitIndex..' with '..#blockpos..' blocks')
			-- TODO lifts will mess up the order of this, maybe?
			local door = srcRoom.doors[exitIndex+1]
			if not door then
--print('found no door')
			elseif door.ctype ~= 'door_t' then
--print("door isn't a ctype")
			-- TODO handle lifts?
			else
				local dstRoom = assert(door.destRoom)
				local dstRoom_ofsx, dstRoom_ofsy = ofsPerRegion[dstRoom.obj.region+1](dstRoom.ptr)
				local dstRoom_xofs = debugImageRoomSizeInPixels * dstRoom_ofsx
				local dstRoom_yofs = debugImageRoomSizeInPixels * dstRoom_ofsy
			
				-- draw an arrow or something on the map where the door drops us off at
				-- door.destRoom is the room
				-- draw it at door.ptr.screenX by door.ptr.screenY
				-- and offset it according to direciton&3 and distToSpawnSamus (maybe)

				local i = door.ptr.screenX
				local j = door.ptr.screenY
				local dir = bit.band(door.ptr.direction, 3)	-- 0-based
				local ti, tj = 0, 0	--table.unpack(doorPosForDir[dir])
					
				local k=debugImageBlockSizeInPixels*3-1 
					
				local pi, pj
				if dir == 0 then		-- enter from left
					pi = k
					pj = bit.rshift(debugImageRoomSizeInPixels, 1)
				elseif dir == 1 then	-- enter from right
					pi = debugImageRoomSizeInPixels - k
					pj = bit.rshift(debugImageRoomSizeInPixels, 1)
				elseif dir == 2 then	-- enter from top
					pi = bit.rshift(debugImageRoomSizeInPixels, 1)
					pj = k
				elseif dir == 3 then	-- enter from bottom
					pi = bit.rshift(debugImageRoomSizeInPixels, 1)
					pj = debugImageRoomSizeInPixels - k
				end
			
				-- here's the pixel x & y of the door destination
				local x1 = dstRoom_xofs + pi + debugImageBlockSizeInPixels * (ti + blocksPerRoom * (dstRoom.obj.x + i))
				local y1 = dstRoom_yofs + pj + debugImageBlockSizeInPixels * (tj + blocksPerRoom * (dstRoom.obj.y + j))

				for _,pos in ipairs(blockpos) do
					-- now for src block pos
					local x2 = srcRoom_xofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (pos[1] + blocksPerRoom * srcRoom.obj.x)
					local y2 = srcRoom_yofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (pos[2] + blocksPerRoom * srcRoom.obj.y)
					drawline(debugMapImage,x1,y1,x2,y2)
				end
			end
		end
	end
end

function drawRoomBlockPLMs(ctx, roomBlockData)
	local debugMapImage = ctx.debugMapImage
	for _,rs in ipairs(roomBlockData.roomStates) do
		local m = rs.room
		local ofsInRoomBlocksX, ofsInRoomBlocksY = ofsPerRegion[m.obj.region+1](m.ptr)
		local xofs = debugImageRoomSizeInPixels * ofsInRoomBlocksX
		local yofs = debugImageRoomSizeInPixels * ofsInRoomBlocksY
		if rs.plmset then
			for _,plm in ipairs(rs.plmset.plms) do
				local x = xofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (plm.x + blocksPerRoom * m.obj.x)
				local y = yofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (plm.y + blocksPerRoom * m.obj.y)
				drawline(debugMapImage,x+2,y,x-2,y, 0x00, 0xff, 0xff)
				drawline(debugMapImage,x,y+2,x,y-2, 0x00, 0xff, 0xff)
				drawstr(debugMapImage, x+5, y, ('$%x'):format(plm.cmd))
			end
		end
		if rs.enemySpawnSet then
			for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do
				local x = math.round(xofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (enemySpawn.x / 16 + blocksPerRoom * m.obj.x))
				local y = math.round(yofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (enemySpawn.y / 16 + blocksPerRoom * m.obj.y))
				drawline(debugMapImage,x+2,y,x-2,y, 0xff, 0x00, 0xff)
				drawline(debugMapImage,x,y+2,x,y-2, 0xff, 0x00, 0xff)
				drawstr(debugMapImage, x+5, y, ('$%x'):format(enemySpawn.enemyAddr))
			end
		end
	end
end


function SMMap:mapSaveImage(filenamePrefix)
	local Image = require 'image'

	--[[
	now that tileSet is loaded, decode the bgdata
	TODO how about grouping by unique bg_t + tileSet pairs?
	to reduce redundant outputs
	actually we can't do this for bgs that have multiple rs's / varying tileSet's
	so do it upon decode

	background bitmaps are generated from combining the bgData graphicsTile indexes with a roomstate's tileSet's graphicsTiles
	stored as 8-bit indexed bitmaps ... use the tileset's palette to get the rgb colors

	group these by unique bgData + tileData to cache unique indexed bitmaps
	or group by unique bgData + tileSet to cache unique rgb bitmaps
		
	cache these as we build them
	--]]
	self.bitmapForTileSetAndTileMap = {}
	self.getBitmapForTileSetAndTileMap = function(tileSet, tilemap)
		self.bitmapForTileSetAndTileMap[tileSet.index] = self.bitmapForTileSetAndTileMap[tileSet.index] or {}
		local bgBmp = self.bitmapForTileSetAndTileMap[tileSet.index][tilemap.addr]
		if bgBmp then return bgBmp end

		bgBmp = {}

print('generating bitmap for tileSet '..('%02x'):format(tileSet.index)..' tilemap '..('%06x'):format(tilemap.addr))		
		bgBmp.tilemap = tilemap
		bgBmp.dataBmp = ffi.new('uint8_t[?]', graphicsTileSizeInPixels * graphicsTileSizeInPixels * tilemap.width * tilemap.height)

		self:convertTilemapToBitmap(
			bgBmp.dataBmp,
			tilemap.data,
			tileSet.graphicsTileVec.v,
			tilemap.width,
			tilemap.height,
			1)
		
		self.bitmapForTileSetAndTileMap[tileSet.index][tilemap.addr] = bgBmp
		return bgBmp
	end

	filenamePrefix = filenamePrefix or 'map'

	if mapSaveWorldImage then
	
		local fullMapWidthInBlocks = 68
		local fullMapHeightInBlocks = 58

		local w = debugImageRoomSizeInPixels * fullMapWidthInBlocks
		local h = debugImageRoomSizeInPixels * fullMapHeightInBlocks
	
		local debugMapImage = Image(w, h, 3, 'unsigned char')
		local debugMapMaskImage = Image(w, h, 3, 'unsigned char')
	
		local mapTexImage = Image(
			blockSizeInPixels * blocksPerRoom * fullMapWidthInBlocks,
			blockSizeInPixels * blocksPerRoom * fullMapHeightInBlocks,
			3, 'unsigned char')
		mapTexImage:clear()

		-- 1 pixel : 1 block for dumpworld
		local dumpw = blocksPerRoom * fullMapWidthInBlocks
		local dumph = blocksPerRoom * fullMapHeightInBlocks
	
		local dumpworldTileImg = Image(dumpw, dumph, 3, 'unsigned char')
		local dumpworldTileFgImg = Image(dumpw, dumph, 3, 'unsigned char')
		local dumpworldTileBgImg = Image(dumpw, dumph, 3, 'unsigned char')
		
		local ctx = {
			sm = self,
			debugMapImage = debugMapImage,
			debugMapMaskImage = debugMapMaskImage,
			mapTexImage = mapTexImage,
			dumpworldTileImg = dumpworldTileImg,
			dumpworldTileFgImg = dumpworldTileFgImg,
			dumpworldTileBgImg = dumpworldTileBgImg,
		}

		for _,roomBlockData in ipairs(self.roomblocks) do
			for _,rs in ipairs(roomBlockData.roomStates) do
				drawRoomBlocks(ctx, roomBlockData, rs)
			end
		end

		for _,roomBlockData in ipairs(self.roomblocks) do
			drawRoomBlockDoors(ctx, roomBlockData)
			drawRoomBlockPLMs(ctx, roomBlockData)
		end

		debugMapImage:save(filenamePrefix..'.png')
		debugMapMaskImage:save(filenamePrefix..'-mask.png')
		mapTexImage:save(filenamePrefix..'-tex.png')
		if filenamePrefix == 'map' then	-- don't do this for the .random file
			dumpworldTileImg:save('../dumpworld/zeta/maps/sm3/tile.png')
			dumpworldTileFgImg:save('../dumpworld/zeta/maps/sm3/tile-fg.png')
			dumpworldTileBgImg:save('../dumpworld/zeta/maps/sm3/tile-bg.png')
		end
	end
	
	-- for now only write out tile graphics for the non-randomized version
	if filenamePrefix == 'map' then
		if mapSaveMode7TileSets then
			for _,tileSet in ipairs(self.tileSets) do
				if tileSet.mode7TileSet then
					-- TODO this only in the mapSaveImage function
					local mode7image = Image(
						graphicsTileSizeInPixels * mode7sizeInGraphicTiles,
						graphicsTileSizeInPixels * mode7sizeInGraphicTiles,
						3, 'unsigned char')
					mode7image:clear()
					local maxdestx = 0
					local maxdesty = 0	
					for i=0,mode7sizeInGraphicTiles-1 do
						for j=0,mode7sizeInGraphicTiles-1 do
							local mode7tileIndex = tileSet.mode7tiles[i + mode7sizeInGraphicTiles * j]
							for y=0,graphicsTileSizeInPixels-1 do
								for x=0,graphicsTileSizeInPixels-1 do
									local destx = x + graphicsTileSizeInPixels * i
									local desty = y + graphicsTileSizeInPixels * j
									local paletteIndex = tileSet.mode7TileSet[
										x + graphicsTileSizeInPixels * (y + graphicsTileSizeInPixels * mode7tileIndex)
									]
									local src = tileSet.palette.colors[paletteIndex]
									-- TODO what about pixel/palette mask/alpha?
									if src.r > 0 or src.g > 0 or src.b > 0 then
										maxdestx = math.max(maxdestx, destx)
										maxdesty = math.max(maxdestx, desty)
										local dst = mode7image.buffer + 3 * (destx + mode7image.width * desty)
										dst[0] = math.floor(src.r*255/31)
										dst[1] = math.floor(src.g*255/31)
										dst[2] = math.floor(src.b*255/31)
									end
								end
							end
						end
					end
					mode7image = mode7image:copy{x=0, y=0, width=maxdestx+1, height=maxdesty+1}
					mode7image:save(filenamePrefix..' tileSet='..('%02x'):format(tileSet.index)..' mode7.png')
				end
			end
		end
		
		if mapSaveTileSets then
			-- TODO how about a wrap row?  grid x, grid y, result x, result y 
			for _,tileSet in ipairs(self.tileSets) do
				if tileSet.tileGfxBmp then
					local rowWidth = 32
					local img = Image(blockSizeInPixels*rowWidth, blockSizeInPixels*math.ceil(tileSet.tileGfxCount/rowWidth), 3, 'unsigned char')
					local imgused = Image(blockSizeInPixels*rowWidth, blockSizeInPixels*math.ceil(tileSet.tileGfxCount/rowWidth), 3, 'unsigned char')
					for tileIndex=0,tileSet.tileGfxCount-1 do
						local xofs = tileIndex % rowWidth
						local yofs = math.floor(tileIndex / rowWidth)
						for i=0,blockSizeInPixels-1 do
							for j=0,blockSizeInPixels-1 do
								local dstIndex = i + blockSizeInPixels * xofs + img.width * (j + blockSizeInPixels * yofs)
								local srcIndex = i + blockSizeInPixels * (j + blockSizeInPixels * tileIndex)
								local paletteIndex = tileSet.tileGfxBmp[srcIndex]
								local r,g,b = 0,0,0
								if bit.band(paletteIndex, 0xf) > 0 then
									local src = tileSet.palette.colors[paletteIndex]
									r = math.floor(src.r*255/31)
									g = math.floor(src.g*255/31)
									b = math.floor(src.b*255/31)
								end
								img.buffer[0 + 3 * dstIndex] = r
								img.buffer[1 + 3 * dstIndex] = g
								img.buffer[2 + 3 * dstIndex] = b
								
								-- draw some diagonal green lines over the used tiles
								if tileSet.tileIndexesUsed[tileIndex] and (i + j) % 3 == 0 then
									r = math.floor(.5 * 0 + .5 * r)
									g = math.floor(.5 * 255 + .5 * g)
									b = math.floor(.5 * 0 + .5 * b)
								end
								imgused.buffer[0 + 3 * dstIndex] = r
								imgused.buffer[1 + 3 * dstIndex] = g
								imgused.buffer[2 + 3 * dstIndex] = b
							end
						end
					end
					img:save('tileset/tileSet='..('%02x'):format(tileSet.index)..' tilegfx.png')
					imgused:save('tileset used/tileSet='..('%02x'):format(tileSet.index)..' tilegfx used.png')
				
					do
						local numGraphicTiles = tileSet.graphicsTileVec.size / graphicsTileSizeInBytes
						local tilemapElemSizeX = 16
						local tilemapElemSizeY = math.floor(numGraphicTiles / tilemapElemSizeX)
						assert(tilemapElemSizeX * tilemapElemSizeY == numGraphicTiles)
						local tilemap = ffi.new('tilemapElem_t[?]', tilemapElemSizeX * tilemapElemSizeY)
						for i=0,numGraphicTiles-1 do
							tilemap[i].graphicsTileIndex = i
							tilemap[i].colorIndexHi = 0
							tilemap[i].xflip = 0
							tilemap[i].yflip = 0
						end
						local imgwidth = graphicsTileSizeInPixels * tilemapElemSizeX
						local imgheight = graphicsTileSizeInPixels * tilemapElemSizeY
						local tilemapElemIndexedBmp = ffi.new('uint8_t[?]', imgwidth * imgheight)
						self:convertTilemapToBitmap(
							tilemapElemIndexedBmp,		-- dst uint8_t[graphicsTileSizeInPixels][numGraphicTiles * graphicsTileSizeInPixels]
							tilemap,					-- tilemap = tilemapElem_t[numGraphicTiles * graphicsTileSizeInPixels]
							tileSet.graphicsTileVec.v,	-- graphicsTiles = 
							tilemapElemSizeX,			-- tilemapElemSizeX
							tilemapElemSizeY,			-- tilemapElemSizeY
							1)							-- count
						local graphicsTileimg = Image(imgwidth, imgheight, 3, 'unsigned char')
						self:indexedBitmapToRGB(graphicsTileimg.buffer, tilemapElemIndexedBmp, imgwidth, imgheight, tileSet)
						graphicsTileimg:save('graphictiles/graphictile='..('%02x'):format(tileSet.index)..'.png')
					end
				end
			end
		end

		if mapSaveLayer2Backgrounds then
			for _,roomBlockData in ipairs(self.roomblocks) do
				if roomBlockData.layer2blocks then
					local _, rs = roomBlockData.roomStates:find(nil, function(rs) return rs.tileSet end)
					local tileSet = rs and rs.tileSet or self.tileSets[1]

					local pixw = blockSizeInPixels * roomBlockData.width
					local pixh = blockSizeInPixels * roomBlockData.height
					local img = Image(pixw, pixh, 3, 'unsigned char')
					img:clear()
					local w = roomBlockData.width
					local h = roomBlockData.height
					for y=0,h-1 do
						for x=0,w-1 do
							local tileIndex = ffi.cast('uint16_t*', roomBlockData.layer2blocks + 2 * (x + w * y))[0]
							local pimask = bit.band(tileIndex, 0x400) ~= 0 and 15 or 0
							local pjmask = bit.band(tileIndex, 0x800) ~= 0 and 15 or 0
							tileIndex = bit.band(tileIndex, 0x3ff)
							for pj=0,blockSizeInPixels-1 do
								for pi=0,blockSizeInPixels-1 do
									local spi = bit.bxor(pi, pimask)
									local spj = bit.bxor(pj, pjmask)
									local srcIndex = spi + blockSizeInPixels * (spj + blockSizeInPixels * tileIndex)
									local paletteIndex = tileSet.tileGfxBmp[srcIndex]
									if bit.band(paletteIndex, 0xf) > 0 then
										local src = tileSet.palette.colors[paletteIndex]
										local dst = img.buffer + 3 * (pi + blockSizeInPixels * x + pixw * (pj + blockSizeInPixels * y))
										dst[0] = src.r*255/31
										dst[1] = src.g*255/31
										dst[2] = src.b*255/31
									end
								end
							end
						end
					end

					img:save('layer2bgs/'..('%06x'):format(roomBlockData.addr)..'.png')
				end
			end
		end

		if mapSaveBackgrounds then
			for _,tilemap in ipairs(self.bgTilemaps) do
				local fn = ('bgs/%06x.png'):format(tilemap.addr)

				local tileSet
				local bg = tilemap.bg
				if bg then
					local rs = bg.roomStates[1]
					tileSet = rs and rs.tileSet
				end

				-- if we don't have a tileset ... then how do we know which one to use?
				tileSet = tileSet or self.tileSets[1]
				
				local bgBmp = self.getBitmapForTileSetAndTileMap(tileSet, tilemap)

				-- now find the first bgBmp associated with the bg, associated with the bgTilemap ...
				-- just for the sake of getting palette info

				local img = Image(graphicsTileSizeInPixels * tilemap.width, graphicsTileSizeInPixels * tilemap.height, 3, 'unsigned char')
				img:clear()
				for y=0,graphicsTileSizeInPixels*tilemap.height-1 do
					for x=0,graphicsTileSizeInPixels*tilemap.width-1 do
						local offset = x + img.width * y
						local paletteIndex = bgBmp.dataBmp[offset]
						if bit.band(paletteIndex, 0xf) > 0 then 
							local rgb = tileSet.palette.colors[paletteIndex]
							local dst = img.buffer + 3 * offset
							dst[0] = math.floor(rgb.r*255/31)
							dst[1] = math.floor(rgb.g*255/31)
							dst[2] = math.floor(rgb.b*255/31)
						end
					end
				end
				img:save(fn)
			end
		end
	end
end


function SMMap:mapPrintRoomBlocks()
	-- print/draw rooms
	print()
	print'all roomBlockData'
	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			print(('%02x/%02x'):format(rs.room.obj.region, rs.room.obj.index))
		end
		local w,h = roomBlockData.width, roomBlockData.height
		print(' size: '..w..','..h)
		print(' addr: '..('%06x'):format(roomBlockData.addr))

		local function printblock(data, width, col)
			for i=0,ffi.sizeof(data)-1 do
				if col and i % col == 0 then io.write' ' end
				io.write((('%02x'):format(tonumber(data[i])):gsub('0','.')))
				if i % width == width-1 then print() end 
			end
			print()
		end
		print(' tileIndexes used: '..table.keys(roomBlockData.tileIndexesUsed):sort():mapi(function(s) return ('$%03x'):format(s) end):concat', ')

		print' head:'
		printblock(roomBlockData.head, 2, 1)
		print' blocks:'
		printblock(roomBlockData.blocks, 3*w, 3) 
		if roomBlockData.layer2blocks then
			print(' layer 2 blocks:')
			printblock(roomBlockData.layer2blocks, 2*w, 2)
		end
		if roomBlockData.tail then
			print(' tail ('..('$%x'):format(ffi.sizeof(roomBlockData.tail))..' bytes) =')
			print('\t\t'..range(0,ffi.sizeof(roomBlockData.tail)-1):mapi(function(ch)
					return ('%02x'):format(ch)
				end):concat' ')
		end
		print' roomstate scrolldata:'
		for _,rs in ipairs(roomBlockData.roomStates) do
			if rs.scrollData then
				print(('  $%06x'):format(ffi.cast('uint8_t*',rs.ptr)-sm.rom))
				printblock(tableToByteArray(rs.scrollData), w/blocksPerRoom, 1)
			end
		end
		
		print('found '..#roomBlockData.doors..' door references in the blocks')
		for _,door in ipairs(roomBlockData.doors) do
			print(' '..tolua(door))
		end	
		print('blocksForExit'..tolua(roomBlockData.blocksForExit))	-- exit information
		print()
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
	local function getRoomName(m)
		return 
			--('$%06x'):format(ffi.cast('uint8_t*', m.ptr) - rom)
--			('%04x'):format(bit.band(0xffff, ffi.cast('uint8_t*', m.ptr) - rom))..nl..
			('%02x'..levelsep..'%02x'):format(m.obj.region, m.obj.index)
	end
	local function getClusterName(roomName)
		-- graphviz clusters have to have 'cluster' as a prefix
		return 'cluster_'..roomName
	end
	local function getRoomStateName(rs)
		return ('%04x'):format(bit.band(0xffff,ffi.cast('uint8_t*',rs.ptr)-rom))
	end
--print'building graph'			
	local edges = table()
	--for _,m in ipairs(self.rooms) do
	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			local m = rs.room
			local roomName = getRoomName(m)
			
			if showRoomStates then
				local itemIndex = 0
				f:write('\tsubgraph "',getClusterName(roomName),'" {\n')
				f:write('\t\trank="same";\n')
				--f:write('\t\tlabel="', roomName, '";\n')
				f:write('\t\t"', roomName, '" [pos="0,0" shape=box];\n')
				for i,rs in ipairs(m.roomStates) do
					local rsName = getRoomStateName(rs)
					local rsNodeName = roomName..nl..rsName
					f:write('\t\t"', rsNodeName, '"')
					f:write(' [pos="0,',tostring(-i),'" shape=box label="',rsName,'"]')
					f:write(';\n')
					
					-- TODO make roomState a subcluster of the room ...
					if rs.plmset then
						for plmIndex,plm in ipairs(rs.plmset.plms) do
							local plmname = plm:getName()
							if plmname and plmname:match'^item_' then
								local itemNodeName = roomName..nl..rsName..nl..plmIndex
								f:write('\t\t"', itemNodeName, '" [pos="1,',tostring(-itemIndex),'" shape=box label="', plmname, '"];\n')
								itemIndex = itemIndex + 1
							
								edges:insert('"'..itemNodeName..'" -> "'..rsNodeName..'"')
							end
						end
					end
				end
			end
			
			-- for each room door, find the room door with a matching index
			-- TODO maybe I should go by room doors.  room doors are based on map tiles, and they reference the room door with their index.
			-- however lifts are not specified by room doors, but they are always the last room door.
			-- and open exits are not room doors either ... this is where roomBlockData.blocksForExit comes in handy 
			for exitIndex, blockpos in pairs(roomBlockData.blocksForExit) do
				local roomDoor = m.doors[exitIndex+1]
				
				if roomDoor 
				and roomDoor.ctype == 'door_t' 	-- otherwise, lift_t is a suffix of a lift door_t
				then

					assert(roomDoor.destRoom)
					local destRoomName = getRoomName(roomDoor.destRoom)
				
					-- if there is no matching roomBlockDoor then it could just be a walk-out-of-the-room exit
					local color
					
					-- notice, if we reverse the search, and cycle through all roomBlockData.doors and then lookup the associated room.door, we come up with only one room door that doesn't have a mdb door ...
					-- !!! WARNING !!! 02/3d roomDoorIndex=1 has no associated room door
					local _, roomBlockDoor = roomBlockData.doors:find(nil, function(roomBlockDoor)
						-- TODO is this always true?  the blockpos exitIndex matches the roomBlockDoor.index?
						return roomBlockDoor.index == exitIndex
					end)
					if roomBlockDoor then
						-- if there is a room door then the exit is a blue door by default ... unless we find a plm for the door
						color = 'blue'

						-- we're getting multiple edges here
						-- room pertains to block data, and it will be repeated for reused block data rooms (like save points, etc)
						-- now this means roomBlockData.roomStates will have as many roomStates as there are multiple rooms which reference it
						-- so we only want to look through the roomStates that pertain to our current room
						--for _,rs in ipairs(roomBlockData.roomStates) do
						for _,rs in ipairs(m.roomStates) do	
							local rsName = getRoomStateName(rs)
--print('  roomstate_t: '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' '..rs.ptr[0]) 
						
							local color
							local doorarg = 0
							
							if rs.plmset then
								for _,plm in ipairs(rs.plmset.plms) do
--local plmname = plm:getName()
--print('   plm_t: '..plmname..' '..plm)
									-- find a matching door plm
									if plm.x == roomBlockDoor.x and plm.y == roomBlockDoor.y then
										local plmname = assert(plm:getName(), "expected door plm to have a valid name "..plm)
										color = plmname:match'^door_([^_]*)'
										doorarg = plm.args
									end
								end
							end
							color = color or 'blue'
							if color == 'eye' then color = 'darkseagreen4' end
							
							if showDoors then
								local srcNodeName = roomName
								local dstNodeName = destRoomName
								local doorName = 'door'..('%04x'):format(roomDoor.addr)
								local doorNodeName = roomName..':'..doorName
								local colorTag = '[color='..colors..']'
								local labelTag = color == 'blue' and '[label=""]' or ('[label="'..('%04x'):format(doorarg)..'"]') 
								f:write('\t"', doorNodeName, '"', colorTag, labelTag, ';\n')
								-- TODO connect the src door with the dest door
								-- look at the roomDoor destination information
								-- compare it to the room doors xy in the destination room 
								-- just like in the drawRoomBlockDoors code
								-- if you have a match then pair the doors together
								-- then TODO store this elsewhere
								-- and TODO TODO then with a bidirectional graph, next add some extra nodes to that graph based on obstructions, and last use this graph for placement and traversal of items
								edges:insert('"'..srcNodeName..'" -> "'..doorNodeName..'"'..colorTag)
								edges:insert('"'..doorNodeName..'" -> "'..dstNodeName..'"'..colorTag)
							else
								-- create door edges from each roomstate to each room
								local srcNodeName = roomName
								local dstNodeName = destRoomName
								if showRoomStates then
									srcNodeName = srcNodeName .. nl .. rsName
									--local dstRSName = getRoomStateName(assert(roomDoor.destRoom.roomStates[1]))	-- TODO how to determine destination room state?
									--dstNodeName = dstNodeName .. nl .. dstRSName
								end
								local edgecode = '"'..srcNodeName..'" -> "'..dstNodeName..'" ['
								if showRoomStates then
									--edgecode = edgecode..'lhead="'..getClusterName(destRoomName)..'" '
								end
								edgecode = edgecode .. 'color=' .. color 
								if color ~= 'blue' then
									edgecode = edgecode .. ' label="' .. ('%04x'):format(doorarg)..'"'
								end
								edgecode = edgecode .. ']'
								edges:insert(edgecode)
							end
						end
					else	-- no roomBlockDoor, so it's just a walk-out-the-wall door or a lift
						if showDoors then
							local srcNodeName = roomName
							local dstNodeName = destRoomName
							local doorName = 'door'..('%04x'):format(roomDoor.addr)
							local doorNodeName = roomName..':'..doorName
							local colorTag = ''
							local labelTag = '[label=""]'
							f:write('\t"', doorNodeName, '"', colorTag, labelTag, ';\n')
							edges:insert('"'..srcNodeName..'" -> "'..doorNodeName..'"'..colorTag)
							edges:insert('"'..doorNodeName..'" -> "'..dstNodeName..'"'..colorTag)
						else
							--if m.doors:last().ctype == 'lift_t' then
							--local roomDoor = m.doors[#m.doors-1]
							local destRoomName = getRoomName(roomDoor.destRoom)
							-- create door edges from each roomstate to each room
							local srcNodeName = roomName
							local dstNodeName = destRoomName
							if showRoomStates then
								--local srcRSName = getRoomStateName(assert(m.roomStates[1]))
								--srcNodeName = srcNodeName .. nl .. srcRSName
								--local dstRSName = getRoomStateName(assert(roomDoor.destRoom.roomStates[1]))
								--dstNodeName = dstNodeName .. nl .. dstRSName
							end
							local edgecode = '"'..srcNodeName..'" -> "'..dstNodeName..'" ['
							if showRoomStates then
								--edgecode = edgecode
								--	..'lhead="'..getClusterName(destRoomName)..'" '
								--	..'ltail="'..getClusterName(roomName)..'" '
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
			..' rooms: '..plmset.roomStates:map(function(rs)
				local m = rs.room
				return ('%02x/%02x'):format(m.obj.region, m.obj.index)
			end):concat' '
		)
		for _,plm in ipairs(plmset.plms) do
			io.write('  '..plm)
			local plmName = plm:getName()
			if plmName then io.write(' ',plmName) end
			print()
		end
	end

	-- [[ debugging - show all rooms that each plm cmd is used in
	local allPLMCmds = table()
	for _,plmset in ipairs(self.plmsets) do
		local rsstrs = table()
		for _,rs in ipairs(plmset.roomStates) do
			local region = assert(tonumber(rs.room.obj.region))
			local index = assert(tonumber(rs.room.obj.index))
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
				local region = assert(tonumber(rs.room.obj.region))
				local index = assert(tonumber(rs.room.obj.index))
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
			..' rooms: '..enemySpawnSet.roomStates:map(function(rs)
				return ('%02x/%02x'):format(rs.room.obj.region, rs.room.obj.index)
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
		print(' '..('$%06x'):format(enemyGFXSet.addr)..': '..tolua(enemyGFXSet.name)
			..' rooms: '..enemyGFXSet.roomStates:map(function(rs)
				return ('%02x/%02x'):format(rs.room.obj.region, rs.room.obj.index)
			end):concat' '
		)
		for _,enemyGFX in ipairs(enemyGFXSet.enemyGFXs) do
			io.write('  '..enemyGFX)
			local enemyName = (self.enemyForAddr[enemyGFX.enemyAddr] or {}).name
			if enemyName then
				io.write(' '..tolua(enemyName))
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
			..' rooms: '..fx1.rooms:map(function(m)
				return ('%02x/%02x'):format(m.obj.region, m.obj.index)
			end):concat' '
		)
	end

	print()
	print"all layerHandling's:"
	for _,layerHandling in ipairs(self.layerHandlings) do
		print(('%06x'):format(layerHandling.addr))
		print(' code: '..layerHandling.code:mapi(function(cmd)
			return ('%02x'):format(cmd)
		end):concat' ')
		print(disasm.disasm(layerHandling.code, layerHandling.addr))
		print(' rooms: '..layerHandling.roomStates:mapi(function(rs)
				return ('%02x/%02x'):format(rs.room.obj.region, rs.room.obj.index)
			end):concat' ')
	end

	-- print bg info
	print()
	print("all bg_t's:")
	self.bgs:sort(function(a,b) return a.addr < b.addr end)
	for _,bg in ipairs(self.bgs) do
		print(' '..('$%06x'):format(bg.addr)..': '..bg.ptr[0])
		print('  rooms: '..bg.roomStates:mapi(function(rs)
				return ('%02x/%02x'):format(rs.room.obj.region, rs.room.obj.index)
			end):concat' ')
		if bg.tilemap then
			print('  tilemap.size: '..('$%x'):format(bg.tilemap.size))
			print('  tilemap.addr: '..('$%x'):format(bg.tilemap.addr))
		end
	end

	-- print room info
	print()
	print("all room_t's:")
	for _,m in ipairs(self.rooms) do
		print(' room_t '..('$%06x'):format(ffi.cast('uint8_t*', m.ptr) - rom)..' '..m.ptr[0])
		for _,rs in ipairs(m.roomStates) do
			print('  roomstate_t: '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' '..rs.ptr[0]) 
			print('  '..rs.select_ctype..': '..('$%06x'):format(ffi.cast('uint8_t*', rs.select_ptr) - rom)..' '..tostring(rs.select))
			-- [[
			if rs.plmset then
				for _,plm in ipairs(rs.plmset.plms) do
					io.write('   plm_t: ')
					local plmName = plm:getName()
					if plmName then io.write(plmName..': ') end
					print(plm)
					--print('    plm scrollmod: '..('$%06x'):format(plm.args + self.plmBaseAddress)..': '..plm.scrollmod:map(function(x) return ('%02x'):format(x) end):concat' ')
				end
			end
			--]]
			for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do	
				print('   enemySpawn_t: '
					..((self.enemyForAddr[enemySpawn.enemyAddr] or {}).name or '')
					..': '..enemySpawn)
			end
			print('   enemyGFXSet: '..tolua(rs.enemyGFXSet.name))	--:match'\0*(.*)')
			for _,enemyGFX in ipairs(rs.enemyGFXSet.enemyGFXs) do
				print('    enemyGFX_t: '
					..tolua((self.enemyForAddr[enemyGFX.enemyAddr] or {}).name or '')
					..': '..enemyGFX)
			end
			for _,fx1 in ipairs(rs.fx1s) do
				print('   fx1_t: '..('$%06x'):format( ffi.cast('uint8_t*',fx1.ptr)-rom )..': '..fx1.ptr[0])
			end
			for _,bg in ipairs(rs.bgs) do
				print('   bg_t: '..('$%06x'):format( ffi.cast('uint8_t*',bg.ptr)-rom )..': '..bg.ptr[0])
			end
			-- TODO only disassemble code once per location -- no repeats per repeated room pointers
			print('   room select code:')
			local roomSelectCodeAddr = topc(self.roomBank, rs.select.testCodeAddr)
			print(disasm.disasm(disasm.readCode(rom, roomSelectCodeAddr, 0x100), roomSelectCodeAddr))
		end
		for _,door in ipairs(m.doors) do
			print('  '..door.ctype..': '
				..('$83:%04x'):format(door.addr)
				..' '..door.ptr[0])
			if door.doorCode then
				print('   code: '..door.doorCode:mapi(function(c) return ('%02x'):format(c) end):concat' ')
				print(disasm.disasm(door.doorCode, door.doorCodeAddr))
			end
		end
	end

	--[[ print plmset information
	-- half this is in the all plms_ts and the other half is in all room_ts
	print()
	print'all plmsets:'
	for i,plmset in ipairs(self.plmsets) do
		print(' plmset '..('$%06x'):format(plmset.addr))
		for _,rs in ipairs(plmset.roomStates) do
			print('  roomstate_t: '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' '..rs.ptr[0]) 
		end
		for _,plm in ipairs(plmset.plms) do
			io.write('  plm_t: ')
			local plmName = plm:getName()
			if plmName then io.write(plmName..': ') end
			print(plm)
			if plm.scrollmod then
				print('  plm scrollmod: '..('$%06x'):format(self.plmBaseAddress + plm.args)..': '..plm.scrollmod:map(function(x) return ('%02x'):format(x) end):concat' ')
			end
		end
	end
	--]]

	-- [[ debugging: print out a graphviz dot file of the rooms and doors
	self:mapWriteGraphDot()
	--]]

	self:mapPrintRoomBlocks()

	--[[ debugging: print all unique test codes
	local testCodeAddrs = table()
	for _,m in ipairs(self.rooms) do
		for _,rs in ipairs(m.roomStates) do
			testCodeAddrs[rs.select.testCodeAddr] = true
		end
	end
	print('unique test code addrs:')
	for _,testCodeAddr in ipairs(testCodeAddrs:keys():sort()) do
		print(('$%04x'):format(testCodeAddr))
	end
	--]]

	--[[ debugging: print all unique door codes
	local doorcodes = table()
	for _,m in ipairs(self.rooms) do
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

	print()
	print"all tileSet_t's:"
	for _,tileSet in ipairs(self.tileSets) do
		io.write(' index='..('%02x'):format(tileSet.index))
		io.write(' addr='..('$%06x'):format(tileSet.addr))
		print(': '..tileSet.obj)
		print('  tileIndexes used = '..table.keys(tileSet.tileIndexesUsed):sort():mapi(function(s)
				return ('$%03x'):format(s)
			end):concat', ')
		print('  rooms used = '..tileSet.roomStates:mapi(function(rs)
				return ('%02x/%02x'):format(rs.room.obj.region, rs.room.obj.index)
			end):concat', ')
	end

	print()
	print"all tileSet palettes:"
	for _,palette in ipairs(self.tileSetPalettes) do
		print(' '..('$%06x'):format(palette.addr))
		print('  size='..('$%x'):format(palette.size))
		print('  color={'..range(0,palette.size-1):mapi(function(i)
				return tostring(palette.colors[i])
			end):concat', '..'}')
		print('  used by tileSets: '..palette.tileSets:mapi(function(tileSet) return ('%02x'):format(tileSet.index) end):concat' ')
	end

	print()
	print"all tileSet tilemaps:"
	for _,tilemap in ipairs(self.tileSetTilemaps) do
		print(' '..('$%06x'):format(tilemap.addr))
		print('  size='..('$%06x'):format(tilemap.size))
		print('  compressedSize='..('$%06x'):format(tilemap.compressedSize))
	end

	print()
	print"all tileSet graphicsTileSets:"
	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		print(' '..('$%06x'):format(graphicsTileSet.addr))
		print('  size='..('$%06x'):format(graphicsTileSet.size))
		print('  compressedSize='..('$%06x'):format(graphicsTileSet.compressedSize))
	end
end

function SMMap:mapBuildMemoryMap(mem)
	local rom = self.rom
	for _,m in ipairs(self.rooms) do
		local addr = topc(self.roomBank, m.addr)	
		mem:add(addr, ffi.sizeof'room_t', 'room_t', m)
		for _,rs in ipairs(m.roomStates) do
			assert(rs.select_ptr)
			mem:add(ffi.cast('uint8_t*', rs.select_ptr) - rom, ffi.sizeof(rs.select_ctype), 'roomselect', m)
			mem:add(ffi.cast('uint8_t*', rs.ptr) - rom, ffi.sizeof'roomstate_t', 'roomstate_t', m)
			if rs.scrollData then
				-- sized room width x height
				local addr = topc(self.scrollBank, rs.obj.scrollAddr)
				mem:add(addr, #rs.scrollData, 'scrolldata', m)
			end
			
			mem:add(topc(self.fx1Bank, rs.obj.fx1Addr), #rs.fx1s * ffi.sizeof'fx1_t' + (rs.fx1term and 2 or 0), 'fx1_t', m)
		
			-- TODO store for printing?  possibly relocation?
			local addr = topc(self.roomBank, rs.select.testCodeAddr)
			local code = disasm.readCode(rom, addr, 100)
			
			mem:add(addr, #code, 'room select code', m)
		end
		
		mem:add(topc(self.doorAddrBank, m.obj.doors), #m.doors * 2, 'dooraddrs', m)
		for _,door in ipairs(m.doors) do
			mem:add(ffi.cast('uint8_t*',door.ptr)-rom, ffi.sizeof(door.ctype), door.ctype, m)
			if door.doorCode then
				mem:add(door.doorCodeAddr, #door.doorCode, 'door code', m)
			end
		end
	end

	for _,layerHandling in ipairs(self.layerHandlings) do
		mem:add(layerHandling.addr, #layerHandling.code, 'layer handling code', layerHandling.roomStates[1].room)
	end

	for _,enemySpawnSet in ipairs(self.enemySpawnSets) do
		mem:add(enemySpawnSet.addr, 3 + #enemySpawnSet.enemySpawns * ffi.sizeof'enemySpawn_t', 'enemySpawn_t', enemySpawnSet.roomStates[1].room)
	end
	for _,enemyGFXSet in ipairs(self.enemyGFXSets) do
		-- 10 = 8 for name, 2 for term
		mem:add(enemyGFXSet.addr - 8, 10 + #enemyGFXSet.enemyGFXs * ffi.sizeof'enemyGFX_t', 'enemyGFX_t', enemyGFXSet.roomStates[1].room)
	end

	for _,plmset in ipairs(self.plmsets) do
		local m = plmset.roomStates[1].room
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
		for _,plm in ipairs(plmset.plms) do
			if plm.scrollmod then
				mem:add(self.plmBaseAddress + plm.args, #plm.scrollmod, 'plm scrollmod', m)
			end
		end
	end
	
	for _,roomBlockData in ipairs(self.roomblocks) do
		mem:add(roomBlockData.addr, roomBlockData.compressedSize, 'roomblocks lz data', roomBlockData.roomStates[1].room)
	end

	for _,bg in ipairs(self.bgs) do
		local m = bg.roomStates[1].room
		mem:add(bg.addr, ffi.sizeof(bg.ctype.name), 'bg_t', m)
	end

	for _,tilemap in ipairs(self.bgTilemaps) do
		local bg = tilemap.bg
		local rs = bg and bg.roomStates[1]
		mem:add(
			tilemap.addr,
			tilemap.compressedSize,
			'bg tilemapElem_t lz data',
			rs and rs.room or nil
		)
	end

	mem:add(
		commonRoomSubtileAddr,
		self.commonRoomGraphicsTileCompressedSize,
		'common room graphicsTile_t lz data')
	mem:add(
		commonRoomTilemapAddr,
		self.commonRoomTilemapCompressedSize,
		'common room tilemapElem_t lz data')

-- [[
	-- should I do this for used palettes, not just my fixed maximum?
	-- and TODO how about declaring this write range and only writing back the tileSets used
	for _,tileSet in ipairs(self.tileSets) do
		local room = #tileSet.roomStates > 0 and tileSet.roomStates[1].room or nil
		mem:add(
			tileSet.addr,
			ffi.sizeof'tileSet_t',
			'tileSet_t',
			room
		)
	end

	for _,palette in ipairs(self.tileSetPalettes) do
		local rs
		for _,tileSet in ipairs(palette.tileSets) do
			rs = tileSet.roomStates[1]
			if rs then break end
		end
		mem:add(
			palette.addr,
			palette.compressedSize,
			'tileSet palette rgb_t lz data',
			rs and rs.room or nil
		)
	end

	for _,tilemap in ipairs(self.tileSetTilemaps) do
		local rs
		for _,tileSet in ipairs(tilemap.tileSets) do
			rs = tileSet.roomStates[1]
			if rs then break end
		end	
		mem:add(
			tilemap.addr,
			tilemap.compressedSize,
			'tileSet tilemapElem_t lz data',
			rs and rs.room or nil
		)
	end

	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		local rs
		for _,tileSet in ipairs(graphicsTileSet.tileSets) do
			rs = tileSet.roomStates[1]
			if rs then break end
		end	
		mem:add(
			graphicsTileSet.addr,
			graphicsTileSet.compressedSize,
			'tileSet graphicsTile_t lz data',
			rs and rs.room or nil
		)	
	end
--]]
end

function SMMap:mapWritePLMs(roomBankWriteRanges)
	local rom = self.rom

	-- [inclusive, exclusive)
	local plmWriteRanges = WriteRange({
		{0x78000, 0x79194},
		-- then comes 100 bytes of layer handling code
		-- then rooms (see roomWriteRanges {0x791f8, 0x7b76a})
		-- then comes door codes 0x7b971 to end of 0x7c0fa routine
		{0x7c215, 0x7c8c7},
		-- next comes 199 bytes of layer handling code, which is L12 data, and then more mdb's
		-- then comes door codes 0x7e1d8 to end of 0x7e513 routine
--		{0x7e87f, 0x7e880},     -- a single plm_t 2-byte terminator ... why do I think this is overlapping with some other data?
		
		-- free space: 
		{0x7e99b, 0x80000},     
	}, 'plm_t')

	-- [[ re-indexing the doors
	--[=[
	notes on doors:
	plm_t of door_* has an x and y that matches up with the door region in the map
	the plm arg low byte of each (non-blue) door is a unique index, contiguous 0x00..0x60 and 0x80..0xac
	(probably used wrt savefiles, to know what doors have been opened)
	certain grey doors have nonzero upper bytes, either  0x00, 0x04, 0x08, 0x0c, 0x18, 0x90, 0x94
	
	TODO the plm is associated with a sm.roomblocks[i].doors[j]
	is the plm:door relation always 1-1, or can you have multiple plms per door, as you can have multiple roomStates per room?
	in that case, should I be duplicating IDs between PLMs?
	or perhaps I should not reindex here, but instead I should use the PLM's index to look up the associated sm.roomblocks[].doors[]?
	--]=]
	print'all door plm ids:'
	-- re-id all door plms?
	local doorid = 0
	for _,plmset in ipairs(self.plmsets) do
		local eyeparts
		local eyedoor
		for _,plm in ipairs(plmset.plms) do
			local name = plm:getName()
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
			local name = plm:getName()
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
				rs.obj.plmAddr = 0
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
	-- [[ if two plms point to matching scrollmods then point them to the same scrollmod object
	-- then collect all unique scrollmod objects
	-- then pack them into the scrollmod regions wherever they can fit
	-- TODO here
	local allScrollModPLMs = table()
	for _,plmset in ipairs(self.plmsets) do
		for _,plm in ipairs(plmset.plms) do
			assert((plm.cmd == sm.plmCmdValueForName.scrollmod) == (not not plm.scrollmod))
			if plm.scrollmod then
				allScrollModPLMs:insert(plm)
			end
		end
	end
	for i=#allScrollModPLMs-1,1,-1 do
		local pi = allScrollModPLMs[i]
		for j=#allScrollModPLMs,i+1,-1 do
			local pj = allScrollModPLMs[j]
			if tablesAreEqual(pi.scrollmod, pj.scrollmod) then
				pj.scrollmod = pi.scrollmod
			end
		end
	end
	local allScrollMods = table()
	for _,plm in ipairs(allScrollModPLMs) do
		local s = plm.scrollmod
		if s then
			allScrollMods[s] = allScrollMods[s] or table()
			allScrollMods[s]:insert(plm)
		end
	end
	--]]
	-- get rid of any duplicate plmsets ... there are none by default
	for i=#self.plmsets-1,1,-1 do
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
						rs.obj.plmAddr = bit.band(0xffff, pi.addr)
						rs.ptr.plmAddr = bit.band(0xffff, pi.addr)
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
			local ptr = ffi.cast('plm_t*', rom + addr)
			plm.ptr = ptr -- now that plms are lua tables we can do this
			ptr[0] = plm:toC()
			addr = addr + ffi.sizeof'plm_t'
		end
		-- write term
		ffi.cast('uint16_t*', rom+addr)[0] = 0
		addr = addr + ffi.sizeof'uint16_t'
		assert(addr == endaddr)

		local newofs = bit.band(0xffff, plmset.addr)
		for _,rs in ipairs(plmset.roomStates) do
			if newofs ~= rs.obj.plmAddr then
				--print('updating roomstate plm from '..('%04x'):format(rs.ptr.plmAddr)..' to '..('%04x'):format(newofs))
				rs.obj.plmAddr = newofs
				rs.ptr.plmAddr = newofs
			end
		end
	end
	--]]
	-- [[ write scrollmods last, so it can fill in the holes that the plmsets can't
	-- and then update the scrollmod ptrs of the plms after
	print()
	-- now for all scrollmods
	-- write the largest ones first then the smallest, and search for subsets in the small regions
	-- if I was clever I would think of a way to have later ones search contiguously across all previous ones instead of just search each previous one at a time
	local sortedScrollMods = allScrollMods:keys():sort(function(a,b)
		return #a > #b
	end)
	local addrForScrollMod = {}
	for i=1,#sortedScrollMods do
		local scrollmod = sortedScrollMods[i]
		local n = #scrollmod
		local addr, endaddr
		-- see if we can use a previous scrollmod
		for j=1,i-1 do
			local prevScrollMod = sortedScrollMods[j]
			for k=1,#prevScrollMod - n + 1 do
				if tableSubsetsEqual(prevScrollMod, scrollmod, k, 1, n) then
					addr = addrForScrollMod[prevScrollMod] + k - 1
					endaddr = addr
					break
				end
			end
			if addr then break end
		end
		if not addr then
			-- pick a memory region
			-- write the scrollmod
			-- update the address of all plms
			addr, endaddr = plmWriteRanges:get(n)
			-- write
			copyByteArray(rom+addr, tableToByteArray(scrollmod))
		end
		-- remember
		addrForScrollMod[scrollmod] = addr
		-- update plm ptrs
		local plms = assert(allScrollMods[scrollmod])
		for _,plm in ipairs(plms) do
			assert(plm.scrollmod)
			assert(plm.cmd == sm.plmCmdValueForName.scrollmod)
			plm.args = bit.band(0xffff, addr)
			plm.ptr.args = plm.args
		end
	end
	--]]

	plmWriteRanges:print()
end

function SMMap:mapWriteEnemySpawnSets()
	local rom = self.rom

	-- preserve order
	self.enemySpawnSets:sort(function(a,b) return a.addr < b.addr end)

	-- remove any enemy spawn sets that no one points to
	for i=#self.enemySpawnSets,1,-1 do
		local spawnset = self.enemySpawnSets[i]
		if #spawnset.roomStates == 0 then
			print('removing unused enemy gfx set: '..('%04x'):format(spawnset.addr))
			self.enemySpawnSets:remove(i)
		end
	end

	-- [[ get rid of duplicate enemy spawns
	-- this currently crashes the game
	-- notice that re-writing the enemy spawns is working fine
	-- but removing the duplicates crashes as soon as the first room with monsters is encountered 
	for i=#self.enemySpawnSets-1,1,-1 do
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
					--print('enemySpawns '..piaddr..' and '..pjaddr..' are matching -- removing '..pjaddr)
					for _,rs in ipairs(table(pj.roomStates)) do
						--print('updating roomState '..('%06x'):format(ffi.cast('unsigned char*',rs.ptr)-rom))
						rs.obj.enemySpawnAddr = bit.band(0xffff, pi.addr)
						rs.ptr.enemySpawnAddr = bit.band(0xffff, pi.addr)
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
	local enemySpawnWriteRanges = WriteRange({
		-- original spawns goes up to $10ebd0, but patrickjohnston's super metroid ROM map says the end of the bank is free
		{0x108000, 0x110000},
	}, 'enemySpawn_t')
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
			if newofs ~= rs.obj.enemySpawnAddr then
				--print('updating roomstate enemySpawn addr from '..('%04x'):format(rs.ptr.enemySpawnAddr)..' to '..('%04x'):format(newofs))
				rs.obj.enemySpawnAddr = newofs
				rs.ptr.enemySpawnAddr = newofs
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

	-- remove any enemy gfx sets that no one points to
	for i=#self.enemyGFXSets,1,-1 do
		local gfxset = self.enemyGFXSets[i]
		if #gfxset.roomStates == 0 then
			print('removing unused enemy gfx set: '..('%04x'):format(gfxset.addr))
			self.enemyGFXSets:remove(i)
		end
	end

	-- [[ update enemy set
	-- I'm sure this will fail.  there's lots of mystery padding here.
	local enemyGFXWriteRanges = WriteRange({
		{0x1a0000, 0x1a12c6},
		-- next comes a debug routine, listed as $9809-$981e
		-- then next comes a routine at $9961 ...
	}, 'enemyGFX_t')
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
		local newofs = bit.bor(bit.band(0x7fff, enemyGFXSet.addr), 0x8000)
		for _,rs in ipairs(enemyGFXSet.roomStates) do
			if newofs ~= rs.obj.enemyGFXAddr then
				--print('updating roomstate enemyGFX addr from '..('%04x'):format(rs.obj.enemyGFXAddr)..' to '..('%04x'):format(newofs))
				rs.obj.enemyGFXAddr = newofs
				rs.ptr.enemyGFXAddr = newofs
			end
		end
	end
	enemyGFXWriteRanges:print()
	--]]
end

function SMMap:mapWriteTileSets(tileSetAndRoomBlockWriteRange)
	local rom = self.rom

	-- looks like there are no equal palettes
	for i=#self.tileSetPalettes,2,-1 do
		local pi = self.tileSetPalettes[i]
		for j=1,i-1 do
			local pj = self.tileSetPalettes[j]
			-- if they were equal then they should be using the same object, which should have unique instances in the array
			assert(pi.addr ~= pj.addr)
			if byteArraysAreEqual(pi.colors, pj.colors) then
print("palettes "..('%04x'):format(pj.addr)..' and '..('%04x'):format(pi.addr)..' are matching -- removing '..('%04x'):format(pi.addr))
				
				for _,tileSet in ipairs(self.tileSets) do
					if tileSet.palette == pi then
						tileSet:setPalette(pj)
						-- tileSet.obj and tileSet.ptr's paletteAddr24 are dangling here, but rewritten after the recompress
					end
				end

				self.tileSetPalettes:remove(i)
				break
			end
		end
	end

	-- none removed 
	for i=#self.tileSetPalettes,1,-1 do
		local palette = self.tileSetPalettes[i]
		if #palette.tileSets == 0 then
			print('!!! removing tileSet palette that is never referenced !!! '..('%06x'):format(palette.addr))
			self.tileSetPalettes:remove(i)
		end
	end
	

	for i=#self.tileSetTilemaps,2,-1 do
		local ti = self.tileSetTilemaps[i]
		for j=1,i-1 do
			local tj = self.tileSetTilemaps[j]
			assert(ti.addr ~= tj.addr)
			if byteArraysAreEqual(ti.data, tj.data) then
print("tilemaps "..('%04x'):format(tj.addr)..' and '..('%04x'):format(ti.addr)..' are matching -- removing '..('%04x'):format(ti.addr))
				
				for _,tileSet in ipairs(self.tileSets) do
					if tileSet.tilemap == ti then
						tileSet:setTilemap(tj)
						-- tileSet.obj and tileSet.ptr's tileAddr24 are dangling here, but rewritten after the recompress
					end
				end

				self.tileSetTilemaps:remove(i)
				break
			end
		end
	end

	-- none removed 
	for i=#self.tileSetTilemaps,1,-1 do
		local tilemap = self.tileSetTilemaps[i]
		if #tilemap.tileSets == 0 then
			print('!!! removing tileSet tilemap that is never referenced !!! '..('%06x'):format(tilemap.addr))
			self.tileSetTilemaps:remove(i)
		end
	end


	for i=#self.tileSetGraphicsTileSets,2,-1 do
		local gi = self.tileSetGraphicsTileSets[i]
		for j=1,i-1 do
			local gj = self.tileSetGraphicsTileSets[j]
			assert(gi.addr ~= gj.addr)
			if byteArraysAreEqual(gi.data, gj.data) then
print("graphicsTileSets "..('%04x'):format(gj.addr)..' and '..('%04x'):format(gi.addr)..' are matching -- removing '..('%04x'):format(gi.addr))
				
				for _,tileSet in ipairs(self.tileSets) do
					if tileSet.graphicsTileSet == gi then
						tileSet:setGraphicsTileSet(gj)
						-- tileSet.obj and tileSet.ptr's graphicsTileAddr24 are dangling here, but rewritten after the recompress
					end
				end

				self.tileSetGraphicsTileSets:remove(i)
				break
			end
		end
	end

	-- none removed 
	for i=#self.tileSetGraphicsTileSets,1,-1 do
		local graphicsTileSet = self.tileSetGraphicsTileSets[i]
		if #graphicsTileSet.tileSets == 0 then
			print('!!! removing tileSet graphicsTileSet that is never referenced !!! '..('%06x'):format(graphicsTileSet.addr))
			self.tileSetGraphicsTileSets:remove(i)
		end
	end


	-- how should I deal with the tilemapElem_t's or the graphicsTile_t's?
	-- I'm lumping them together but maybe I shouldn't
--[=[
	local tileSetWriteRanges = WriteRange({
--[[
	tileWriteRanges:
		{0x1d4629, 0x20b6f6}, 		-- tileSet graphicsTile_t lz data
		{0x20b6f6, 0x212d7c}, 	-- tileSet tilemapElem_t lz data
		-- tileSet tilemapElem_t's go here
		{0x212d7c, 0x2142bb},		-- tileSet palette rgb_t lz data
--]]
		{0x1d4629, 0x2142bb},		-- the end of this is the beginning of a roomblock lz data range, soo ... combine?
	}, 'tileSet tilemap+graphicsTileSet+palette lz data')
--]=]	
	local totalOriginalCompressedSize = 0
	local totalRecompressedSize = 0

	for _,tilemap in ipairs(self.tileSetTilemaps) do
		local data = tilemap.data
		local recompressed = lz.compress(data)
		totalOriginalCompressedSize = totalOriginalCompressedSize + tilemap.compressedSize
		totalRecompressedSize = totalRecompressedSize + ffi.sizeof(recompressed)
		data = recompressed
		tilemap.compressedSize = ffi.sizeof(recompressed)
		local fromaddr, toaddr = tileSetAndRoomBlockWriteRange:get(ffi.sizeof(data))
		ffi.copy(rom + fromaddr, data, ffi.sizeof(data))
		tilemap.addr = fromaddr
		-- update anything dependent on this tilemap
		for _,tileSet in ipairs(tilemap.tileSets) do
			tileSet.obj.tileAddr24:frompc(fromaddr)

			-- TODO don't do this here, do this on write later
			tileSet.ptr.tileAddr24.bank = tileSet.obj.tileAddr24.bank
			tileSet.ptr.tileAddr24.ofs = tileSet.obj.tileAddr24.ofs
		end
	end

	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		local data = graphicsTileSet.data
		local recompressed = lz.compress(data)
		totalOriginalCompressedSize = totalOriginalCompressedSize + graphicsTileSet.compressedSize
		totalRecompressedSize = totalRecompressedSize + ffi.sizeof(recompressed)
		data = recompressed
		graphicsTileSet.compressedSize = ffi.sizeof(recompressed)
		local fromaddr, toaddr = tileSetAndRoomBlockWriteRange:get(ffi.sizeof(data))
		ffi.copy(rom + fromaddr, data, ffi.sizeof(data))
		graphicsTileSet.addr = fromaddr
		-- update anything dependent on this graphicsTileSet
		for _,tileSet in ipairs(graphicsTileSet.tileSets) do
			tileSet.obj.graphicsTileAddr24:frompc(fromaddr)

			-- TODO don't do this here, do this on write later
			tileSet.ptr.graphicsTileAddr24.bank = tileSet.obj.graphicsTileAddr24.bank
			tileSet.ptr.graphicsTileAddr24.ofs = tileSet.obj.graphicsTileAddr24.ofs
		end
	end

	for _,palette in ipairs(self.tileSetPalettes) do
		local data = palette.colors
		local recompressed = lz.compress(data)
		totalOriginalCompressedSize = totalOriginalCompressedSize + palette.compressedSize
		totalRecompressedSize = totalRecompressedSize + ffi.sizeof(recompressed)
		data = recompressed
		palette.compressedSize = ffi.sizeof(recompressed)
		local fromaddr, toaddr = tileSetAndRoomBlockWriteRange:get(ffi.sizeof(data))
		ffi.copy(rom + fromaddr, data, ffi.sizeof(data))
		palette.addr = fromaddr
		-- update anything dependent on this palette
		for _,tileSet in ipairs(palette.tileSets) do
			tileSet.obj.paletteAddr24:frompc(fromaddr)

			-- TODO don't do this here, do this on write later
			tileSet.ptr.paletteAddr24.bank = tileSet.obj.paletteAddr24.bank
			tileSet.ptr.paletteAddr24.ofs = tileSet.obj.paletteAddr24.ofs
		end
	end

	print()
	print('tileSet tilemap + graphicsTileSet + palettes recompressed from '..totalOriginalCompressedSize..' to '..totalRecompressedSize..
		', saving '..(totalOriginalCompressedSize - totalRecompressedSize)..' bytes '
		..'(new data is '..math.floor(totalRecompressedSize/totalOriginalCompressedSize*100)..'% of original size)')

	-- remove duplicate tileSet_t's 
	for i=#self.tileSets,2,-1 do
		local ti = self.tileSets[i]
		for j=1,#self.tileSets-1 do
			local tj = self.tileSets[j]
			if byteArraysAreEqual(ti.obj.ptr, tj.obj.ptr) then
print("tileSet_t "..('%02x'):format(tj.index)..' and '..('%02x'):format(ti.index)..' are matching -- removing '..('%02x'):format(ti.index))
				-- TODO
			end
		end
	end

--[[
tileSet memory ranges [incl,excl)

[0x07e6a2, 0x07e7a7) = tileSet_t's

[0x1c8000, 0x1ca09d) = common room graphicsTile_t lz data
[0x1ca09d, 0x1ca634) = common room tilemapElem_t lz data

and then don't forget the bg tilemapElem_t's, which has some pockets in the data
--]]
end


function SMMap:mapWriteRooms(roomBankWriteRanges)
	local rom = self.rom

	local roomWriteRanges = WriteRange({
		 {0x0791f8, 0x07b76a},     -- rooms of regions 0-2
		 
		 -- {0x07b76a, 0x07b971}, 	-- bg_t's (all padding in here isn't used)
		 -- {0x07b971, 0x07ba37},	-- door codes
		 -- {0x07ba37, 0x07bd07},	-- bg_t's (all padding in here isn't used)
		 -- {0x07bd07, 0x07be3f},	-- door code
		 -- {0x07be3f, 0x07bf9e}	-- bg_t's.  within this is a 54 bytes padding, 27 of these bytes is a set of bg_t's that points from room 02/3d, which is unfinished
		 -- {0x07bf9e, 0x07c116},	-- door code
		 -- {0x07c116, 0x07c215},	-- 255 bytes of main asm routines
		 -- {0x07c215, 0x07c8c7},	-- plm_t's
		 -- {0x07c8c7, 0x07c8f6},	-- layer handling code
		 
		 -- these two functions are not pointed to by any rooms
		 --  but their functions are referenced by the code at c8dd, 
		 -- so this is reserved, can't be moved (without updating the code of c8dd as well)
		 --  which is the layerHandlingAddr of room 04/37, draygon's room
		 -- in other words, without some deep code introspection (and maybe some sentience)
		 --  this can't be automatically moved around and updated
		 -- {0x07c8f6, 0x07c8fc},	-- 6 bytes of draygon's room pausing code
		 -- {0x07c8fc, 0x07c90a,	-- 14 bytes of draygon's room unpausing code 
		 
		 -- {0x07c90a, 0x07c98e},	-- layer handling code
		 	{0x07c98e, 0x07e0fd},   -- rooms of regions 3-6
-- TODO make sure 06/00 is at $07c96e, or update whatever points to Ceres
		 -- {0x07e0fd, 0x07e1d8},	-- bg_t's TODO verifying padding at 0x07e132 isn't used
		 -- {0x07e1d8, 0x07e248},	-- door code
		 -- {0x07e248, 0x07e26c},	-- bg_t
		 -- {0x07e26c, 0x07e3e8},	-- door code (with padding at a few places)
		 -- {0x07e3e8, 0x07e4c0},	-- bg_t
		 -- {0x07e4c0, 0x07e51f},	-- door code
		 -- {0x07e51f, 0x07e5e6},	-- 199 bytes of padding
		 -- {0x07e5e6, 0x07e6a2},	-- room select code (with some padding)
		 -- {0x07e6a2, 0x07e7a7},	-- tileSet_t's
		 {0x07e82c, 0x07e85a},     -- single mdb of region 7
		 -- then comes door code
	}, 'room_t')


	-- compress roomstates ...
	-- for all plm scrollmods, if they have matching data then combine their addresses

	-- sort rooms by region and by index
	self.rooms:sort(function(a,b)
		-- [[
		if a.obj.region < b.obj.region then return true end
		if a.obj.region > b.obj.region then return false end
		return a.obj.index < b.obj.index
		--]]
		--[[
		return a.addr < b.addr
		--]]
	end)
	-- grab and write new regions
	for _,m in ipairs(self.rooms) do
		print('room size '..('0x%x'):format(ffi.sizeof'room_t'))	
		local totalSize = ffi.sizeof'room_t'
		for _,rs in ipairs(m.roomStates) do
			print(rs.select_ctype..' size '..('0x%x'):format(ffi.sizeof(rs.select_ctype)))	
			totalSize = totalSize + ffi.sizeof(rs.select_ctype)
			print('roomstate_t size '..('0x%x'):format(ffi.sizeof'roomstate_t'))	
			totalSize = totalSize + ffi.sizeof'roomstate_t'
		end
		print('dooraddr size '..('0x%x'):format(2 * #m.doors))	
		totalSize = totalSize + 2 * #m.doors
		for _,rs in ipairs(m.roomStates) do
			if rs.roomvar then
				print('roomvar size '..('0x%x'):format(#rs.roomvar))	
				totalSize = totalSize + #rs.roomvar
			end
		end
		for i,rs in ipairs(m.roomStates) do
			if rs.scrollData then
				local matches
				for j=1,i-1 do
					local rs2 = m.roomStates[j]
					if tablesAreEqual(rs.scrollData, rs2.scrollData) then
						matches = true
						break
					end
				end
				if not matches then
					print('scroll size '..('0x%x'):format(m.obj.width * m.obj.height))	
					totalSize = totalSize + m.obj.width * m.obj.height
				end
			end
		end
	
		-- write m.obj
		local reqAddr
--		if m.obj.region == 0 and m.obj.index == 0 then reqAddr = 0x0791f8 end
--		if m.obj.region == 6 and m.obj.index == 0 then reqAddr = 0x07c96e end
		local addr, endaddr = roomWriteRanges:get(totalSize, reqAddr)
		local ptr = rom + addr
		m.ptr = ffi.cast('room_t*', ptr)
		m.ptr[0] = m.obj
		m.addr = bit.band(addr, 0xffff)	-- TODO get rid of this field and only use m.ptr
		ptr = ptr + ffi.sizeof'room_t'

		-- write m.roomStates[1..n].select
		for _,rs in ipairs(m.roomStates) do
			local selptr = ffi.cast(rs.select_ctype..'*', ptr)
			selptr[0] = rs.select
			rs.select_ptr = selptr
			ptr = ptr + ffi.sizeof(rs.select_ctype)
		end
		-- write m.roomStates[n..1].obj (reverse order ... last roomselect matches first roomstate, and that's why last roomselect has no pointer.  the others do have roomstate addrs, but maybe keep the roomstates reverse-sequential just in case) 
		--		update roomstate2_t's and roomstate3_t's as you do this
		for i=#m.roomStates,1,-1 do
			local rs = m.roomStates[i]
			local roomStateAddr = bit.band(0xffff, ptr - rom)
			local rsptr = ffi.cast('roomstate_t*', ptr)
			rsptr[0] = rs.obj
			rs.ptr = rsptr
			if rs.select_ctype ~= 'roomselect1_t' then
				rs.select_ptr.roomStateAddr = roomStateAddr		-- update previous write in rom
				rs.select.roomStateAddr = roomStateAddr		-- update POD
			else
				assert(i == #m.roomStates, "expected only roomselect1_t to appear last, but found one not last for room "..('%02x/%02x'):format(m.obj.region, m.obj.index))
			end
			ptr = ptr + ffi.sizeof'roomstate_t'
		end
		
		-- write the dooraddrs: m.doors[i].addr.  terminator: 00 80.  reuse matching dooraddr sets between rooms.
		--		update m.obj.doors
		m.obj.doors = bit.band(0xffff, ptr-rom)
		m.ptr.doors = m.obj.doors
		for _,door in ipairs(m.doors) do
			ffi.cast('uint16_t*', ptr)[0] = door.addr
			-- right now door.ptr points to the door_t object elsewhere, not to the ptr of the ptr to the door_t
			ptr = ptr + ffi.sizeof'uint16_t'
		end
		
		-- write m.roomStates[1..n].roomvar (only for grey torizo room)
		--		update m.roomStates[1..n].ptr.roomvarAddr
		for _,rs in ipairs(m.roomStates) do
			if rs.roomvar then
				rs.obj.roomvarAddr = bit.band(0xffff, ptr-rom)
				rs.ptr.roomvarAddr = rs.obj.roomvarAddr
				for _,c in ipairs(rs.roomvar) do
					ptr[0] = c
					ptr = ptr + 1
				end
			end
		end
		
		-- write m.roomStates[1..n].scrollData
		--		update m.roomStates[1..n].obj.scrollAddr
		for i,rs in ipairs(m.roomStates) do
			if rs.scrollData then
				assert(rs.obj.scrollAddr > 1 and rs.obj.scrollAddr ~= 0x8000)
				assert(#rs.scrollData == m.obj.width * m.obj.height)
				local matches
				for j=1,i-1 do
					local rs2 = m.roomStates[j]
					if rs2.scrollData then
						if tablesAreEqual(rs.scrollData, rs2.scrollData) then
							matches = rs2.obj.scrollAddr
							break
						end
					end	
				end
				if matches then
					rs.obj.scrollAddr = matches
					rs.ptr.scrollAddr = matches
				else
					rs.obj.scrollAddr = bit.band(0xffff, ptr-rom)
					rs.ptr.scrollAddr = rs.obj.scrollAddr
					for i=1,m.obj.width * m.obj.height do
						ptr[0] = rs.scrollData[i]
						ptr = ptr + 1
					end
				end
			end
		end

		assert(endaddr == ptr - rom)
	end

	-- update m.doors[1..n].ptr.destRoomAddr
	for _,m in ipairs(self.rooms) do
		for _,door in ipairs(m.doors) do
			if door.ctype == 'door_t' then
				door.ptr.destRoomAddr = bit.band(0xffff, ffi.cast('uint8_t*', door.destRoom.ptr) - rom)
			end
		end
	end

	for _,m in ipairs(self.rooms) do
		assert(m.ptr.region == m.obj.region, "regions dont match for room "..('%02x/%02x'):format(m.obj.region, m.obj.index))
	end
	-- if you remove rooms but forget to remove them from rooms then you could end up here ... 
	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			local m = rs.room
			assert(m.ptr.region == m.obj.region, "regions dont match for room:\nptr "..m.ptr[0].."\nobj "..m.obj)
		end
	end
	
	roomWriteRanges:print()
end

function SMMap:mapWriteRoomBlocks(writeRange)
	local rom = self.rom
	
	-- remove any roomblocks that no one is using
	for i=#self.roomblocks,1,-1 do
		local rb = self.roomblocks[i]
		if #rb.rooms == 0 then
			print('removing unused room blocks at: '..('%04x'):format(rb.addr))
			self.roomblocks:remove(i)
		end
	end

--[==[	
	-- [[ write back compressed data
	local roomBlockWriteRanges = WriteRange({
		--[=[ there are some bytes outside compressed regions but between a few roomdatas
		-- the metroid rom map says these are a part of the room block data
		-- this includes those breaks
		{0x2142bb, 0x235d77},
		{0x235ee0, 0x244da9},
		{0x24559c, 0x272503},
		{0x272823, 0x27322e},
		--]=]
		-- [=[ and this doesn't -- one giant contiguous region
		{0x2142bb, 0x278000},
		--]=]
	}, 'roomblocks')
--]==]	
	-- ... reduces to 56% of the original compressed data
	-- but goes slow
	local totalOriginalCompressedSize = 0
	local totalRecompressedSize = 0
	print()
	for _,roomBlockData in ipairs(self.roomblocks) do
		local data = roomBlockData:getData()
		local recompressed = lz.compress(data)
	--	print('recompressed size: '..ffi.sizeof(recompressed)..' vs original compressed size '..roomBlockData.compressedSize)
	-- this doesn't matter
	--	assert(ffi.sizeof(recompressed) <= roomBlockData.compressedSize, "recompressed to a larger size than the original.  recompressed "..ffi.sizeof(recompressed).." vs original "..roomBlockData.compressedSize)
		totalOriginalCompressedSize = totalOriginalCompressedSize + roomBlockData.compressedSize
		totalRecompressedSize = totalRecompressedSize + ffi.sizeof(recompressed)
		
		data = recompressed
		roomBlockData.compressedSize = ffi.sizeof(recompressed)
		--[=[ now write back to the original location at addr
		ffi.copy(rom + roomBlockData.addr, data, ffi.sizeof(data))
		--]=]
		-- [=[ write back at a contiguous location
		-- (don't forget to update all roomstate_t's roomBlockAddr24.bank:roomBlockAddr24.ofs's to point to this
		-- TODO this currently messes up the scroll change in wrecked ship, when you go to the left to get the missile in the spike room
		local fromaddr, toaddr = writeRange:get(ffi.sizeof(data))

		-- do the write
		ffi.copy(rom + fromaddr, data, ffi.sizeof(data))
		-- update roomblock addr
		roomBlockData.addr = fromaddr
		-- update any roomstate_t's that point to this data
		for _,rs in ipairs(roomBlockData.roomStates) do
			rs.obj.roomBlockAddr24:frompc(roomBlockData.addr)
			rs.ptr.roomBlockAddr24.bank = rs.obj.roomBlockAddr24.bank
			rs.ptr.roomBlockAddr24.ofs = rs.obj.roomBlockAddr24.ofs
		end
		--]=]

	--[=[ verify that compression works by decompressing and re-compressing
		local data2, compressedSize2 = lz.decompress(rom, roomBlockData.addr, 0x10000)
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

	--]]
end

-- write back changes to the ROM
-- right now my structures are mixed between ptrs and by-value copied objects
-- so TODO eventually have all ROM writing in this routine
function SMMap:mapWrite()
	-- TODO everything in 3 steps
	-- 0) don't use ptrs before this at all, only objs and copied data
	-- 1) request all ranges up front
	-- 2) update all addrs in all objs based on the ptrs
	-- 3) write last


	local roomBankWriteRanges = WriteRange({
		{0x78000, 0x79194},		-- plms
		-- 9194-91f7 = asm
		{0x791f8, 0x7b76a},		-- rooms of regions 0-2
		-- b76a-b970 = 'library backgrounds'
		-- b971-c116 = door asm
		-- c117-c214 = asm
		{0x7c215, 0x7c8c7},
		-- c8c7-c98d = layer asm, which is L12 data
		{0x7c98e, 0x7e0fd},	-- rooms of regions 3-6
		-- e1d8-e513 = door asm 
		-- e514-e689 = room select asm.  notice these call one another, so you can't just omve them around willy nilly
		-- e68a-e82b = more tables and stuff
		{0x7e82c, 0x7e881},	-- within this region is e85b-e87e, which is assumed to be unused ...
		-- e88f-e99a = setup asm
		{0x7e99b, 0x80000},	-- free space: 
	
-- TODO make sure 06/00 is at $07c96e, or update whatever points to Ceres
		-- then comes door code
	})
	
	-- write these before writing roomstates
	do
		-- this is how the data is ordered in the rom:
		local tileSetAndRoomBlockWriteRange = WriteRange({
			-- NOTICE from 0x1c8000 to 1ca633 is common room compressed graphicsTile_t then tilemapElem_t
			-- then comes the bg tilemapElem_t's, but they have random padding in there,
			-- and immediately after comes this:
			-- so I'm a step away from just writing everything from 0x1c8000 to 0x278000
			{0x1d4629, 0x278000},
		}, 'tileSet tilemap+graphicsTileSet+palette lz data, and roomblocks lz data')
		self:mapWriteTileSets(tileSetAndRoomBlockWriteRange)		-- tileSet_t's...
		self:mapWriteRoomBlocks(tileSetAndRoomBlockWriteRange)		-- roomBlockData ...
		
		-- output memory ranges
		tileSetAndRoomBlockWriteRange:print()
	end

	roomBankWriteRanges.name = 'plm_t'
	self:mapWritePLMs(roomBankWriteRanges)

	-- do this before writing anything that uses enemy spawn sets
	self:mapWriteEnemyGFXSets()
	self:mapWriteEnemySpawnSets()

	-- TODO recompress and write bg_t's
	-- but first I need to decode them all

	roomBankWriteRanges.name = 'room_t'
	self:mapWriteRooms(roomBankWriteRanges)
	
	roomBankWriteRanges:print()


	-- now that we've moved some rooms around, update them in the loading station and demo section
	for _,ls in ipairs(self.loadStations) do
		if ls.room then
			ls.ptr.roomAddr = ls.room:getAddr(self)
--print("updating loadStation addr "..ls.ptr.roomAddr)
		end
	end

	-- TODO same with demo?
end


return SMMap
