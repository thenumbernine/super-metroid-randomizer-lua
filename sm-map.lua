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
local table = require 'ext.table'
local class = require 'ext.class'
local range = require 'ext.range'
local tolua = require 'ext.tolua'
local math = require 'ext.math'
local template = require 'template'
local Image = require 'image'
local struct = require 'super_metroid_randomizer.smstruct'
local lz = require 'super_metroid_randomizer.lz'
local WriteRange = require 'super_metroid_randomizer.writerange'
local config = require 'super_metroid_randomizer.config'

local Blob = require 'super_metroid_randomizer.blob'
local Palette = require 'super_metroid_randomizer.palette'

local SMGraphics = require 'super_metroid_randomizer.sm-graphics'
local graphicsTileSizeInPixels = SMGraphics.graphicsTileSizeInPixels 
local graphicsTileSizeInBytes = SMGraphics.graphicsTileSizeInBytes 

local pc = require 'super_metroid_randomizer.pc'
local topc = pc.to
local frompc = pc.from

local tableSubsetsEqual = require 'super_metroid_randomizer.util'.tableSubsetsEqual
local tablesAreEqual = require 'super_metroid_randomizer.util'.tablesAreEqual
local byteArraysAreEqual = require 'super_metroid_randomizer.util'.byteArraysAreEqual
local tableToByteArray = require 'super_metroid_randomizer.util'.tableToByteArray


local SMMap = {}


SMMap.fx1Bank = 0x83
SMMap.doorBank = 0x83

-- each room and its roomstates, dooraddrs, and scrolldata are stored grouped together
SMMap.roomBank = 0x8f
SMMap.roomStateBank = 0x8f	-- bank for roomselect_t.roomStatePageOffset
SMMap.doorAddrBank = 0x8f	-- bank for room_t.doors
SMMap.scrollBank = 0x8f		-- if scrolldata is stored next to room, roomstate, and dooraddr, then why does it have a separate bank?
-- then between groups of rooms (and their content) are groups of bg_t's and doorcodes
SMMap.bgBank = 0x8f			
SMMap.doorCodeBank = 0x8f
-- then comes a group o fplms, and then comes a group of layer handling
SMMap.layerHandlingBank = 0x8f
SMMap.plmBank = 0x8f

-- and then we go back to some more rooms

SMMap.enemySpawnBank = 0xa1
SMMap.enemyGFXBank = 0xb4

local loadStationBank = 0x80
local loadStationRegionTableOffset = 0xc4b5
local loadStationRegionCount = 8
-- if I want to move this, then where is 80:c4b5 referenced in code?  at 80:c458
local loadStationEndOffset = 0xcd07	-- don't go past here when writing

local commonRoomGraphicsTileAddr24 = ffi.new('addr24_t', {bank=0xb9, ofs=0x8000})
assert(commonRoomGraphicsTileAddr24:topc() == 0x1c8000)

local commonRoomTilemapAddr24 = ffi.new('addr24_t', {bank=0xb9, ofs=0xa09d})
assert(commonRoomTilemapAddr24:topc() == 0x1ca09d)

-- where is b9:a09d used in code:
-- TODO use 3 refs instead of 2, like mapKraidBGTilemap?
local commonRoomTilemapAddrLocs = table{
	-- ofsaddr is 16-bit, bankaddr is 8-bit
	{ofsaddr=topc(0x82, 0xe841), bankaddr=topc(0x82, 0xe83d)},
	{ofsaddr=topc(0x82, 0xeaf1), bankaddr=topc(0x82, 0xeaed)},
}

local mapKraidBGTilemapTopAddrLoc = {ofs1addr=topc(0xa7, 0xaac9), ofs2addr=topc(0xa7, 0xaacf), bankaddr=topc(0xa7, 0xaad5)}
local mapKraidBGTilemapBottomAddrLoc = {ofs1addr=topc(0xa7, 0xaaeb), ofs2addr=topc(0xa7, 0xaaf1), bankaddr=topc(0xa7, 0xaaf7)}


local blocksPerRoom = require 'super_metroid_randomizer.roomblocks'.blocksPerRoom
local blockSizeInPixels = 16
local roomSizeInPixels = blocksPerRoom * blockSizeInPixels

SMMap.blockSizeInPixels = blockSizeInPixels
SMMap.blocksPerRoom = blocksPerRoom 
SMMap.roomSizeInPixels = roomSizeInPixels 

local numMode7Tiles = 256
local mode7sizeInGraphicTiles = 128
assert(mode7sizeInGraphicTiles * mode7sizeInGraphicTiles == numMode7Tiles * graphicsTileSizeInPixels * graphicsTileSizeInPixels)


local debugImageBlockSizeInPixels = 4
local debugImageRoomSizeInPixels = blocksPerRoom * debugImageBlockSizeInPixels


function SMMap:mapGetFullMapInfoForMD5(md5)
	local version = ({
		['21f3e98df4780ee1c667b84e57d88675'] = 'original',	-- JU
		['3d64f89499a403d17d530388854a7da5'] = 'original',	-- E
		['f24904a32f1f6fc40f5be39086a7fa7c'] = 'original',	-- JU with some memcheck and pal bits changed
		['6092a3ea09347e1800e330ea27efbef2'] = 'vitality',
	})[md5]

	if version == 'original' then
		return {
			fullMapWidthInBlocks = 68,
			fullMapHeightInBlocks = 58,
			ofsPerRegion = {
				function(m) 
					--[[
					special case for Crateria right of Wrecked Ship
					ok how to generalize this?
					one way is to recursively build the room locations in the overworld map picture
					however you then run into trouble with lifts that can be arbitrary heights

					so next , how about (certain?) doors are given arbitrary spacing
					and then we try to adjust and minimize that spacing such that all rooms fit together?
					--]]
					if m:obj().region == 0	-- Crateria
					and m:obj().x > 45 
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
			},
			-- to prevent overlap
			-- honestly, excluding the empty background tiles below fixes most of this
			-- but for the solid tile output, I still want to see those types, so that's why I added this code 
			-- what regions on the map to exclude
			mapDrawExcludeMapBlocks = {
				[0x000] = {
					{0, 0, 2, 2},			-- crateria intro, out of bounds backgrounds
					{0, 3, 2, 1},			-- "
				},
				[0x002] = {					-- crateria first room
					{0, 1, 1, 2},			-- overlaps the 1st save room
					{0, 4, 1, 1},
					{2, 1, 1, 2},
					{2, 4, 3, 1},
					{4, 1, 1, 1},
				},
				[0x005] = {{6, 2, 2, 2}},	-- crateria big room to the right
				[0x009] = {{0, 0, 7, 4}},
				[0x007] = {					-- crateria lift to red brinstar
					{0, 1, 1, 2},
					{2, 1, 1, 2},
				},			
				[0x012] = {					-- crateria down hall to mother brain overlapping mother brain 1st room
					{0, 7, 1, 1},
					{2, 1, 1, 1},
					{2, 6, 1, 1},
					{2, 8, 1, 1},
				},
				[0x013] = {{1, 1, 1, 1}},	-- crateria old mother brain room
				[0x01d] = {					-- crateria speed boost to super missile secret
					{2, 1, 1, 1},
					{2, 6, 1, 1},
				},
				[0x108] = {{0, 1, 4, 5}},	-- brinstar pink speed fall room
				[0x109] = {
					{0, 0, 1, 1},			-- brinstar pink big room
					{0, 1, 2, 2},			-- "
				},
				[0x10e] = {{0, 0, 5, 2}},	-- brinstar blue first room
				[0x113] = {{2, 0, 3, 1}},	-- brinstar bottom flea room
				[0x124] = {{1, 4, 1, 1}},	-- red room ascending to lift to brinstar, blocks save to the right
				[0x12c] = {{0, 1, 1, 1}},	-- brinstar kraid fly room
				[0x134] = {{2, 1, 1, 1}},	-- brinstar flea e-tank room in kraid area
				[0x204] = {
					{0, 0, 3, 3},	-- norfair speed room to ice
					{4, 3, 3, 1},	-- "
				},
				[0x207] = {
					{1, 0, 1, 1},	-- norfair room before ice
					{1, 2, 1, 1},	-- "
				},
				[0x214] = {{5, 0, 3, 2}},	-- norfair room before grappling
				[0x217] = {{0, 3, 1, 1}},	-- norfair grappling room
				[0x221] = {{0, 0, 2, 2}},	-- norfair lava rise room run to wave
				[0x225] = {{3, 2, 1, 1}},	-- norfair entrance to lower norfair lava swim, lower right corner occuldes room 2-3c, even though there are gfx tiles here
				[0x235] = {{2, 0, 1, 1}},	-- chozo morph to lower acid room, upper right overlaps with room to the right
				[0x236] = {{5, 0, 3, 2}},	-- norfair lower first room, occludes lava jump entrance to lower norfair
				[0x23e] = {{0, 0, 2, 3}},	-- norfair lower return from gold chozo loop
				[0x245] = {{1, 0, 2, 4}},	-- norfair room after acid raise run room, upper right blocks room to the right
				[0x248] = {{0, 0, 1, 2}},	-- norfair lower escape last room
				[0x24b] = {					-- norfair lower escape fireflea room
					{0, 1, 1, 5},
					{2, 0, 1, 1},
				},
				[0x300] = {
					{0, 0, 2, 1},			-- wrecked ship bowling chozo room
					{0, 2, 1, 1},			-- "
				},
				[0x304] = {					-- wrecked ship main shaft
					{0, 0, 4, 5},
					{0, 6, 3, 1},
					{0, 7, 4, 1},
					{5, 7, 1, 1},
					{5, 0, 1, 6},
				},
				[0x403] = {{1, 1, 3, 1}},	-- maridia fly and yellow blob room at the bottom
				[0x404] = {
					{2, 3, 1, 2},
					{2, 7, 1, 1},			-- maridia big climb upper left room, block over its door right to crabs 
				},
				[0x406] = {{0, 0, 1, 2}},	-- maridia turtle room
				[0x408] = {					-- maridia balloon grappling room
					{0, 3, 1, 1},
					{5, 3, 1, 1},
				},
				[0x40a] = {{1, 1, 1, 2}},	-- maridia far upper left room
				[0x40b] = {{1, 0, 3, 1}},	-- maridia room before far upper left room
				[0x40c] = {{1, 0, 1, 3}},	-- maridia purple vertical shaft with crabs
				[0x40d] = {{3, 2, 1, 1}},	-- maridia top room to items
				[0x414] = {{0, 0, 1, 2}},	-- maridia top room to plasma
				[0x426] = {{1, 0, 1, 1}},	-- maridia springball room
				[0x42a] = {{1, 1, 1, 2}},	-- maridia room to draygon
				[0x431] = {{1, 0, 4, 2}},	-- maridia mocktroid and big shell guy area
			},
		}
	elseif version == 'vitality' then
		return {
			fullMapWidthInBlocks = 103,
			fullMapHeightInBlocks = 76,
			ofsPerRegion = {
				function(m) return 21,	43	end,		-- region 0
				function(m) return 15,	23	end,		-- region 1
				function(m) return 57,	12	end,		-- region 2
				function(m) return 16,	-1	end,		-- region 3
				function(m) return -27,	28	end,		-- region 4
				function(m) return 40,	59	end,		-- region 5
				function(m) return 0,	0	end,		-- region 6
				function(m) return 0,	0	end,		-- region 7
			},
			mapDrawExcludeMapBlocks = {},
		}
	else
		return {
			fullMapWidthInBlocks = 80,
			fullMapHeightInBlocks = 58,
			ofsPerRegion = range(8):mapi(function(i)
				return function(m) 
					return bit.rshift(i,1) * 20,
						bit.band(i,1) * 20
				end
			end),
			mapDrawExcludeMapBlocks = {},
		}
	end
end



-- plm = 'post-load modification'
-- this is a non-enemy object in a map.
local plm_t = struct{
	name = 'plm_t',
	fields = {
		{cmd = 'uint16_t'},			-- TODO rename to plmPageOffset?  but that is ambiguous with this struct's name.  How to keep this analogous with enemyPageOffset vs enemyClass_t vs enemySpawn_t ... maybe rename this to plmSpawn_t ? hmm...
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
		{enemyPageOffset = 'uint16_t'},	-- matches enemies[].addr, instance of enemyClass_t
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
		{enemyPageOffset = 'uint16_t'},	-- matches enemies[].addr
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
		{doorPageOffset = 'uint16_t'},			-- 0
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

-- http://patrickjohnston.org/bank/80
local loadStation_t = struct{
	name = 'loadStation_t',
	fields = {
		{roomPageOffset = 'uint16_t'},
		{doorPageOffset = 'uint16_t'},
		{doorID = 'uint16_t'},	-- index when saving door open flags 
		{screenX = 'uint16_t'},
		{screenY = 'uint16_t'},
		-- TODO do door_t and demoRoom_t match this structure?
		{offsetY = 'uint16_t'},	-- relative to top
		{offsetX = 'uint16_t'},	-- relative to center
	},
}
SMMap.loadStation_t = loadStation_t

-- http://patrickjohnston.org/bank/82
local demoRoom_t = struct{
	name = 'demoRoom_t',
	fields = {
		{roomPageOffset = 'uint16_t'},
		{doorPageOffset = 'uint16_t'},
		{doorID = 'uint16_t'},	-- index when saving door open flags
		{screenX = 'uint16_t'},
		{screenY = 'uint16_t'},
		{offsetX = 'uint16_t'},
		{offsetY = 'uint16_t'},
		{demoLength = 'uint16_t'},
		{codePageOffset = 'uint16_t'},
	},
}

local tileSetCount = 29	-- this is the # that are used in metroid.  hardcoded?

--[[
just before this are the tileSets
why are the pointers into the table stored *after* the table?

just before that, from e68a-e6a2, are a list of offsets to door-closing PLMs
--]]
local tileSetOffsetsAddr = topc(0x8f, 0xe7a7)

-- NOTICE this is just used for testing to see if it moved
-- since this info is stored in the tileSetOffsetsAddr[] data
local tileSetOrigBaseAddr = topc(0x8f, 0xe6a2)


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
	boss_chozo_statue = 0xd6ea,	-- 00/15, 00/15

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


local Room = require 'super_metroid_randomizer.room'
SMMap.Room = Room

SMMap.RoomState = require 'super_metroid_randomizer.roomstate'

local PLM = require 'super_metroid_randomizer.plm'
SMMap.PLM = PLM


local PLMSet = class()

function PLMSet:init(args)
	self.addr = args.addr	--optional
	self.plms = table(args.plms)
	self.roomStates = table()
end


local Door = require 'super_metroid_randomizer.door'
SMMap.Door = Door

function SMMap:mapAddDoor(addr)
	if addr then
		for _,door in ipairs(self.doors) do
			if door.addr == addr then return door end
		end
	end
	local door = Door{sm=self, addr=addr}
	self.doors:insert(door)
	return door
end


--[[
bg tilemap.size is 0x800 / 2048 or 0x1000 / 4096
with 2 bytes per tilemapElem_t's, that means
most are tilemap.size==0x800 <=> uint16_t tilemapElem[height=32][width=32]
some are tilemap.size==0x1000 <=> uint16_t tilemapElem[height=64][width=32]
--]]
local BGTilemap = class(Blob)
BGTilemap.type = 'tilemapElem_t'
BGTilemap.compressed = true
BGTilemap.width = 32
function BGTilemap:init(args)
	BGTilemap.super.init(self, args)
	self.height = self.count / self.width
	assert(self.width * self.height * ffi.sizeof(self.type) == self:sizeof())
end


-- TODO make common with mapAddTileSetTilemap
function SMMap:mapAddBGTilemap(addr)
	for _,tilemap in ipairs(self.bgTilemaps) do
		if tilemap.addr == addr then return tilemap end
	end
	local tilemap = BGTilemap{sm=self, addr=addr}
	self.bgTilemaps:insert(tilemap)
	return tilemap
end

function SMMap:mapAddRoom(addr)
	for _,room in ipairs(self.rooms) do
		if room.addr == addr then return room end
	end
	assert(frompc(addr) == self.roomBank)
	
	local room = Room{sm=self, addr=addr}
	self.rooms:insert(room)
	-- TODO only do this after room is added to self.rooms or else you'll get an infinite loop
	for _,door in ipairs(room.doors) do
		door:buildRoom(self)
	end

	return room
end

-- used for adding new rooms
function SMMap:mapNewRoom(args)
	args = table(args, {sm=self}):setmetatable(nil)
	-- don't need an address, always new
	local room = Room(args)
	self.rooms:insert(room)
	return room
end

function SMMap:mapRemoveRoom(m)
	if not m then return end
	
	-- TODO in theory a room state could be pointed to by more than one room (if its roomselect's point to the same one), but in practice this is not true so I don't need to consider it
	for _,rs in ipairs(m.roomStates) do
		rs:setPLMSet(nil)
		rs:setFX1Set(nil)
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
	
	-- TODO remove all doors targetting this room?
	local i = self.rooms:find(m)
	assert(i, "tried to remove a room that I couldn't find")
	self.rooms:remove(i)
end

function SMMap:mapFindRoom(region, index)
	for _,m in ipairs(sm.rooms) do
		if m:obj().region == region and m:obj().index == index then return m end
	end
	return false, "couldn't find "..('%02x/%02x'):format(region, index)
end

function SMMap:mapClearDoorColor(region, roomIndex, x,y)
--print('searching for door to remove at '..('%02x/%02x %d,%d'):format(region, roomIndex, x,y))
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
--print('...removing door')
						rs.plmset.plms:remove(j)
					end
				end
			end
		end
	end
end


-- use this for manually adding a PLMSet without reading it from the ROM
function SMMap:mapAddPLMSet(args)
	local plmset = PLMSet(args)
	self.plmsets:insert(plmset)
	return plmset
end

-- table of all unique plm regions
-- m is only used for MemoryMap.  you have to add to plmset.rooms externally
function SMMap:mapAddPLMSetFromAddr(addr)
	local rom = self.rom
	for _,plmset in ipairs(self.plmsets) do
		if plmset.addr == addr then return plmset end
	end

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

	local plmset = self:mapAddPLMSet{
		addr = startaddr,
		plms = plms,
	}

	-- now interpret the plms...
	for _,plm in ipairs(plmset.plms) do
		if plm.cmd == self.plmCmdValueForName.scrollmod then
			local startaddr = topc(self.plmBank, plm.args)
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

	local enemySpawns = table()
	local enemiesToKill = 0
	local startaddr = addr
	if addr then
		while true do
			local ptr = ffi.cast('enemySpawn_t*', rom + addr)
			if ptr.enemyPageOffset == 0xffff then
				-- include term and enemies-to-kill
				addr = addr + 2
				break
			end
			enemySpawns:insert(ffi.new('enemySpawn_t', ptr[0]))
			addr = addr + ffi.sizeof'enemySpawn_t'
		end
		enemiesToKill = rom[addr]
		addr = addr + 1
	end

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

	local enemyGFXs = table()
	local startaddr = addr
	local name
	if addr then
		-- NOTICE the name is padded at the beginning with terms
		-- and it is 8 bytes long
		name = range(0,7):map(function(i) return string.char(rom[startaddr-8+i]) end):concat()
		while true do
			if ffi.cast('uint16_t*', rom+addr)[0] == 0xffff then break end
			local ptr = ffi.cast('enemyGFX_t*', rom+addr)
			enemyGFXs:insert(ffi.new('enemyGFX_t', ptr[0]))
			addr = addr + ffi.sizeof'enemyGFX_t'
		end
	else
		name = ('\0'):rep(8)
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

local MapBG = require 'super_metroid_randomizer.mapbg'

--[[
table of all unique bgs.
each entry has .addr and .ptr = (bg_t*)(rom+addr)
doesn't create duplicates -- returns a previous copy if it exists

b9:a634 -> $1ca634
--]]
function SMMap:mapAddBG(addr, rom)
	for _,bg in ipairs(self.bgs) do
		if bg.addr == addr then return bg end
	end
	local bg = MapBG{sm=self, addr=addr}
	self.bgs:insert(bg)
	return bg
end


local MapFX1 = class(Blob)
MapFX1.type = 'fx1_t' 
MapFX1.count = 1


local FX1Set = class()

-- like PLMSet, not quite a Blob, mabye could be, but then couldn't be resized dynamically as easily
--  (unless I merge Blob with ffi.cpp.vector ... )
function FX1Set:init(args)
	local sm = args.sm
	local rom = sm.rom
	local addr = args.addr
	
	self.addr = addr
	self.fx1s = table(args.fx1s)
	self.roomStates = table()

	if addr then
		-- some rooms use the same fx1 ptr
		-- and from there they are read in contiguous blocks until a term is encountered
		-- so I should make these fx1sets (like plmsets)
		-- unless -- another optimization -- is, if one room's fx1's (or plms) are a subset of another,
		-- then make one set and just put the subset's at the end
		-- (unless the order matters...)
		local startaddr = addr
		local retry
		while true do
			local cmd = ffi.cast('uint16_t*', rom+addr)[0]
			
			-- null sets are represented as an immediate ffff
			-- whereas sets of more than 1 value use 0000 as a term ...
			-- They can also be used to terminate a set of fx1_t
			if cmd == 0xffff then
				if #self.fx1s ~= 0 then
					print('WARNING - found a fx1set with a terminator that is not its only entry')
				end
				break
			end
			
			local fx1 = MapFX1{sm=sm, addr=addr}
			
			self.fx1s:insert(fx1)
			
			addr = addr + ffi.sizeof'fx1_t'

			-- if doorPageOffset == 0 then this is a non-specific fx1
			-- which means it is the last, general-case fx1 for the room
			-- and there only can be one
			-- so break
			if fx1:obj().doorPageOffset == 0 then break end
		end
	end
end

function SMMap:mapAddFX1Set(addr)
	for _,fx1set in ipairs(self.fx1sets) do
		if fx1set.addr == addr then return fx1set end
	end
	local fx1set = FX1Set{
		sm = self,
		addr = addr,
	}
	self.fx1sets:insert(fx1set)
	return fx1set
end


local RoomBlocks = require 'super_metroid_randomizer.roomblocks'
SMMap.RoomBlocks = RoomBlocks

-- this is the block data of the rooms
function SMMap:mapAddRoomBlockData(addr, room)
	local _,roomBlockData = self.roomblocks:find(nil, function(roomBlockData) 
		return roomBlockData.addr == addr 
	end)
	if roomBlockData then 
		-- rooms can come from separate room_t's
		-- which means they can have separate widths & heights
		-- so here, assert that their width & height matches
		assert(16 * room:obj().width == roomBlockData.width, "expected room width "..roomBlockData.width.." but got "..room:obj().width)
		assert(16 * room:obj().height == roomBlockData.height, "expected room height "..roomBlockData.height.." but got "..room:obj().height)
		return roomBlockData 
	end

	local roomBlockData = RoomBlocks{
		sm = self,
		addr = addr,
		room = room,
	}
	self.roomblocks:insert(roomBlockData)
	return roomBlockData
end

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
	
	local palette = Palette{sm=self, addr=addr, compressed=true}
	assert(palette.count == 128)	-- always true for map's palettes
	
	self.tileSetPalettes:insert(palette)
	palette.tileSets = table()
	
	return palette
end

function SMMap:mapAddTileSetGraphicsTileSet(addr)
	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		if graphicsTileSet.addr == addr then return graphicsTileSet end
	end
	
	-- NOTICE this buffer is SEPARATE of tileSet.graphicsTileVec
	-- tileSet.graphicsTileVec starts with this, pads it, appends the commonRoomGraphicsTiles,
	-- and even right now does some in-place stuff to it
	-- SO if you modify that, don't forget to update this buffer as well (somehow)
	local graphicsTileSet = Blob{
		sm = self,
		addr = addr,
		--type = 'uint8_t',
		compressed = true,
	}
	
	self.tileSetGraphicsTileSets:insert(graphicsTileSet)
	graphicsTileSet.tileSets = table()
	return graphicsTileSet
end

-- TODO make this a class and common with mapAddBGTilemap
function SMMap:mapAddTileSetTilemap(addr)
	for _,tilemap in ipairs(self.tileSetTilemaps) do
		if tilemap.addr == addr then return tilemap end
	end
	
	local tilemap = Blob{
		sm = self,
		addr = addr,
		--type = 'tilemapElem_t',
		compressed = true,
	}

	tilemap.tileSets = table()
	self.tileSetTilemaps:insert(tilemap)
	return tilemap
end

local TileSet = require 'super_metroid_randomizer.tileset'

--[[
graphicsTile_t = 8x8 rendered block
--]]
ffi.cdef(template([[
typedef struct graphicsTile_t {
	uint8_t s[<?=graphicsTileSizeInBytes?>];
} graphicsTile_t;
]], {
	graphicsTileSizeInBytes = graphicsTileSizeInBytes,
}))
assert(ffi.sizeof'graphicsTile_t' == graphicsTileSizeInBytes)

-- used by the map only so far, so i'll keep it here
function SMMap:graphicsLoadMode7(ptr, size)
	-- uint8_t mode7tileSet[256][8][8], values are 0-255 palette index
	local mode7graphicsTiles = ffi.new('uint8_t[?]', graphicsTileSizeInPixels * graphicsTileSizeInPixels * numMode7Tiles)
	for mode7tileIndex=0,numMode7Tiles-1 do
		for x=0,graphicsTileSizeInPixels-1 do
			for y=0,graphicsTileSizeInPixels-1 do
				mode7graphicsTiles[x + graphicsTileSizeInPixels * (y + graphicsTileSizeInPixels * mode7tileIndex)] 
					= ptr[1 + 2 * (x + graphicsTileSizeInPixels * (y + graphicsTileSizeInPixels * mode7tileIndex))]
			end
		end
	end

	-- who uses this?
	-- just a few rooms in Ceres space station -- the rotating room, and the rotating image of Ridley flying away
	-- uint8_t mode7tilemap[128][128], values are 0-255 lookup of the mode7tileSet
	local mode7tilemap = ffi.new('uint8_t[?]', mode7sizeInGraphicTiles * mode7sizeInGraphicTiles)
	for i=0,mode7sizeInGraphicTiles-1 do
		for j=0,mode7sizeInGraphicTiles-1 do
			mode7tilemap[i + mode7sizeInGraphicTiles * j] 
				= ptr[0 + 2 * (i + mode7sizeInGraphicTiles * j)]
		end
	end

	return mode7graphicsTiles, mode7tilemap
end

function SMMap:mapReadTileSets()
	local rom = self.rom
	
	--common room elements
	-- TODO this is a bad blob / has moved in Ice Metal
	-- so find in the code where this is read from
	self.commonRoomGraphicsTiles = Blob{
		sm = self,
		addr = commonRoomGraphicsTileAddr24:topc(),
		type = 'graphicsTile_t',
		compressed = true,
	}
	-- decompresesd size is 0x3000
--print('self.commonRoomGraphicsTiles.size', ('$%x'):format(self.commonRoomGraphicsTiles:sizeof()))


	-- if this happens then your rom's code has been modified to the point that the common room tilemap loading is somewhere else, or is pointed to somewhere else
	-- if these don't match then the rom has enough asm modifications that it probably has its common room tilemap somewhere else	
	-- but TODO if that's the case, why not just seek past the end of the common room graphics tile addr,
	--  since those two are usually packed?
	-- well, in roms like Metroid Redesigned, where these lookup instructions have been changed, it looks like the graphics tile buffer is also not present
	-- TODO how about instead I read the address from here -- and complain if any of these entries differ?
	local function check(loc, write)
		local ofsvalue = ffi.cast('uint16_t*', rom + loc.ofsaddr)[0]
		if ofsvalue ~= commonRoomTilemapAddr24.ofs then
			print(" WARNING - the value at location "..('%02x:%04x'):format(frompc(loc.ofsaddr))..", is "..('%04x'):format(ofsvalue)..", should be "..('%04x'):format(commonRoomTilemapAddr24.ofs))
			if write then
				commonRoomTilemapAddr24.ofs = ofsvalue
			end
		end

		local bankvalue = rom[loc.bankaddr]
		if bankvalue ~= commonRoomTilemapAddr24.bank then
			print(" WARNING - the value at location "..('%02x:%04x'):format(frompc(loc.bankaddr))..", is "..('%02x'):format(bankvalue)..", should be "..('%02x'):format(commonRoomTilemapAddr24.bank))
			if write then
				commonRoomTilemapAddr24.bank = bankvalue
			end
		end	

	end
	check(commonRoomTilemapAddrLocs[1], true)
	for i=2,#commonRoomTilemapAddrLocs do
		check(commonRoomTilemapAddrLocs[i], false) 
	end

	--common room elements
--DEBUG = true		
	-- TODO in Super Metroid Dependence the original addresses that point to commonRoomTilemapAddr24 haven't changed, but I'm still getting decompression errors here...
	self.commonRoomTilemaps = Blob{
		sm = self,
		addr = commonRoomTilemapAddr24:topc(),
		type = 'tilemapElem_t',
		compressed = true,
	}
--DEBUG = false	

	-- size is 0x800 ... so 256 8bit tile infos
	-- in my 32-tiles-per-row pics, this is 8 rows
--print('self.commonRoomTilemaps.size', ('$%x'):format(self.commonRoomTilemaps:sizeof()))

	--[[
	before loading any tileSets, find out the tileSet bank 
	where's the tileSet offsets read / bank set in code?
	82:def4 == 0x8f
	where's the tileSet themselves bank set in code?
	--]]
	self.tileSetBank = 0x8f
	local newTileSetBank = self.rom[topc(0x82, 0xdef4)]
	if self.tileSetBank ~= newTileSetBank then
		print("WARNING - tileSet offsets bank has changed from "..("%02x"):format(self.tileSetBank).." to "..('%02x'):format(newTileSetBank))
		self.tileSetBank = newTileSetBank 
	end

	-- offsets in the tileSetBank where	to find the tileSet_t data
	self.tileSetOffsets = Blob{
		sm = self,
		addr = tileSetOffsetsAddr,
		count = tileSetCount,
		type = 'uint16_t',
	}
	for i=0,tileSetCount-1 do
		local origOffset = select(2, frompc(tileSetOrigBaseAddr + 9 * i))
		if self.tileSetOffsets.v[i] ~= origOffset then
			print('WARNING - tileSet #'..('$%02x'):format(i)..' has moved from '..('%04x'):format(origOffset)..' to '..('%04x'):format(self.tileSetOffsets.v[i]))
		end
	end

	-- load all the tileset address info that is referenced by per-room stuff
	-- do this before any mapAddRoom calls
	for tileSetIndex=0,tileSetCount-1 do
		xpcall(function()
			self.tileSets:insert(TileSet{
				index = tileSetIndex,
				sm = self,
			})
		end, function(err)
			print(err..'\n'..debug.traceback())
		end)
	end

	-- strangely, immediately *after* the tileset data, is the table into the tileset data
	-- starting at 8f:e7a7, this is a list of 29 entries of 2 bytes each with values, starting at e6a2, spaced at 9 bytes each.
	-- which finishes at 8f:e7e1
	-- which is where the music pointers begin
end


local LoadStation = class(Blob)
LoadStation.type = 'loadStation_t'
LoadStation.count = 1

function SMMap:mapReadLoadStations()
	local rom = self.rom

	-- load stations
	-- I'm using this as entry points to loading rooms
	self.loadStationOffsetTable = Blob{
		sm = self,
		addr = topc(loadStationBank, loadStationRegionTableOffset),
		type = 'uint16_t',
		count = loadStationRegionCount,
	}
	
	for region=0,loadStationRegionCount-1 do
		self.loadStationsForRegion:insert{
			region = region,
			pageOffset = self.loadStationOffsetTable.v[region],
			stations = table(),
		}
	end
	
	-- how do you tell how many entries each one has?
	-- one way is to just not overrun the next address
	-- but what about the last address?
	-- of course that is a debug/empty table
	-- but TODO how do you determine the debug region loadStation count?
	for region=0,#self.loadStationsForRegion-1 do
		local lsr = self.loadStationsForRegion[region+1]
		local pageOffset = lsr.pageOffset
		local nextPageOffset
		if region < #self.loadStationsForRegion-1 then
			nextPageOffset = self.loadStationsForRegion[region+2].pageOffset
		else
			nextPageOffset = loadStationEndOffset
		end
		assert((nextPageOffset - pageOffset) % ffi.sizeof'loadStation_t' == 0)
		local count = (nextPageOffset - pageOffset) / ffi.sizeof'loadStation_t'
	
		local addr = topc(loadStationBank, pageOffset)
		for i=0,count-1 do
			lsr.stations:insert(LoadStation{sm=self, addr=addr})
			addr = addr + ffi.sizeof'loadStation_t'
		end
	end
end

function SMMap:mapInit()
	local rom = self.rom

	-- check where the PLM bank is
	-- TODO this will affect the items.lua addresses
	-- read from 84:84ac
	-- default is 0x8f
	self.plmBank = rom[0x204ac]	
--print('plmBank '..('%02x'):format(self.plmBank))

	self.loadStationsForRegion = table()

	self.rooms = table()
	self.roomblocks = table()
	self.bgs = table()
	self.bgTilemaps = table()
	self.fx1sets = table()

	self.doors = table()	-- most doors are added by rooms, but some are added by loadStations
	self.plmsets = table()
	self.enemySpawnSets = table()
	self.enemyGFXSets = table()

	self.tileSets = table()
	self.tileSetPalettes = table()
	self.tileSetGraphicsTileSets = table()
	self.tileSetTilemaps = table()


	self:mapReadTileSets()

	self:mapReadLoadStations()

	
	--[[ load fixed rooms	
	assert(self:mapAddRoom(topc(self.roomBank, 0x91f8), true))	-- Zebes
	assert(self:mapAddRoom(topc(self.roomBank, 0xdf45), true))	-- Ceres
	--]]
	-- [[ load via loadstations
	-- loadstations 0-7 are used for save points
	-- beyond that are used for lifts 
	-- and region=0 index=12h is used for landing from ceres
	
	for _,lsr in ipairs(self.loadStationsForRegion) do
		for _,ls in ipairs(lsr.stations) do
			if ls:obj().doorPageOffset > 0 then
				ls.door = self:mapAddDoor(topc(self.doorBank, ls:obj().doorPageOffset))
				ls.door.srcLoadStations:insertUnique(ls)
				
				if ls:obj().roomPageOffset ~= ls.door:obj().destRoomPageOffset then
					print('WARNING - loadStation region '..lsr.region
						..' has a room at '..('%04x'):format(ls:obj().roomPageOffset)
						..' has door at '..('%04x'):format(ls:obj().doorPageOffset)
						..' that points to room at '..('%04x'):format(ls.door:obj().destRoomPageOffset))
				end
				ls.door:buildRoom(self)
			end
		end
	end

	--[[
	this is just validation since the doors are all we need

	most these doors are already loaded from room loading
	but occasionally (one per region?) you'll find a loadStation door not used except by loadStations - these are for debug world map selection entrances 
	
	two out of the loadstation doors don't match
	the 21st loadstation of region 2
	the 17th loadstation of region 5
	so i'm thinking these aren't used
	--]]
	for _,lsr in ipairs(self.loadStationsForRegion) do
		for _,ls in ipairs(lsr.stations) do
			if not ls.door then
				assert(ls:obj().roomPageOffset == 0)
			else
				local room = select(2, self.rooms:find(nil, function(m)
					return m.addr == topc(self.roomBank, ls:obj().roomPageOffset)
				end))
				if not room then
					print("WARNING - loadStation "
						..('%06x'):format(ls.addr)
						.." has roomPageOffset "..('%04x'):format(ls:obj().roomPageOffset)
						.." failed to add room")
				elseif room ~= ls.door.destRoom then
					print("WARNING - loadStation "
						..('%06x'):format(ls.addr)
						.." room "
						..room:getIdentStr()
						.." does not match door's room "
						..ls.door.destRoom:getIdentStr()
					)
				end
			end
		end
	end
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


	-- load kraid's background, since its address will have to be updated in the code
	-- this should already be referenced by a room, (and therefore already loaded)
	xpcall(function()
		local ofs1 = rom[mapKraidBGTilemapTopAddrLoc.ofs1addr]
		local ofs2 = rom[mapKraidBGTilemapTopAddrLoc.ofs2addr]
		local bank = rom[mapKraidBGTilemapTopAddrLoc.bankaddr]
		local ofs = bit.bor(ofs1, bit.lshift(ofs2, 8))
		self.mapKraidBGTilemapTop = self:mapAddBGTilemap(topc(bank, ofs))
		assert(self.mapKraidBGTilemapTop.bg, "expected kraid bg tilemap to already be assigned to a room")
	end, function(err)
		print("failed to load kraid BG tilemap")
		print(err..'\n'..debug.traceback())
	end)
	xpcall(function()
		local ofs1 = rom[mapKraidBGTilemapBottomAddrLoc.ofs1addr]
		local ofs2 = rom[mapKraidBGTilemapBottomAddrLoc.ofs2addr]
		local bank = rom[mapKraidBGTilemapBottomAddrLoc.bankaddr]
		local ofs = bit.bor(ofs1, bit.lshift(ofs2, 8))
		self.mapKraidBGTilemapBottom = self:mapAddBGTilemap(topc(bank, ofs))
		assert(self.mapKraidBGTilemapBottom.bg, "expected kraid bg tilemap to already be assigned to a room")
	end, function(err)
		print("failed to load kraid BG tilemap bottom")
		print(err..'\n'..debug.traceback())
	end)


	if config.mapAssertStructure then
		-------------------------------- ASSERT STRUCT ---------------------------------
		
		-- asserting underlying contiguousness of structure of the room_t's...
		-- verify that after each room_t, the roomselect / roomstate_t / dooraddrs are packed together

		-- before the first room_t is 174 plm_t's, 
		-- then 100 bytes of something
		assert(self.rooms)
		for j,m in ipairs(self.rooms) do
			local d = ffi.cast('uint8_t*', m:ptr())
			local roomaddr = d - rom
			d = d + ffi.sizeof'room_t'
			-- last roomselect should always be 2 byte term
			--assert(m.roomStates:last().roomSelect.type == 'roomselect1_t')
			-- if there's only 1 roomState then it is a term, and
			for i=1,#m.roomStates do
				assert(d == ffi.cast('uint8_t*', m.roomStates[i].roomSelect:ptr()))
				d = d + ffi.sizeof(m.roomStates[i].roomSelect.type)
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
			local dooraddr = topc(self.doorAddrBank, m:obj().doorPageOffset)
	--		assert(d == rom + dooraddr)
			if d ~= rom + dooraddr then
				print("warning - doorPageOffset does not proceed roomStates")
				d = rom + dooraddr
			end
			d = d + 2 * #m.doors
			
			-- now expect all scrolldatas of all rooms of this room_t
			-- the # of unique scrolldatas is either 0 or 1
			local scrolls = m.roomStates:map(function(rs)
				return true, rs:obj().scrollPageOffset
			end):keys():filter(function(scroll)
				return scroll > 1 and scroll ~= 0x8000
			end):sort()
			if #scrolls > 1 then
				print("warning - got more than one scrolls "..#scrolls)
			end
			-- room_t $07adad -- room before wave room -- has its scrolldata overlap with the dooraddr
			-- so... shouldn't this assertion fail?
			for _,scroll in ipairs(scrolls) do
				local addr = topc(self.scrollBank, scroll)
	--			assert(d == rom + addr)
				if d ~= rom + addr then
					print("warning - scrollPageOffset does not proceed doorPageOffset")
					d = rom + addr
				end
				d = d + m:obj().width * m:obj().height
			end
		end
	end --------------------------------------------------------------------------------

	
	-- while here, sort roomBlockDatas
	self.roomblocks:sort(function(a,b)
		local ma = a.roomStates[1].room
		local mb = b.roomStates[1].room
		if ma:obj().region < mb:obj().region then return true end
		if ma:obj().region > mb:obj().region then return false end
		return ma:obj().index < mb:obj().index
	end)


	-- TODO switch to graphicsTile indexes used, per 8x8 block
	-- collect all unique indexes of each roomblockdata	
	for _,roomBlockData in ipairs(self.roomblocks) do
		roomBlockData.tileIndexesUsed = roomBlockData.tileIndexesUsed or {}
		local blocks12 = ffi.cast('uint16_t*', roomBlockData:getBlocks12())
		local blocks3 = ffi.cast('uint16_t*', roomBlockData:getBlocks3())
		local layer2blocks = roomBlockData:getLayer2Blocks()
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
						local tileIndex = bit.band(blocks12[di], 0x3ff)
						roomBlockData.tileIndexesUsed[tileIndex] = true
						-- TODO convert tileIndexes into its 4 graphicsTile indexes and mark the graphicsTiles used
						if layer2blocks then
							local tileIndex = bit.band(layer2blocks[di], 0x3ff) 
							roomBlockData.tileIndexesUsed[tileIndex] = true
						end
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
			if rs.roomBlockData then
				for tileIndex,_ in pairs(rs.roomBlockData.tileIndexesUsed) do
					rs.tileSet.tileIndexesUsed[tileIndex] = true
				end
			end
		end
	end

	-- all fx1's that point to doors, update the pointers here
	-- TODO should I keep track of a list of fx1s per-door?
	for _,fx1set in ipairs(self.fx1sets) do
		for _,fx1 in ipairs(fx1set.fx1s) do
			if fx1:obj().doorPageOffset > 0 then
				local addr = topc(self.doorBank, fx1:obj().doorPageOffset)
				fx1.door = select(2, self.doors:find(nil, function(door)
					return door.addr == addr
				end))
				if not fx1.door then
					print("WARNING - fx1 has nonzero door offset but couldn't find the door at "..('%06x'):format(addr))
				end
			end
		end
	end

	-- [=[
	-- now that all rooms are loaded, and all bg_t's are loaded, 
	-- assign door pointers to all bg_e_t's
	-- BUT since this is a bg_t, if it points to a dangling door, don't try to load it, and don't try to build rooms from it
	for i=#self.bgs,1,-1 do
		local bg = self.bgs[i]
		if bg.type == 'bg_e_t' then
			-- TODO separate class per bg_*_t
			-- and with the bg_e_t, you must have a door
			assert(bg:obj().doorPageOffset >= 0x8000)
			local addr = topc(self.doorBank, bg:obj().doorPageOffset)
			bg.door = select(2, self.doors:find(nil, function(door) 
				return door.addr == addr 
			end))
			if not bg.door then
				--[[
				in room 0-00 there is a background that only activates when entering from the debug room ... 
				but I'm not loading the debug room ...
				so ...
				should I be?
				--]]
				print(
					"WARNING failed to find door at "..('%06x'):format(addr)
					..'\n used by roomstates '..bg.roomStates:mapi(function(rs)
						return ('%06x'):format(rs.addr)
					end):concat' '..' ... removing'
				)
				-- remove it?
				self.bgs:remove(i)
			end
		end
	end
	--]=]

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

end


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

local debugImageColorMap = range(254)
--debugImageColorMap = table.shuffle(debugImageColorMap)
debugImageColorMap[0] = 0
debugImageColorMap[255] = 255

local function drawRoomBlocks(ctx, roomBlockData, rs)
	local fullmapinfo = ctx.sm:mapGetFullMapInfoForMD5(ctx.sm.md5hash)
	
	local m = rs.room
	local debugMapImage = ctx.debugMapImage
	local debugMapMaskImage = ctx.debugMapMaskImage
	local blocks12 = roomBlockData:getBlocks12()
	local blocks3 = roomBlockData:getBlocks3()
	local w = roomBlockData.width / blocksPerRoom
	local h = roomBlockData.height / blocksPerRoom
	local ofscalc = assert(fullmapinfo.ofsPerRegion[m:obj().region+1], "couldn't get offset calc func for room: "..m:obj())
	local ofsInRoomBlocksX, ofsInRoomBlocksY = ofscalc(m)
	local firstcoord
	
	for j=0,h-1 do
		for i=0,w-1 do
			local ignore
			if config.mapOmitOverlappingRoomsInOriginal then
				local region, index = m:obj().region, m:obj().index
				local roomKey = bit.bor(bit.lshift(region, 8), index)
				local infos = fullmapinfo.mapDrawExcludeMapBlocks[roomKey]
				if infos then
					for _,info in ipairs(infos) do
						local mx, my, mw, mh = table.unpack(info)
						if i >= mx and i < mx + mw 
						and j >= my and j < my + mh
						then
							ignore = true
							break
						end
					end
				end
			end
			if not ignore then
				for ti=0,blocksPerRoom-1 do
					for tj=0,blocksPerRoom-1 do
						local dx = ti + blocksPerRoom * i
						local dy = tj + blocksPerRoom * j
						local di = dx + blocksPerRoom * w * dy
						-- blocks is 0-based
						local d1 = blocks12[0 + 2 * di]
						local d2 = blocks12[1 + 2 * di]
						local d3 = blocks3[di]
				
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
								local y = pj + debugImageBlockSizeInPixels * (tj + blocksPerRoom * (m:obj().y + j + ofsInRoomBlocksY))
								for pi=0,debugImageBlockSizeInPixels-1 do
									local x = pi + debugImageBlockSizeInPixels * (ti + blocksPerRoom * (m:obj().x + i + ofsInRoomBlocksX))
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

						-- TODO isSolid will overlap between a few rooms
						local isBorder = roomBlockData:isBorderAndNotCopy(dx,dy)
						do --if isBorder or isSolid then
							local isSolid = roomBlockData:isSolid(dx,dy)
							for pi=0,debugImageBlockSizeInPixels-1 do
								for pj=0,debugImageBlockSizeInPixels-1 do
									local x = pi + debugImageBlockSizeInPixels * (ti + blocksPerRoom * (m:obj().x + i + ofsInRoomBlocksX))
									local y = pj + debugImageBlockSizeInPixels * (tj + blocksPerRoom * (m:obj().y + j + ofsInRoomBlocksY))
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

	if not firstcoord then
		firstcoord = {
			debugImageBlockSizeInPixels * (blocksPerRoom * (m:obj().x + ofsInRoomBlocksX)),
			debugImageBlockSizeInPixels * (blocksPerRoom * (m:obj().y + ofsInRoomBlocksY)),
		}
	end

	drawstr(debugMapImage, firstcoord[1], firstcoord[2], ('%x-%02x'):format(m:obj().region, m:obj().index))
	drawstr(debugMapImage, firstcoord[1], firstcoord[2]+6, ('$%02x:%04x'):format(frompc(m.addr)))
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
	local fullmapinfo = ctx.sm:mapGetFullMapInfoForMD5(ctx.sm.md5hash)
	local debugMapImage = ctx.debugMapImage
	-- for all blocks in the room, if any are xx9xyy, then associate them with exit yy in the door_t list (TODO change to exit_t)	
	-- then, cycle through exits, and draw lines from each block to the exit destination

	for _,rs in ipairs(roomBlockData.roomStates) do
		local srcRoom = rs.room
		local srcRoom_ofsx, srcRoom_ofsy = fullmapinfo.ofsPerRegion[srcRoom:obj().region+1](srcRoom)
		local srcRoom_xofs = debugImageRoomSizeInPixels * srcRoom_ofsx
		local srcRoom_yofs = debugImageRoomSizeInPixels * srcRoom_ofsy
		for exitIndex,blockpos in pairs(roomBlockData.blocksForExit) do
--print('in room '..srcRoom:getIdentStr()..' looking for exit '..exitIndex..' with '..#blockpos..' blocks')
			-- TODO lifts will mess up the order of this, maybe?
			local door = srcRoom.doors[exitIndex+1]
			if not door then
--print('found no door')
			elseif door.type ~= 'door_t' then
--print("door isn't a ctype")
			-- TODO handle lifts?
			else
				local dstRoom = assert(door.destRoom)
				local dstRoom_ofsx, dstRoom_ofsy = fullmapinfo.ofsPerRegion[dstRoom:obj().region+1](dstRoom)
				local dstRoom_xofs = debugImageRoomSizeInPixels * dstRoom_ofsx
				local dstRoom_yofs = debugImageRoomSizeInPixels * dstRoom_ofsy
			
				-- draw an arrow or something on the map where the door drops us off at
				-- door.destRoom is the room
				-- draw it at door:obj().screenX by door:obj().screenY
				-- and offset it according to direciton&3 and distToSpawnSamus (maybe)

				local i = door:obj().screenX
				local j = door:obj().screenY
				local dir = bit.band(door:obj().direction, 3)	-- 0-based
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
				local x1 = dstRoom_xofs + pi + debugImageBlockSizeInPixels * (ti + blocksPerRoom * (dstRoom:obj().x + i))
				local y1 = dstRoom_yofs + pj + debugImageBlockSizeInPixels * (tj + blocksPerRoom * (dstRoom:obj().y + j))

				for _,pos in ipairs(blockpos) do
					-- now for src block pos
					local x2 = srcRoom_xofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (pos[1] + blocksPerRoom * srcRoom:obj().x)
					local y2 = srcRoom_yofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (pos[2] + blocksPerRoom * srcRoom:obj().y)
					drawline(debugMapImage,x1,y1,x2,y2)
				end
			end
		end
	end
end

local function drawRoomBlockPLMs(ctx, roomBlockData)
	local fullmapinfo = ctx.sm:mapGetFullMapInfoForMD5(ctx.sm.md5hash)
	
	local debugMapImage = ctx.debugMapImage
	for _,rs in ipairs(roomBlockData.roomStates) do
		local m = rs.room
		local ofsInRoomBlocksX, ofsInRoomBlocksY = fullmapinfo.ofsPerRegion[m:obj().region+1](m)
		local xofs = debugImageRoomSizeInPixels * ofsInRoomBlocksX
		local yofs = debugImageRoomSizeInPixels * ofsInRoomBlocksY
		if rs.plmset then
			for _,plm in ipairs(rs.plmset.plms) do
				local x = xofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (plm.x + blocksPerRoom * m:obj().x)
				local y = yofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (plm.y + blocksPerRoom * m:obj().y)
				drawline(debugMapImage,x+2,y,x-2,y, 0x00, 0xff, 0xff)
				drawline(debugMapImage,x,y+2,x,y-2, 0x00, 0xff, 0xff)
				drawstr(debugMapImage, x+5, y, ('$%x'):format(plm.cmd))
			end
		end
		if rs.enemySpawnSet then
			for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do
				local x = math.round(xofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (enemySpawn.x / 16 + blocksPerRoom * m:obj().x))
				local y = math.round(yofs + debugImageBlockSizeInPixels/2 + debugImageBlockSizeInPixels * (enemySpawn.y / 16 + blocksPerRoom * m:obj().y))
				drawline(debugMapImage,x+2,y,x-2,y, 0xff, 0x00, 0xff)
				drawline(debugMapImage,x,y+2,x,y-2, 0xff, 0x00, 0xff)
				drawstr(debugMapImage, x+5, y, ('$%x'):format(enemySpawn.enemyPageOffset))
			end
		end
	end
end


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
SMMap.bitmapForTileSetAndTileMap = {}
function SMMap:mapGetBitmapForTileSetAndTileMap(tileSet, tilemap)
	self.bitmapForTileSetAndTileMap[tileSet.index] = self.bitmapForTileSetAndTileMap[tileSet.index] or {}
	local bgBmp = self.bitmapForTileSetAndTileMap[tileSet.index][tilemap.addr]
	if bgBmp then return bgBmp end

	bgBmp = {}

--print('generating bitmap for tileSet '..('%02x'):format(tileSet.index)..' tilemap '..('%06x'):format(tilemap.addr))		
	bgBmp.tilemap = tilemap

	bgBmp.dataBmp = self:graphicsConvertTilemapToBitmap(
		tilemap.v,
		tilemap.width,
		tilemap.height,
		tileSet.graphicsTileVec.v)
	
	self.bitmapForTileSetAndTileMap[tileSet.index][tilemap.addr] = bgBmp
	return bgBmp
end


function SMMap:mapSaveImageInformative(filenamePrefix)
	filenamePrefix = filenamePrefix or 'map'

	local fullmapinfo = self:mapGetFullMapInfoForMD5(self.md5hash)

	local w = debugImageRoomSizeInPixels * fullmapinfo.fullMapWidthInBlocks
	local h = debugImageRoomSizeInPixels * fullmapinfo.fullMapHeightInBlocks

	local debugMapImage = Image(w, h, 3, 'unsigned char')
	local debugMapMaskImage = Image(w, h, 3, 'unsigned char')

	local ctx = {
		sm = self,
		debugMapImage = debugMapImage,
		debugMapMaskImage = debugMapMaskImage,
	}

	local regionRanges = {}
	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			local m = rs.room
			local range = regionRanges[m:obj().region]
			if not range then
				range = {}
				range.region = m:obj().region
				range.x1 = m:obj().x
				range.y1 = m:obj().y
				range.x2 = m:obj().x + m:obj().width - 1
				range.y2 = m:obj().y + m:obj().height - 1
				regionRanges[m:obj().region] = range
			else
				range.x1 = math.min(range.x1, m:obj().x)
				range.y1 = math.min(range.y1, m:obj().y)
				range.x2 = math.max(range.x2, m:obj().x + m:obj().width - 1)
				range.y2 = math.max(range.y2, m:obj().y + m:obj().height - 1)
			end
		end
	end
--	for region,range in pairs(regionRanges) do
--		print('region ranges '..tolua(range))
--	end

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
end


local function drawRoomBlocksTextured(args)
	local roomBlockData = assert(args.roomBlockData)
	local rs = assert(args.rs)
	local sm = assert(args.sm)
	local mapTexImage = assert(args.mapTexImage)

	local fullmapinfo = sm:mapGetFullMapInfoForMD5(sm.md5hash)
	
	local m = rs.room
	local blocks12 = roomBlockData:getBlocks12()
	local blocks3 = roomBlockData:getBlocks3()
	local layer2blocks = roomBlockData:getLayer2Blocks()
	local w = roomBlockData.width / blocksPerRoom
	local h = roomBlockData.height / blocksPerRoom

	local ofsInRoomBlocksX, ofsInRoomBlocksY = 0, 0
	if not args.ignoreOffsetPerRegion then
		local ofscalc = assert(fullmapinfo.ofsPerRegion[m:obj().region+1], "couldn't get offset calc func for room:\n "..m:obj())
		ofsInRoomBlocksX, ofsInRoomBlocksY = ofscalc(m)
	end

	local tileSet = rs.tileSet
	if not tileSet then return end

	-- TODO first bg with a tileset ... but for now there's only 1 anyways
	local _, bg = rs.bgs:find(nil, function(bg) return bg.tilemap end)
	local bgTilemap = bg and bg.tilemap
	local bgBmp = bgTilemap and sm:mapGetBitmapForTileSetAndTileMap(tileSet, bgTilemap)
	local bgw = bgBmp and graphicsTileSizeInPixels * bgTilemap.width
	local bgh = bgBmp and graphicsTileSizeInPixels * bgTilemap.height
	
	for j=0,h-1 do
		for i=0,w-1 do
			local ignore
			if config.mapOmitOverlappingRoomsInOriginal then
				local region, index = m:obj().region, m:obj().index
				local roomKey = bit.bor(bit.lshift(region, 8), index)
				local infos = fullmapinfo.mapDrawExcludeMapBlocks[roomKey]
				if infos then
					for _,info in ipairs(infos) do
						local mx, my, mw, mh = table.unpack(info)
						if i >= mx and i < mx + mw 
						and j >= my and j < my + mh
						then
							ignore = true
							break
						end
					end
				end
			end
			if not ignore then
				for ti=0,blocksPerRoom-1 do
					for tj=0,blocksPerRoom-1 do
						local dx = ti + blocksPerRoom * i
						local dy = tj + blocksPerRoom * j
						local di = dx + blocksPerRoom * w * dy
						-- blocks is 0-based
						local d1 = blocks12[0 + 2 * di]
						local d2 = blocks12[1 + 2 * di]
						local d3 = blocks3[di]
							
						-- TODO seems omitting tileIndexes >= tileGfxCount and just using modulo tileGfxCount makes no difference
						--and tileIndex < tileSet.tileGfxCount
-- [[ draw background?
						if bgBmp then
							for pj=0,blockSizeInPixels-1 do
								local y = pj + blockSizeInPixels * (tj + blocksPerRoom * (m:obj().y + j + ofsInRoomBlocksY))
								for pi=0,blockSizeInPixels-1 do
									local x = pi + blockSizeInPixels * (ti + blocksPerRoom * (m:obj().x + i + ofsInRoomBlocksX))
									if x >= 0 and x < mapTexImage.width
									and y >= 0 and y < mapTexImage.height 
									then
										local bgx = x % bgw
										local bgy = y % bgh
										local paletteIndex = bgBmp.dataBmp.buffer[bgx + bgw * bgy]
										if bit.band(paletteIndex, 0xf) > 0 then
											local src = tileSet.palette.v[paletteIndex]
											local dstIndex = x + mapTexImage.width * y
											local dst = mapTexImage.buffer + 3 * dstIndex
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
						if layer2blocks then
							local tileIndex = ffi.cast('uint16_t*', layer2blocks)[ti + blocksPerRoom * i + blocksPerRoom * w * (tj + blocksPerRoom * j)]
							local pimask = bit.band(tileIndex, 0x400) ~= 0 and 15 or 0
							local pjmask = bit.band(tileIndex, 0x800) ~= 0 and 15 or 0
							tileIndex = bit.band(tileIndex, 0x3ff)
							
							for pj=0,blockSizeInPixels-1 do
								for pi=0,blockSizeInPixels-1 do
									local x = pi + blockSizeInPixels * (ti + blocksPerRoom * (m:obj().x + i + ofsInRoomBlocksX))
									local y = pj + blockSizeInPixels * (tj + blocksPerRoom * (m:obj().y + j + ofsInRoomBlocksY))
									if x >= 0 and x < mapTexImage.width
									and y >= 0 and y < mapTexImage.height 
									then
										-- for loop here
										--local dst = img.buffer + 3 * (pi + blockSizeInPixels * x + pixw * (pj + blockSizeInPixels * y))
										local spi = bit.bxor(pi, pimask)
										local spj = bit.bxor(pj, pjmask)
										local srcIndex = spi + blockSizeInPixels * (spj + blockSizeInPixels * tileIndex)
										local paletteIndex = tileSet.tileGfxBmp.buffer[srcIndex]
										if bit.band(paletteIndex, 0xf) > 0 then
											local src = tileSet.palette.v[paletteIndex]
											local dstIndex = x + mapTexImage.width * y
											local dst = mapTexImage.buffer + 3 * dstIndex
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
								local y = pj + blockSizeInPixels * (tj + blocksPerRoom * (m:obj().y + j + ofsInRoomBlocksY))
								for pi=0,blockSizeInPixels-1 do
									local x = pi + blockSizeInPixels * (ti + blocksPerRoom * (m:obj().x + i + ofsInRoomBlocksX))
									if x >= 0 and x < mapTexImage.width
									and y >= 0 and y < mapTexImage.height 
									then
										local spi = bit.bxor(pi, pimask)
										local spj = bit.bxor(pj, pjmask)
										local srcIndex = spi + blockSizeInPixels * (spj + blockSizeInPixels * tileIndex)
										local paletteIndex = tileSet.tileGfxBmp.buffer[srcIndex]
										-- now which determines transparency?
										if bit.band(paletteIndex, 0xf) > 0 then	-- why does lo==0 coincide with a blank tile? doesn't that mean colors 0, 16, 32, etc are always black?
											local src = tileSet.palette.v[paletteIndex]
											local dstIndex = x + mapTexImage.width * y
											local dst = mapTexImage.buffer + 3 * dstIndex
											dst[0] = math.floor(src.r*255/31)
											dst[1] = math.floor(src.g*255/31)
											dst[2] = math.floor(src.b*255/31)
										end
									end
								end
							end
						end
--[[ want to see what tileIndex each block is?
						drawstr(mapTexImage,
							2 + blockSizeInPixels * (ti + blocksPerRoom * (m:obj().x + i + ofsInRoomBlocksX)),
							8 + blockSizeInPixels * (tj + blocksPerRoom * (m:obj().y + j + ofsInRoomBlocksY)),
							('%02x'):format(tileIndex))
--]]						
					end
				end
			end
		end
	end
end

function SMMap:mapSaveImageTextured(filenamePrefix)
	filenamePrefix = filenamePrefix or 'map'
	
	local fullmapinfo = self:mapGetFullMapInfoForMD5(self.md5hash)
	
	local mapTexImage = Image(
		blockSizeInPixels * blocksPerRoom * fullmapinfo.fullMapWidthInBlocks,
		blockSizeInPixels * blocksPerRoom * fullmapinfo.fullMapHeightInBlocks,
		3, 'unsigned char')
	mapTexImage:clear()

	SMMap.bitmapForTileSetAndTileMap = {}	-- clear bgBmp cache
	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			drawRoomBlocksTextured{
				sm = self,
				mapTexImage = mapTexImage,
				rs = rs,
				roomBlockData = roomBlockData,
			}
		end
	end
	if config.mapSaveImageTextured_HighlightItems then
		-- do this last, so no room tiles overlap it
		for _,m in ipairs(self.rooms) do
			local ofsInRoomBlocksX, ofsInRoomBlocksY = fullmapinfo.ofsPerRegion[m:obj().region+1](m)
			local xofs = roomSizeInPixels * ofsInRoomBlocksX
			local yofs = roomSizeInPixels * ofsInRoomBlocksY
			for _,rs in ipairs(m.roomStates) do
				if rs.plmset then
					for _,plm in ipairs(rs.plmset.plms) do
						local name = self.plmCmdNameForValue[plm.cmd]
						if name and name:sub(1,5) == 'item_' then
							local x = xofs + blockSizeInPixels / 2 + blockSizeInPixels * (plm.x + blocksPerRoom * m:obj().x)
							local y = yofs + blockSizeInPixels / 2 + blockSizeInPixels * (plm.y + blocksPerRoom * m:obj().y)
						
							for rad=1,8,2 do
								local x1 = x - rad
								local y1 = y - rad
								local x2 = x + rad
								local y2 = y + rad
								drawline(mapTexImage, x1, y1, x2, y1, 0x00, 0xff, 0xff)
								drawline(mapTexImage, x2, y1, x2, y2, 0x00, 0xff, 0xff)
								drawline(mapTexImage, x2, y2, x1, y2, 0x00, 0xff, 0xff)
								drawline(mapTexImage, x1, y2, x1, y1, 0x00, 0xff, 0xff)
							end
						end
					end
				end
			end
		end
	end

	mapTexImage:save(filenamePrefix..'-tex.png')
end

-- TODO put this in sm-regions?
function SMMap:mapSaveImageRegionsTextured()
	for _,region in ipairs(self.regions) do
		-- TODO store region bounds in the sm-regions.lua ctor?
		local min = {math.huge, math.huge}
		local max = {-math.huge, -math.huge}
		for _,room in ipairs(region.rooms) do
			min[1] = math.min(min[1], room:obj().x)
			min[2] = math.min(min[2], room:obj().y)
			max[1] = math.max(max[1], room:obj().x + room:obj().width - 1)
			max[2] = math.max(max[2], room:obj().y + room:obj().height - 1)
		end
		region.min = min
		region.max = max

		-- also for the image size, use 64x32 map region blocks, since that's how big the region map tilemaps are
		-- also, to match with the game, draw map tiles down one tile's size
		local regionTexImage = Image(
			blockSizeInPixels * blocksPerRoom * 64,
			blockSizeInPixels * blocksPerRoom * 32,
			3, 'unsigned char')
		regionTexImage:clear()
	
		for _,room in ipairs(region.rooms) do
			for _,rs in ipairs(room.roomStates) do
				drawRoomBlocksTextured{
					sm = self,
					mapTexImage = regionTexImage,
					rs = rs,
					roomBlockData = rs.roomBlockData,
					ignoreOffsetPerRegion = true,
				}
			end
		end
	
		regionTexImage:save('map-tex-region-'..region.index..'.png')
	end
end

local function drawRoomBlocksDumpworld(
	roomBlockData,
	rs,
	sm,
	dumpworldTileImg,
	dumpworldTileFgImg,
	dumpworldTileBgImg
)
	local fullmapinfo = self:mapGetFullMapInfoForMD5(sm.md5hash)
	
	local m = rs.room
	local blocks12 = roomBlockData:getBlocks12()
	local blocks3 = roomBlockData:getBlocks3()
	local w = roomBlockData.width / blocksPerRoom
	local h = roomBlockData.height / blocksPerRoom
	local ofscalc = assert(fullmapinfo.ofsPerRegion[m:obj().region+1], "couldn't get offset calc func for room:\n "..m:obj())
	local ofsInRoomBlocksX, ofsInRoomBlocksY = ofscalc(m)
	
	for j=0,h-1 do
		for i=0,w-1 do
			local ignore
			if config.mapOmitOverlappingRoomsInOriginal then
				local region, index = m:obj().region, m:obj().index
				local roomKey = bit.bor(bit.lshift(region, 8), index)
				local infos = fullmapinfo.mapDrawExcludeMapBlocks[roomKey]
				if infos then
					for _,info in ipairs(infos) do
						local mx, my, mw, mh = table.unpack(info)
						if i >= mx and i < mx + mw 
						and j >= my and j < my + mh
						then
							ignore = true
							break
						end
					end
				end
			end
			if not ignore then
				for ti=0,blocksPerRoom-1 do
					for tj=0,blocksPerRoom-1 do
						local dx = ti + blocksPerRoom * i
						local dy = tj + blocksPerRoom * j
						local di = dx + blocksPerRoom * w * dy
						-- blocks is 0-based
						local d1 = blocks12[0 + 2 * di]
						local d2 = blocks12[1 + 2 * di]
						local d3 = blocks3[di]
						
						-- TODO isSolid will overlap between a few rooms
						local isBorder = roomBlockData:isBorderAndNotCopy(dx,dy)
						do --if isBorder or isSolid then
							local isSolid = roomBlockData:isSolid(dx,dy)
							
							do
								local x = ti + blocksPerRoom * (m:obj().x + i + ofsInRoomBlocksY)
								local y = tj + blocksPerRoom * (m:obj().y + j + ofsInRoomBlocksX)
								if x >= 0 and x < dumpworldTileImg.width
								and y >= 0 and y < dumpworldTileImg.height 
								then
									local dstIndex = x + dumpworldTileImg.width * y
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
										
-- [===[
											print('here with ext tiletype '..tolua{
												region = ('%02x'):format(m:obj().region),
												index = ('%02x'):format(m:obj().index),
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
									dumpworldTileImg.buffer[0+3*dstIndex] = dtt
									dumpworldTileImg.buffer[1+3*dstIndex] = 0
									dumpworldTileImg.buffer[2+3*dstIndex] = 0
									
									if foreground then
										dumpworldTileFgImg.buffer[0+3*dstIndex] = d1
										dumpworldTileFgImg.buffer[1+3*dstIndex] = bit.band(d2, 0x03)
										dumpworldTileFgImg.buffer[2+3*dstIndex] = 0
									else
										dumpworldTileBgImg.buffer[0+3*dstIndex] = d1
										dumpworldTileBgImg.buffer[1+3*dstIndex] = bit.band(d2, 0x03)
										dumpworldTileBgImg.buffer[2+3*dstIndex] = 0
									end
--]==]
								end
							end
						end
					end
				end
			end
		end
	end
end



function SMMap:mapSaveDumpworldImage(filenamePrefix)
	filenamePrefix = filenamePrefix or 'map'
	
	local fullmapinfo = self:mapGetFullMapInfoForMD5(self.md5hash)

	-- 1 pixel : 1 block for dumpworld
	local dumpw = blocksPerRoom * fullmapinfo.fullMapWidthInBlocks
	local dumph = blocksPerRoom * fullmapinfo.fullMapHeightInBlocks

	local dumpworldTileImg = Image(dumpw, dumph, 3, 'unsigned char')
	local dumpworldTileFgImg = Image(dumpw, dumph, 3, 'unsigned char')
	local dumpworldTileBgImg = Image(dumpw, dumph, 3, 'unsigned char')

	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			drawRoomBlocksDumpworld(
				roomBlockData,
				rs,
				sm,
				dumpworldTileImg,
				dumpworldTileFgImg,
				dumpworldTileBgImg
			)
		end
	end

	dumpworldTileImg:save('../dumpworld/zeta/maps/sm3/tile.png')
	dumpworldTileFgImg:save('../dumpworld/zeta/maps/sm3/tile-fg.png')
	dumpworldTileBgImg:save('../dumpworld/zeta/maps/sm3/tile-bg.png')
end


function SMMap:mapSaveGraphicsMode7()
	-- for now only write out tile graphics for the non-randomized version
	for _,tileSet in ipairs(self.tileSets) do
		if tileSet.mode7graphicsTiles then
			local mode7image = Image(
				graphicsTileSizeInPixels * mode7sizeInGraphicTiles,
				graphicsTileSizeInPixels * mode7sizeInGraphicTiles,
				3, 'unsigned char')
			mode7image:clear()
			local maxdestx = 0
			local maxdesty = 0	
			for i=0,mode7sizeInGraphicTiles-1 do
				for j=0,mode7sizeInGraphicTiles-1 do
					local mode7tileIndex = tileSet.mode7tilemap[i + mode7sizeInGraphicTiles * j]
					for y=0,graphicsTileSizeInPixels-1 do
						for x=0,graphicsTileSizeInPixels-1 do
							local destx = x + graphicsTileSizeInPixels * i
							local desty = y + graphicsTileSizeInPixels * j
							local paletteIndex = tileSet.mode7graphicsTiles[
								x + graphicsTileSizeInPixels * (y + graphicsTileSizeInPixels * mode7tileIndex)
							]
							local src = tileSet.palette.v[paletteIndex]
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
			mode7image:save('mode7 tileSet='..('%02x'):format(tileSet.index)..'.png')
		end
	end
end
	
function SMMap:mapSaveGraphicsTileSets()
	-- TODO how about a wrap row?  grid x, grid y, result x, result y 
	for _,tileSet in ipairs(self.tileSets) do
		if tileSet.tileGfxBmp then
			local numBlockTilesWide = 32
		
			local img = self:graphicsBitmapIndexedToRGB(tileSet.tileGfxBmp, tileSet.palette)
			local img = self:graphicsWrapRows(img, blockSizeInPixels, numBlockTilesWide)
			img:save('tileset/tileSet='..('%02x'):format(tileSet.index)..' tilegfx.png')

			
			-- draw some diagonal green lines over the used tiles
			local highlightColor = {0, 255, 0}
			-- [[
			for tileIndex=0,tileSet.tileGfxCount-1 do
				if tileSet.tileIndexesUsed[tileIndex] then
					local xofs = tileIndex % numBlockTilesWide
					local yofs = (tileIndex - xofs) / numBlockTilesWide
					for j=0,blockSizeInPixels-1 do
						for i=0,blockSizeInPixels-1 do
							local dstIndex = i + blockSizeInPixels * xofs
								+ blockSizeInPixels * numBlockTilesWide * (j + blockSizeInPixels * yofs)
							if (i + j) % 3 == 0 then
								for ch=0,2 do
									local v = img.buffer[ch + 3 * dstIndex]
									v = math.floor(.5 * highlightColor[ch+1] + .5 * v)
									img.buffer[ch + 3 * dstIndex] = v
								end
							end
						end
					end
				end
			end
			--]]
			img:save('tileset used/tileSet='..('%02x'):format(tileSet.index)..' tilegfx used.png')
	
			
			do
				assert(tileSet.graphicsTileVec.size % graphicsTileSizeInBytes == 0)
				local tilesWide = tileSet.graphicsTileVec.size / graphicsTileSizeInBytes
				local img = self:graphicsCreateRGBBitmapForTiles(tileSet.graphicsTileVec.v, tilesWide, tileSet.palette)
				img:save('graphictiles/graphictile='..('%02x'):format(tileSet.index)..'.png')
			end
		end
	end
end

function SMMap:mapSaveGraphicsLayer2BGs()
	for _,roomBlockData in ipairs(self.roomblocks) do
		local layer2blocks = roomBlockData:getLayer2Blocks()
		if layer2blocks then
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
					local tileIndex = ffi.cast('uint16_t*', layer2blocks + 2 * (x + w * y))[0]
					local pimask = bit.band(tileIndex, 0x400) ~= 0 and 15 or 0
					local pjmask = bit.band(tileIndex, 0x800) ~= 0 and 15 or 0
					tileIndex = bit.band(tileIndex, 0x3ff)
					for pj=0,blockSizeInPixels-1 do
						for pi=0,blockSizeInPixels-1 do
							local spi = bit.bxor(pi, pimask)
							local spj = bit.bxor(pj, pjmask)
							local srcIndex = spi + blockSizeInPixels * (spj + blockSizeInPixels * tileIndex)
							local paletteIndex = tileSet.tileGfxBmp.buffer[srcIndex]
							if bit.band(paletteIndex, 0xf) > 0 then
								local src = tileSet.palette.v[paletteIndex]
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

function SMMap:mapSaveGraphicsBGs()
	SMMap.bitmapForTileSetAndTileMap = {}	-- clear bgBmp cache
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
		
		local bgBmp = self:mapGetBitmapForTileSetAndTileMap(tileSet, tilemap)

		-- now find the first bgBmp associated with the bg, associated with the bgTilemap ...
		-- just for the sake of getting palette info

		local img = Image(graphicsTileSizeInPixels * tilemap.width, graphicsTileSizeInPixels * tilemap.height, 3, 'unsigned char')
		img:clear()
		for y=0,graphicsTileSizeInPixels*tilemap.height-1 do
			for x=0,graphicsTileSizeInPixels*tilemap.width-1 do
				local offset = x + img.width * y
				local paletteIndex = bgBmp.dataBmp.buffer[offset]
				if bit.band(paletteIndex, 0xf) > 0 then 
					local rgb = tileSet.palette.v[paletteIndex]
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


function SMMap:mapPrintRoomBlocks()
	-- print/draw rooms
	print()
	print'all roomBlockData'
	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			print(rs.room:getIdentStr())
		end
		local w,h = roomBlockData.width, roomBlockData.height
		print(' size: '..w..','..h)
		if roomBlockData.addr then
			print(' addr: '..('%06x'):format(roomBlockData.addr))
		end

		local function printblock(data, size, width, col)
			for i=0,size-1 do
				if col and i % col == 0 then io.write' ' end
				io.write((('%02x'):format(tonumber(data[i])):gsub('0','.')))
				if i % width == width-1 then print() end 
			end
			print()
		end
		if roomBlockData.tileIndexesUsed then
			print(' tileIndexes used: '..table.keys(roomBlockData.tileIndexesUsed):sort():mapi(function(s) return ('$%03x'):format(s) end):concat', ')
		end

		print' offset to ch 3:'
		printblock(roomBlockData.v, 2, 2, 1)
		print' blocks ch 1 2:'
		printblock(roomBlockData:getBlocks12(), 2*w*h, 2*w, 2) 
		print' blocks ch 3:'
		printblock(roomBlockData:getBlocks3(), w*h, w, 1) 
		local layer2blocks = roomBlockData:getLayer2Blocks()
		if layer2blocks then
			local bytesLeft = roomBlockData:iend() - layer2blocks 
			print(' layer 2 blocks:')
			printblock(layer2blocks, math.min(2*w*h, bytesLeft), 2*w, 2)
		end
--[=[ I don't store this anymore
		if roomBlockData.tail then
			local bytesLeft = roomBlockData:iend() - roomBLockData.tail
			print(' tail ('..('$%x'):format(bytesLeft)..' bytes) =')
			print('\t\t'..range(0,bytesLeft-1):mapi(function(i)
					return ('%02x'):format(roomBlockData.tail[i])
				end):concat' ')
		end
--]=]	
		print' roomstate scrolldata:'
		for _,rs in ipairs(roomBlockData.roomStates) do
			if rs.scrollData then
				print(('  $%06x'):format(rs.addr))
				printblock(tableToByteArray(rs.scrollData), #rs.scrollData, w/blocksPerRoom, 1)
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
			--('$%06x'):format(m.addr)
			--('%04x'):format(select(2, frompc(m.addr)))
			('%02x'..levelsep..'%02x'):format(m:obj().region, m:obj().index)
	end
	local function getClusterName(roomName)
		-- graphviz clusters have to have 'cluster' as a prefix
		return 'cluster_'..roomName
	end
	local function getRoomStateName(rs)
		local bank, ofs = frompc(rs.addr)
		return ('%04x'):format(ofs)
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
				and roomDoor.type == 'door_t' 	-- otherwise, lift_t is a suffix of a lift door_t
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
--print('  roomstate_t: '..('$%06x'):format(rs.addr)..' '..rs:obj()) 
						
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
								local doorName = 'door'..('%04x'):format(select(2, frompc(roomDoor.addr)))
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
							local doorName = 'door'..('%04x'):format(select(2, frompc(roomDoor.addr)))
							local doorNodeName = roomName..':'..doorName
							local colorTag = ''
							local labelTag = '[label=""]'
							f:write('\t"', doorNodeName, '"', colorTag, labelTag, ';\n')
							edges:insert('"'..srcNodeName..'" -> "'..doorNodeName..'"'..colorTag)
							edges:insert('"'..doorNodeName..'" -> "'..dstNodeName..'"'..colorTag)
						else
							--if m.doors:last().type == 'lift_t' then
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
				return rs.room:getIdentStr()
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
			rsstrs:insert(rs.room:getIdentStr())
		end
		rsstrs = rsstrs:concat', '
		for _,plm in ipairs(plmset.plms) do
			local plmcmd = assert(tonumber(plm.cmd))
			allPLMCmds[plmcmd] = true
		end
	end
	
	print'rooms per plm_t cmd:'
	for _,plmcmd in ipairs(table.keys(allPLMCmds):sort()) do
		io.write((' %x: '):format(plmcmd))
		local sep = ''
		
		for _,plmset in ipairs(self.plmsets) do
			local rsstrs = table()
			for _,rs in ipairs(plmset.roomStates) do
				rsstrs:insert(rs.room:getIdentStr())
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
				return rs.room:getIdentStr()
			end):concat' '
		)
		for _,enemySpawn in ipairs(enemySpawnSet.enemySpawns) do	
			io.write('  '..enemySpawn)
			local enemyName = (self.enemyForPageOffset[enemySpawn.enemyPageOffset] or {}).name
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
		print(' '..('$%06x'):format(enemyGFXSet.addr)..': '
			..tolua(enemyGFXSet.name)
			:gsub('.', function(c) 
				local b = c:byte()
				if b > 127 then return '\\'..b end 
				return c 
			end)
			..' rooms: '..enemyGFXSet.roomStates:map(function(rs)
				return rs.room:getIdentStr()
			end):concat' '
		)
		for _,enemyGFX in ipairs(enemyGFXSet.enemyGFXs) do
			io.write('  '..enemyGFX)
			local enemyName = (self.enemyForPageOffset[enemyGFX.enemyPageOffset] or {}).name
			if enemyName then
				io.write(' '..tolua(enemyName))
			end
			print()
		end
	end

	-- print fx1 info
	--[[ just do this in room
	print()
	print("all fx1_t's:")
	self.fx1s:sort(function(a,b) return a.addr < b.addr end)
	for _,fx1 in ipairs(self.fx1s) do
		print(' '..('$%06x'):format(fx1.addr)..': '..fx1:obj())
	end
	--]]

	-- print bg info
	print()
	print("all bg_t's:")
	self.bgs:sort(function(a,b) return a.addr < b.addr end)
	for _,bg in ipairs(self.bgs) do
		print(' '..('$%06x'):format(bg.addr)..': '..bg.type..' '..bg:obj())
		print('  rooms: '..bg.roomStates:mapi(function(rs)
				return rs.room:getIdentStr()
			end):concat' ')
		if bg.tilemap then
			print('  tilemap.size: '..('$%x'):format(bg.tilemap:sizeof()))
			print('  tilemap.addr: '..('$%x'):format(bg.tilemap.addr))
		end
	end

	-- print room info
	print()
	print("all room_t's:")
	for _,m in ipairs(self.rooms) do
		print(' room_t '..(m.addr and (('$%06x'):format(m.addr)..' ') or '')..m:obj())
		for _,rs in ipairs(m.roomStates) do
			print('  roomstate_t: '..(rs.addr and (('$%06x'):format(rs.addr)..' ') or '')..rs:obj()) 
			print('  '..rs.roomSelect.type..': '..(rs.roomSelect.addr and (('$%06x'):format(rs.roomSelect.addr)..' ') or '')..tostring(rs.roomSelect:obj()))
			-- [[
			if rs.plmset then
				for _,plm in ipairs(rs.plmset.plms) do
					io.write('   plm_t: ')
					local plmName = plm:getName()
					if plmName then io.write(plmName..': ') end
					print(plm)
					--print('    plm scrollmod: '..('$%06x'):format(topc(self.plmBank, plm.args))..': '..plm.scrollmod:map(function(x) return ('%02x'):format(x) end):concat' ')
				end
			end
			--]]
			if rs.enemySpawnSet then	-- TODO is this required? 
				for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do	
					print('   enemySpawn_t: '
						..((self.enemyForPageOffset[enemySpawn.enemyPageOffset] or {}).name or '')
						..': '..enemySpawn)
				end
			end
			if rs.enemyGFXSet then	-- TODO required?
				print('   enemyGFXSet: '..tolua(rs.enemyGFXSet.name):gsub('.', function(c) 
					local b = c:byte()
					if b > 127 then return '\\'..b end 
					return c 
				end))
				for _,enemyGFX in ipairs(rs.enemyGFXSet.enemyGFXs) do
					print('    enemyGFX_t: '
						..tolua((self.enemyForPageOffset[enemyGFX.enemyPageOffset] or {}).name or '')
						..': '..enemyGFX)
				end
			end
			if rs.fx1set then
				for _,fx1 in ipairs(rs.fx1set.fx1s) do
					print('   fx1_t: '..fx1:obj())
				end
			end
			for _,bg in ipairs(rs.bgs) do
				print('   '..bg.type..': '..('$%06x'):format(bg.addr)..': '..bg:obj())
			end
			print('   roomSelect testCode: '..('$%02x:%04x'):format(frompc(rs.roomSelect.testCode.addr)))
			if rs.layerHandlingCode then
				print('   layerHandling: '..('$%02x:%04x'):format(frompc(rs.layerHandlingCode.addr)))
			end
		end
		for _,door in ipairs(m.doors) do
			print('  '..door.type..': '
				..('$%02x:%04x'):format(frompc(door.addr))
				..' '..door:obj())
			if door.doorCode then
				print('   code: '..('$%02x:%04x'):format(frompc(door.doorCode.addr)))
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
			print('  roomstate_t: '..('$%06x'):format(rs.addr)..' '..rs:obj()) 
		end
		for _,plm in ipairs(plmset.plms) do
			io.write('  plm_t: ')
			local plmName = plm:getName()
			if plmName then io.write(plmName..': ') end
			print(plm)
			if plm.scrollmod then
				print('  plm scrollmod: '..('$%06x'):format(topc(self.plmBank, plm.args))..': '..plm.scrollmod:map(function(x) return ('%02x'):format(x) end):concat' ')
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
			testCodeAddrs[rs.roomSelect:obj().testCodePageOffset] = true
		end
	end
	print('unique test code addrs:')
	for _,testCodePageOffset in ipairs(testCodeAddrs:keys():sort()) do
		print(('$%04x'):format(testCodePageOffset))
	end
	--]]

	--[[ debugging: print all unique door codes
	local doorcodes = table()
	for _,door in ipairs(self.doors) do
		if door.type == 'door_t' then
			doorcodes[door:obj().code] = true
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
		print(': '..tileSet:obj())
		print('  tileIndexesUsed = '..table.keys(tileSet.tileIndexesUsed):sort():mapi(function(s)
				return ('$%03x'):format(s)
			end):concat', ')
		print('  rooms used = '..tileSet.roomStates:mapi(function(rs)
				return rs.room:getIdentStr()
			end):concat', ')
	end

	print()
	print"all tileSet palettes:"
	for _,palette in ipairs(self.tileSetPalettes) do
		print(' '..('$%06x'):format(palette.addr))
		print('  count='..('$%x'):format(palette.count))
		print('  color={'..range(0,palette.count-1):mapi(function(i)
				return tostring(palette.v[i])
			end):concat', '..'}')
		print('  used by tileSets: '..palette.tileSets:mapi(function(tileSet) return ('%02x'):format(tileSet.index) end):concat' ')
	end

	print()
	print"all tileSet tilemaps:"
	for _,tilemap in ipairs(self.tileSetTilemaps) do
		print(' '..('$%06x'):format(tilemap.addr))
		print('  size='..('$%06x'):format(tilemap:sizeof()))
		print('  compressedSize='..('$%06x'):format(tilemap.compressedSize))
	end

	print()
	print"all tileSet graphicsTileSets:"
	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		print(' '..('$%06x'):format(graphicsTileSet.addr))
		print('  size='..('$%06x'):format(graphicsTileSet:sizeof()))
		print('  compressedSize='..('$%06x'):format(graphicsTileSet.compressedSize))
	end


	print()
	print"all loadStation_t's:"
	for i,lsr in ipairs(self.loadStationsForRegion) do
		print(' region='..lsr.region..' pageOffset='..('%04x'):format(lsr.pageOffset))
		for _,ls in ipairs(lsr.stations) do
			print('  '..('%06x'):format(ls.addr)..' '..ls:obj())
		end
	end
end

function SMMap:mapBuildMemoryMap(mem)
	local rom = self.rom
	
	for _,room in ipairs(self.rooms) do
		room:addMem(mem, nil, room)
		for _,rs in ipairs(room.roomStates) do
			assert(rs.roomSelect:obj())
			rs.roomSelect:addMem(mem, nil, room)
			rs:addMem(mem, nil, room)
			if rs.scrollData then
				-- sized room width x height
				mem:add(
					topc(self.scrollBank, rs:obj().scrollPageOffset),
					#rs.scrollData,
					'scrolldata',
					room)
			end
		
			-- add plmset later
			-- add fx1set later
		end
		
		mem:add(topc(self.doorAddrBank, room:obj().doorPageOffset), #room.doors * 2, 'dooraddrs', room)
	end

	for _,fx1set in ipairs(self.fx1sets) do
		local count = #fx1set.fx1s
		local size = count == 0 and 2 or count * ffi.sizeof'fx1_t'
		local rs = fx1set.roomStates[1]	
		mem:add(fx1set.addr, size, 'fx1_t', rs and rs.room)
	end

	-- loop through self.doors so we get room's and loadStation's
	for _,door in ipairs(self.doors) do
		door:addMem(mem, nil, door.destRoom)
	end

	for _,enemySpawnSet in ipairs(self.enemySpawnSets) do
		mem:add(enemySpawnSet.addr, 3 + #enemySpawnSet.enemySpawns * ffi.sizeof'enemySpawn_t', 'enemySpawn_t', enemySpawnSet.roomStates[1].room)
	end
	for _,enemyGFXSet in ipairs(self.enemyGFXSets) do
		-- 10 = 8 for name, 2 for term
		mem:add(enemyGFXSet.addr - 8, 10 + #enemyGFXSet.enemyGFXs * ffi.sizeof'enemyGFX_t', 'enemyGFX_t', enemyGFXSet.roomStates[1].room)
	end

	for _,plmset in ipairs(self.plmsets) do
		local room = plmset.roomStates[1].room
		--[[ entry-by-entry
		local addr = plmset.addr
		for _,plm in ipairs(plmset.plms) do
			mem:add(addr, ffi.sizeof'plm_t', 
				'plm_t',
				--'plm '..ffi.cast('plm_t*',rom+addr)[0], 
				room)
			addr = addr + ffi.sizeof'plm_t'
		end
		mem:add(addr, 2, 
			'plm_t term',
			--'plm '..ffi.cast('uint16_t*',rom+addr)[0], 
			room)
		--]]
		-- [[ all at once
		local len = 2 + #plmset.plms * ffi.sizeof'plm_t'
		mem:add(plmset.addr, len, 'plm_t', room)
		--]]
		for _,plm in ipairs(plmset.plms) do
			if plm.scrollmod then
				mem:add(topc(self.plmBank, plm.args), #plm.scrollmod, 'plm scrollmod', room)
			end
		end
	end
	
	for _,roomBlockData in ipairs(self.roomblocks) do
		roomBlockData:addMem(mem, 'roomblocks lz data', roomBlockData.roomStates[1].room)
	end

	for _,bg in ipairs(self.bgs) do
		bg:addMem(mem, nil, bg.roomStates[1].room)
	end

	for _,tilemap in ipairs(self.bgTilemaps) do
		local bg = tilemap.bg
		local rs = bg and bg.roomStates[1]
		tilemap:addMem(mem, 'bg tilemaps lz data', rs and rs.room or nil)
	end

	self.commonRoomGraphicsTiles:addMem(mem, 'common room graphicsTile_t lz data')
	
	self.commonRoomTilemaps:addMem(mem, 'common room tilemaps lz data')

-- [[
	-- should I do this for used palettes, not just my fixed maximum?
	-- and TODO how about declaring this write range and only writing back the tileSets used
	for _,tileSet in ipairs(self.tileSets) do
		tileSet:addMem(mem, nil, #tileSet.roomStates > 0 and tileSet.roomStates[1].room or nil)
	end

	for _,palette in ipairs(self.tileSetPalettes) do
		local rs
		for _,tileSet in ipairs(palette.tileSets) do
			rs = tileSet.roomStates[1]
			if rs then break end
		end
		palette:addMem(mem, 'tileSet palette lz data', rs and rs.room or nil)
	end

	for _,tilemap in ipairs(self.tileSetTilemaps) do
		local rs
		for _,tileSet in ipairs(tilemap.tileSets) do
			rs = tileSet.roomStates[1]
			if rs then break end
		end	
		tilemap:addMem(mem, 'tileSet tilemaps lz data', rs and rs.room or nil)
	end

	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		local rs
		for _,tileSet in ipairs(graphicsTileSet.tileSets) do
			rs = tileSet.roomStates[1]
			if rs then break end
		end	
		graphicsTileSet:addMem(mem, 'tileSet graphicsTile_t lz data', rs and rs.room or nil)
	end
--]]

	-- add load stations
	mem:add(
		topc(loadStationBank, loadStationRegionTableOffset),
		2 * #self.loadStationsForRegion,
		'load station region addrs'
	)
	for i,lsr in ipairs(self.loadStationsForRegion) do
		local region = lsr.region
		for i,ls in ipairs(lsr.stations) do
			ls:addMem(mem, nil, ls.door and ls.door.destRoom)
		end
	end
end


function SMMap:mapWriteDoorsAndFX1Sets()
	local rom = self.rom

	local writeRanges = WriteRange({
		{0x018000, 0x01abf0},	-- door_t's and fx1_t's
	}, "door_t's and fx1_t's")

	--[[
	with lift_t then you can point many offsets to one object 
	but with door_t, esp since the first field is the associated room_t offset
	I don't think you can have any duplicate doors ... actually yes, there are 3
	--]]

	-- TODO rooms point to a list of doorOffsets
	-- these can be grouped and uniquely reduced as well

	-- [[ build a map from doors to fx1's that point to the doors (for updating fx1 door pointers)
	local fx1sForDoor = {}
	for _,fx1set in ipairs(self.fx1sets) do
		for _,fx1 in ipairs(fx1set.fx1s) do
			if fx1.door then
				if not fx1sForDoor[fx1.door] then
					fx1sForDoor[fx1.door] = table()
				end
				fx1sForDoor[fx1.door]:insert(fx1)
			end
		end
	end
	--]]
	
	-- before comparing door objs, make sure the door destRoom addr is updated, so that obj compare will work for matching doors
	-- but in the event the door doesn't really have an address yet, be sure to also compare door ptrs
	-- alternatively just zero all destRoomPageOffsets as well
	for _,door in ipairs(self.doors) do
		if door.type == 'door_t' then
			door:obj().destRoomPageOffset = 
				door.destRoom and door.destRoom.addr and select(2, frompc(door.destRoom.addr))
				or 0
		end
	end

	-- [[ merge doors (and upate fx1_t's that point ot the doors) before merging fx1_t's
	-- but doors have destRoom pointers ... so make sure those match too?
	for i=#self.doors-1,1,-1 do
		local di = self.doors[i]
		for j=i+1,#self.doors do
			local dj = self.doors[j]
			if di.type == dj.type
			and di:obj() == dj:obj() 
			and di.destRoom == dj.destRoom	-- since the addrs might match, while the rooms don't, right?
			then
				print('doors '..('%06x'):format(di.addr)..' and '..('%06x'):format(dj.addr)..' are matching -- removing '..('%06x'):format(dj.addr)..'(type='..di.type..')')
				
				-- door j => door i
				
				-- do this here since i'm not tracking .door within the .fx1 (since it's a POD)
				-- so TODO make fx1 a Lua object and do a :toC() or do a Blob?
				local fx1sForDj = fx1sForDoor[dj]
				if fx1sForDj then
					for _,fx1 in ipairs(fx1sForDj) do
						fx1.door = di
						-- TODO don't update pageOffset yet ...
						fx1:obj().doorPageOffset = select(2, frompc(di.addr))
					end
					
					fx1sForDoor[di] = (fx1sForDoor[di] or table()):append(fx1sForDj)
					fx1sForDoor[dj] = nil
				end

				-- TODO get this to work
				-- until then, don't move doors or fx1s?
				-- [[
				-- but doors don't keep track of what room holds them, other than 'destRoom', which is a single pointer that lift_t doesn't have
				-- and I'm thinking only lift_t is going to hit this case
				-- TODO NOPE, there are 3 door_t's that are identical
				-- what would the point of two duplicate doors be?
				-- maybe because one is associated with a bg_t and the other is not?
				-- or plms somehow?
				-- anything that references a door by its pageoffset
				for _,room in ipairs(dj.srcRooms) do
					for k=1,#room.doors do
						if room.doors[k] == dj then
							room.doors[k] = di
						end
					end
				end
				--]]

				-- redirect loadstations that point to this door
				for _,lsr in ipairs(self.loadStationsForRegion) do
					for _,ls in ipairs(lsr.stations) do
						if ls.door == dj then
							ls.door = di
						end
					end
				end
				
				self.doors:remove(j)
				
				break
			end
		end
	end
	--]]


	-- remove empty fx1sets but one
	-- since we need a ffff marker for an empty fx1set, but we can otherwise point them all to the same fx1set
	-- (who thought this empty set marker up?  why not just null the offset?)
	--[[ or don't, since merging plms will do just this anyways
	local needsEmpty
	for i=#self.fx1sets,1,-1 do
		local fx1set = self.fx1sets[i]
		if #fx1set.fx1s == 0 then
			print('!!! removing empty fx1set !!! '..('%06x'):format(fx1set.addr))
			self.fx1sets:remove(i)
			needsEmpty = true
		end
	end
	--]]
	-- [[ remove fx1sets not referenced by any roomstates
	for i=#self.fx1sets,1,-1 do
		local fx1set = self.fx1sets[i]
		if #fx1set.roomStates == 0 then
			print('!!! removing fx1set that is never referenced !!! '..(fx1set.addr and ('%06x'):format(fx1set.addr) or '#'..i))
			self.fx1sets:remove(i)
		end
	end
	--]]
	-- make sure fx1's doorPageOffset is up to date before comparing fx1 objects
	for _,fx1set in ipairs(self.fx1sets) do
		for _,fx1 in ipairs(fx1set.fx1s) do
			fx1:obj().doorPageOffset = fx1.door and fx1.door.addr and select(2, frompc(fx1.door.addr)) or 0
		end
	end
	-- [[ get rid of any duplicate fx1sets
	-- seems the only duplicates are the empty sets
	-- (which do still need their own terminator)
	-- TODO find if setting fx1PageOffset to 0 makes it empty?
	for i=#self.fx1sets-1,1,-1 do
		local fi = self.fx1sets[i]
		for j=i+1,#self.fx1sets do
			local fj = self.fx1sets[j]
			if #fi.fx1s == #fj.fx1s then
				local differ
				for k=1,#fi.fx1s do
					-- compare objs and pointers, in case the pageOffset is matching in the case of new unwritten objects
					if not (
						fi.fx1s[k]:obj() == fj.fx1s[k]:obj() 
						and fi.fx1s[k].door == fj.fx1s[k].door
					)
					then
						differ = true
						break
					end
				end
				if not differ then
					local fiaddr = fi.addr and ('$%06x'):format(fi.addr) or '#'..i
					local fjaddr = fj.addr and ('$%06x'):format(fj.addr) or '#'..j
					print('fx1sets '..fiaddr..' and '..fjaddr..' are matching -- removing '..fjaddr..' (size is '..#fi.fx1s..')')
					local bank, ofs = frompc(fi.addr)
					assert(bank == self.fx1Bank)
					for _,rs in ipairs(table(fj.roomStates)) do
						-- TODO update here, or upon writing of roomstate?
						rs:obj().fx1PageOffset = ofs
						--rs:ptr().fx1PageOffset = ofs
						rs:setFX1Set(fi)
					end
					self.fx1sets:remove(j)
					break
				end
			end
		end
	end
	--]]

	for _,fx1set in ipairs(self.fx1sets) do
		local empty = #fx1set.fx1s == 0
		local bytesToWrite = empty and 2 or #fx1set.fx1s * ffi.sizeof'fx1_t'
		local addr, endaddr = writeRanges:get(bytesToWrite)
		fx1set.addr = addr
		local bank, ofs = frompc(fx1set.addr)
		assert(bank == self.fx1Bank)

		if empty then
			ffi.cast('uint16_t*', rom + addr)[0] = 0xffff	-- term
			addr = addr + 2
		else
			for _,fx1 in ipairs(fx1set.fx1s) do
				fx1.addr = addr
				fx1:writeToROM()
				addr = addr + ffi.sizeof'fx1_t'
			end
		end
		assert(addr == endaddr)

		for _,rs in ipairs(fx1set.roomStates) do
			rs:obj().fx1PageOffset = ofs
			-- don't write ptr now.  write in mapWriteRooms() instead
		end
	end


	-- TODO should I do this in mapWriteRooms()
	-- in the original, fx1 writes first, then door, (then fx1, then door)
	-- I'm not sure if door pageofs has a test for > or >= 0x8000 so I'll write fx1 first
	for _,door in ipairs(self.doors) do
		local addr, endaddr = writeRanges:get(door:sizeof())
		door.addr = addr
		door:writeToROM()
	end

	-- now that we've written/moved doors, update fx1 door pageoffsets 
	for _,fx1set in ipairs(self.fx1sets) do
		for _,fx1 in ipairs(fx1set.fx1s) do
			local doorPageOffset = fx1.door and fx1.door.addr and select(2, frompc(fx1.door.addr)) or 0
			fx1:obj().doorPageOffset = doorPageOffset
			-- and since fx1 is already written, update :ptr() as well
			fx1:ptr().doorPageOffset  = doorPageOffset
		end
	end

-- [[
	-- now that i've rearranged all doors, update plm pointers
	-- I think I'll update roomstate door pointers during roomstate write later
	-- but right now I don't move bg_t's, so I'll update those pointers here
	for _,bg in ipairs(self.bgs) do
		if bg.type == 'bg_e_t' then
			if bg.door then
				local addr = select(2, frompc(bg.door.addr))
				bg:obj().doorPageOffset = addr
				bg:ptr().doorPageOffset = addr
			else
				-- and if it's not?  then we shouldn't be using bg_e_t...
			end
		end
	end
--]]

	writeRanges:print()
end

function SMMap:mapWritePLMSets(roomBankWriteRanges)
	local rom = self.rom

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
					if eyedoor then
						print("WARNING - you have more than one eye door in a room")
					else
						eyedoor = plm
					end
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
--print("used a total of "..doorid.." special and non-special doors")	
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
				rs:obj().plmPageOffset = 0
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
					local bank, ofs = frompc(pi.addr)
					assert(bank == self.plmBank)
					-- TODO no need, since we are about to move and rewrite these anyways?
					for _,rs in ipairs(table(pj.roomStates)) do
						rs:obj().plmPageOffset = ofs
						--rs:ptr().plmPageOffset = ofs
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
	for _,plmset in ipairs(self.plmsets) do
		local bytesToWrite = #plmset.plms * ffi.sizeof'plm_t' + 2	-- +2 for null term
		local addr, endaddr = roomBankWriteRanges:get(bytesToWrite)
		plmset.addr = addr
		local bank, ofs = frompc(plmset.addr)
		assert(bank == self.plmBank)

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

		-- TODO don't write now.  write in mapWriteRooms() instead
		for _,rs in ipairs(plmset.roomStates) do
			rs:obj().plmPageOffset = ofs
			--rs:ptr().plmPageOffset = ofs
		end
	end
	--]]
	-- [[ write scrollmods last, so it can fill in the holes that the plmsets can't
	-- and then update the scrollmod ptrs of the plms after
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
			addr, endaddr = roomBankWriteRanges:get(n)
			-- write
			ffi.copy(rom+addr, tableToByteArray(scrollmod), #scrollmod)
		end
		-- remember
		addrForScrollMod[scrollmod] = addr
		-- update plm ptrs
		local plms = assert(allScrollMods[scrollmod])
		for _,plm in ipairs(plms) do
			assert(plm.scrollmod)
			assert(plm.cmd == sm.plmCmdValueForName.scrollmod)
			local bank, ofs = frompc(addr)
			assert(bank == self.scrollBank)
			plm.args = ofs
			plm.ptr.args = plm.args
		end
	end
	--]]
end

function SMMap:mapWriteEnemySpawnSets()
	local rom = self.rom

	-- preserve order
	self.enemySpawnSets:sort(function(a,b) return (a.addr or 0) < (b.addr or 0) end)

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
					--local piaddr = pi.addr and ('$%06x'):format(pi.addr) or '#'..i
					--local pjaddr = pj.addr and ('$%06x'):format(pj.addr) or '#'..j
					--print('enemySpawns '..piaddr..' and '..pjaddr..' are matching -- removing '..pjaddr)
					--print('updating roomState '..('%06x'):format(rs.addr))
					if pi.addr then
						local bank, ofs = frompc(pi.addr)
						assert(bank == self.enemySpawnBank)
					end
					for _,rs in ipairs(table(pj.roomStates)) do
						--rs:obj().enemySpawnPageOffset = ofs
						--rs:ptr().enemySpawnPageOffset = ofs
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
		local bank, ofs = frompc(enemySpawnSet.addr)
		assert(bank == self.enemySpawnBank)
		for _,rs in ipairs(enemySpawnSet.roomStates) do
			if ofs ~= rs:obj().enemySpawnPageOffset then
				--print('updating roomstate enemySpawn addr from '..('%04x'):format(rs:ptr().enemySpawnPageOffset)..' to '..('%04x'):format(ofs))
				-- TODO update here or at roomstate write?
				rs:obj().enemySpawnPageOffset = ofs
				--rs:ptr().enemySpawnPageOffset = ofs
			end
		end
	end
	enemySpawnWriteRanges:print()
	--]]
end

function SMMap:mapWriteEnemyGFXSets()
	local rom = self.rom
	
	-- preserve order
	self.enemyGFXSets:sort(function(a,b) return (a.addr or 0) < (b.addr or 0) end)

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
	
		local size = 2 + #enemyGFXSet.enemyGFXs * ffi.sizeof'enemyGFX_t' + (saveName and 8 or 0)
		local addr, endaddr = enemyGFXWriteRanges:get(size)
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
		local bank, ofs = frompc(enemyGFXSet.addr)
		assert(bank == self.enemyGFXBank)
		for _,rs in ipairs(enemyGFXSet.roomStates) do
			if ofs ~= rs:obj().enemyGFXPageOffset then
				--print('updating roomstate enemyGFX addr from '..('%04x'):format(rs:obj().enemyGFXPageOffset)..' to '..('%04x'):format(ofs))
				rs:obj().enemyGFXPageOffset = ofs
				--rs:ptr().enemyGFXPageOffset = ofs
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
			if byteArraysAreEqual(pi.v, pj.v) then
print("palettes "..('%04x'):format(pj.addr)..' and '..('%04x'):format(pi.addr)..' are matching -- removing '..('%04x'):format(pi.addr))
				
				for _,tileSet in ipairs(self.tileSets) do
					if tileSet.palette == pi then
						tileSet:setPalette(pj)
						-- tileSet:obj() and tileSet:ptr()'s paletteAddr24 are dangling here, but rewritten after the recompress
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
			if byteArraysAreEqual(ti.v, tj.v) then
print("tilemaps "..('%04x'):format(tj.addr)..' and '..('%04x'):format(ti.addr)..' are matching -- removing '..('%04x'):format(ti.addr))
				
				for _,tileSet in ipairs(self.tileSets) do
					if tileSet.tilemap == ti then
						tileSet:setTilemap(tj)
						-- tileSet:obj() and tileSet:ptr()'s tileAddr24 are dangling here, but rewritten after the recompress
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
			if byteArraysAreEqual(gi.v, gj.v) then
print("graphicsTileSets "..('%04x'):format(gj.addr)..' and '..('%04x'):format(gi.addr)..' are matching -- removing '..('%04x'):format(gi.addr))
				
				for _,tileSet in ipairs(self.tileSets) do
					if tileSet.graphicsTileSet == gi then
						tileSet:setGraphicsTileSet(gj)
						-- tileSet:obj() and tileSet:ptr()'s graphicsTileAddr24 are dangling here, but rewritten after the recompress
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


	--[[
	compress tileIndexes used
	we can only move a tileIndex if its destination isn't used by any other tileSets used by any roomStates used by any roomBlockData whose roomStates also use this tileSet.
	--]]


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
	local compressInfo = Blob.CompressInfo'tileSet tilemap + graphicsTileSet + palettes'

	for _,tilemap in ipairs(self.tileSetTilemaps) do
		tilemap:recompress(tileSetAndRoomBlockWriteRange, compressInfo)
		
		-- update anything dependent on this tilemap
		for _,tileSet in ipairs(tilemap.tileSets) do
			tileSet:obj().tileAddr24:frompc(tilemap.addr)

			-- TODO don't do this here, do this on write later
			tileSet:ptr().tileAddr24.bank = tileSet:obj().tileAddr24.bank
			tileSet:ptr().tileAddr24.ofs = tileSet:obj().tileAddr24.ofs
		end
	end

	for _,graphicsTileSet in ipairs(self.tileSetGraphicsTileSets) do
		graphicsTileSet:recompress(tileSetAndRoomBlockWriteRange, compressInfo)
		
		-- update anything dependent on this graphicsTileSet
		for _,tileSet in ipairs(graphicsTileSet.tileSets) do
			tileSet:obj().graphicsTileAddr24:frompc(graphicsTileSet.addr)

			-- TODO don't do this here, do this on write later
			tileSet:ptr().graphicsTileAddr24.bank = tileSet:obj().graphicsTileAddr24.bank
			tileSet:ptr().graphicsTileAddr24.ofs = tileSet:obj().graphicsTileAddr24.ofs
		end
	end

	for _,palette in ipairs(self.tileSetPalettes) do
		palette:recompress(tileSetAndRoomBlockWriteRange, compressInfo)
		
		-- update anything dependent on this palette
		for _,tileSet in ipairs(palette.tileSets) do
			tileSet:obj().paletteAddr24:frompc(palette.addr)

			-- TODO don't do this here, do this on write later
			tileSet:ptr().paletteAddr24.bank = tileSet:obj().paletteAddr24.bank
			tileSet:ptr().paletteAddr24.ofs = tileSet:obj().paletteAddr24.ofs
		end
	end

	print()
	print(compressInfo)

--[[
	-- remove duplicate tileSet_t's 
	-- TODO why is this always saying true?
	for i=#self.tileSets,2,-1 do
		local ti = self.tileSets[i]
		for j=1,#self.tileSets-1 do
			local tj = self.tileSets[j]
			if byteArraysAreEqual(ti.v, tj.v, ffi.sizeof'tileSet_t') then
print("tileSet_t "..('%02x'):format(tj.index)..' and '..('%02x'):format(ti.index)..' are matching -- removing '..('%02x'):format(ti.index))
				-- TODO
			end
		end
	end
--]]

--[[
tileSet memory ranges [incl,excl)

[0x07e6a2, 0x07e7a7) = default tileSet_t dense array location
[0x07e7a7, 0x07e7e1) = offsets to each tileSet_t

[0x1c8000, 0x1ca09d) = common room graphicsTile_t lz data
[0x1ca09d, 0x1ca634) = common room tilemapElem_t lz data

and then don't forget the bg tilemapElem_t's, which has some pockets in the data
--]]
end


function SMMap:mapWriteRooms(roomBankWriteRanges)
	local rom = self.rom


	-- compress roomstates ...
	-- for all plm scrollmods, if they have matching data then combine their addresses

	-- sort rooms by region and by index
	self.rooms:sort(function(a,b)
		if a:obj().region < b:obj().region then return true end
		if a:obj().region > b:obj().region then return false end
		return a:obj().index < b:obj().index
	end)
	-- grab and write new regions
	for _,m in ipairs(self.rooms) do
--print('room size '..('0x%x'):format(ffi.sizeof'room_t'))	
		local totalSize = ffi.sizeof'room_t'
		for _,rs in ipairs(m.roomStates) do
--print(rs.roomSelect.type..' size '..('0x%x'):format(ffi.sizeof(rs.roomSelect.type)))	
			totalSize = totalSize + rs.roomSelect:sizeof()
--print('roomstate_t size '..('0x%x'):format(ffi.sizeof'roomstate_t'))	
			totalSize = totalSize + ffi.sizeof'roomstate_t'
		end
--print('dooraddr size '..('0x%x'):format(2 * #m.doors))	
		totalSize = totalSize + 2 * #m.doors
		for _,rs in ipairs(m.roomStates) do
			if rs.roomvar then
--print('roomvar size '..('0x%x'):format(#rs.roomvar))	
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
--print('scroll size '..('0x%x'):format(m:obj().width * m:obj().height))	
					totalSize = totalSize + m:obj().width * m:obj().height
				end
			end
		end
	
		-- write m:obj()
		local reqAddr
--		if m:obj().region == 0 and m:obj().index == 0 then reqAddr = 0x0791f8 end
--		if m:obj().region == 6 and m:obj().index == 0 then reqAddr = 0x07c96e end
		local addr, endaddr = roomBankWriteRanges:get(totalSize, reqAddr)
		
		local ptr = rom + addr
		assert(frompc(addr) == self.roomBank)
		m.addr = addr
		m:ptr()[0] = m:obj()
		ptr = ptr + ffi.sizeof'room_t'

		-- write m.roomStates[1..n].roomSelect:obj()
		for _,rs in ipairs(m.roomStates) do
			local selptr = ffi.cast(rs.roomSelect.type..'*', ptr)
			selptr[0] = rs.roomSelect:obj()
			rs.roomSelect.addr = ptr - rom
			ptr = ptr + ffi.sizeof(rs.roomSelect.type)
		end
		-- write m.roomStates[n..1] (reverse order ... last roomselect matches first roomstate, and that's why last roomselect has no pointer.  the others do have roomstate addrs, but maybe keep the roomstates reverse-sequential just in case) 
		--		update roomstate2_t's and roomstate3_t's as you do this
		for i=#m.roomStates,1,-1 do
			local rs = m.roomStates[i]
			
			local roomStateAddr = ptr - rom
			local bank, ofs = frompc(roomStateAddr)
			assert(bank == self.roomStateBank)
			
			rs.addr = roomStateAddr
			rs:ptr()[0] = rs:obj()
			if rs.roomSelect.type ~= 'roomselect1_t' then
				rs.roomSelect:ptr().roomStatePageOffset = ofs	-- update previous write in rom
				rs.roomSelect:obj().roomStatePageOffset = ofs	-- update POD
			else
				assert(i == #m.roomStates, "expected only roomselect1_t to appear last, but found one not last for room "..m:getIdentStr())
			end
			ptr = ptr + ffi.sizeof'roomstate_t'
		end
	
		-- I am not writing doors yet so this doesn't matter
		-- but when I do, do it before writing rooms, or these offsets will go bad.
		-- write the dooraddrs: m.doors[i].addr.  terminator: 00 80.  reuse matching dooraddr sets between rooms.
		--		update m:obj().doorPageOffset
		-- TODO maybe write back the room_t last? so we don't have to reupdate its fields
		m:obj().doorPageOffset = select(2, frompc(ptr - rom))
		m:ptr().doorPageOffset = m:obj().doorPageOffset
		for _,door in ipairs(m.doors) do
			local bank, ofs = frompc(door.addr)
			assert(bank == self.doorBank)
			ffi.cast('uint16_t*', ptr)[0] = ofs
			-- right now door:ptr() points to the door_t object elsewhere, not to the ptr of the ptr to the door_t
			ptr = ptr + ffi.sizeof'uint16_t'
		end
		
		-- write m.roomStates[1..n].roomvar (only for grey torizo room)
		--		update m.roomStates[1..n].ptr.roomvarPageOffset
		for _,rs in ipairs(m.roomStates) do
			if rs.roomvar then
				local bank, ofs = frompc(ptr - rom)
				--assert(bank == self.plmBank)
				if bank ~= self.plmBank then
					print('DANGER DANGER - you are writing roomvar data outside the PLM bank')
				end
				rs:obj().roomvarPageOffset = ofs
				rs:ptr().roomvarPageOffset = rs:obj().roomvarPageOffset
				for _,c in ipairs(rs.roomvar) do
					ptr[0] = c
					ptr = ptr + 1
				end
			end
		end
		
		-- write m.roomStates[1..n].scrollData
		--		update m.roomStates[1..n]:obj().scrollPageOffset
		for i,rs in ipairs(m.roomStates) do
			if rs.scrollData then
				assert(rs:obj().scrollPageOffset > 1 and rs:obj().scrollPageOffset ~= 0x8000)
				assert(#rs.scrollData == m:obj().width * m:obj().height)
				local matches
				for j=1,i-1 do
					local rs2 = m.roomStates[j]
					if rs2.scrollData then
						if tablesAreEqual(rs.scrollData, rs2.scrollData) then
							matches = rs2:obj().scrollPageOffset
							break
						end
					end	
				end
				if matches then
					rs:obj().scrollPageOffset = matches
					rs:ptr().scrollPageOffset = matches
				else
					local addr = ptr - rom
					local bank, ofs = frompc(addr)
					assert(bank == self.scrollBank)
					rs:obj().scrollPageOffset = ofs
					rs:ptr().scrollPageOffset = rs:obj().scrollPageOffset
					for i=1,m:obj().width * m:obj().height do
						ptr[0] = rs.scrollData[i]
						ptr = ptr + 1
					end
				end
			end
		end

		assert(endaddr == ptr - rom)
	end

	-- now that we have repositioned our rooms,
	-- update door.destRoomPageOffset
	for _,door in ipairs(self.doors) do
		if door.destRoom then
			local bank, ofs = frompc(door.destRoom.addr)
			door:obj().destRoomPageOffset = ofs
			door:ptr().destRoomPageOffset = ofs
		end
	end

	for _,m in ipairs(self.rooms) do
		assert(m:ptr().region == m:obj().region, "regions dont match for room "..m:getIdentStr())
	end
	-- if you remove rooms but forget to remove them from rooms then you could end up here ... 
	for _,roomBlockData in ipairs(self.roomblocks) do
		for _,rs in ipairs(roomBlockData.roomStates) do
			local m = rs.room
			assert(m:ptr().region == m:obj().region, "ptr vs obj regions dont match for room:\nptr "..m:ptr()[0].."\nobj "..m:obj())
		end
	end
end

function SMMap:mapWriteRoomBlocks(writeRanges)
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
	local compressInfo = Blob.CompressInfo'rooms'
	print()
	for _,roomBlockData in ipairs(self.roomblocks) do
		
		-- readjust size based on room sizes
		-- TODO do this on load,then you don't need functions to return the ch12 and ch3 offsets -- you can just always use 2*w*h and 3*w*h
		roomBlockData:refreshRooms()
		local m1 = roomBlockData.rooms[1]
		local w, h = m1:obj().width, m1:obj().height
		for i=2,#roomBlockData.rooms do
			local mi = roomBlockData.rooms[i]
			assert(mi:obj().width == w and mi:obj().height == h)
		end
		local numBlocks = w * h * blocksPerRoom * blocksPerRoom

		local oldOffsetToCh3 = ffi.cast('uint16_t*', roomBlockData.v)[0]
		assert(oldOffsetToCh3 >= 2 * numBlocks)
		if oldOffsetToCh3 ~= 2 * numBlocks then
			local newcount = 2 + numBlocks * (roomBlockData.hasLayer2Blocks and 5 or 3)
			local newdata = ffi.new('uint8_t[?]', newcount)
			ffi.cast('uint16_t*', newdata)[0] = 2 * numBlocks
			ffi.copy(newdata + 2, roomBlockData.v + 2, 3 * numBlocks)
			if roomBlockData.hasLayer2Blocks then
				ffi.copy(newdata + 2 + 3 * numBlocks, roomBlockData.v + 2 + 3 * oldOffsetToCh3 / 2, 2 * numBlocks)
			end
			roomBlockData.v = newdata
			roomBlockData.count = newcount
			-- and now the recompression % will also include the clipped data, so it'll not exactly be strictly recompression, but also trimmed block data
		end
print('encoding roomBlockData for rooms '..roomBlockData.rooms:mapi(function(room) return room:getIdentStr() end):concat', ')
		roomBlockData:recompress(writeRanges, compressInfo)

		-- update any roomstate_t's that point to this data
		for _,rs in ipairs(roomBlockData.roomStates) do
			rs:obj().roomBlockAddr24:frompc(roomBlockData.addr)
			-- rooms havne't been written yet 
			--rs:ptr().roomBlockAddr24.bank = rs:obj().roomBlockAddr24.bank
			--rs:ptr().roomBlockAddr24.ofs = rs:obj().roomBlockAddr24.ofs
		end

	--[=[ verify that compression works by decompressing and re-compressing
		local data2, compressedSize2 = lz.decompress(rom, roomBlockData.addr)
		assert(compressedSize == compressedSize2)
		assert(ffi.sizeof(data) == ffi.sizeof(data2))
		for i=0,ffi.sizeof(data)-1 do
			assert(data[i] == data2[i])
		end
	--]=]
	end
	print()
	print(compressInfo)
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

	-- NOTE TO SELF
	-- don't validate this using state-reload, since your current room info might be moved, and then your state load is essentially corrupted
	-- only validate using reset and savefile reload
	self:mapWriteDoorsAndFX1Sets()

	-- I'm combining plm_t and room_t writeranges:
	-- [inclusive, exclusive)
	local roomBankWriteRanges = WriteRange({
		{0x78000, 0x79194},		-- plm_t's
		--{0x79194, 0x0791f8},  -- 100 bytes of layer handling code
		{0x791f8, 0x7b76a},		-- rooms of regions 0-2
		-- {0x07b76a, 0x07b971}, 	-- bg_t's (all padding in here isn't used)
		-- {0x07b971, 0x07ba37},	-- door code's
		-- {0x07ba37, 0x07bd07},	-- bg_t's (all padding in here isn't used)
		-- {0x07bd07, 0x07be3f},	-- door code's
		-- {0x07be3f, 0x07bf9e}		-- bg_t's.  within this is a 54 bytes padding, 27 of these bytes is a set of bg_t's that points from room 02/3d, which is unfinished
		-- {0x07bf9e, 0x07c116},	-- door code's
		-- {0x07c116, 0x07c215},	-- 255 bytes of main asm routines
		{0x7c215, 0x7c8c7},		-- plm_t's
		-- {0x07c8c7, 0x07c8f6},	-- layer handling code, which is L12 data
		
		-- these two functions are not pointed to by any rooms
		--  but their functions are referenced by the code at c8dd, 
		-- so this is reserved, can't be moved (without updating the code of c8dd as well)
		--  which is the layerHandlingPageOffset of room 04/37, draygon's room
		-- in other words, without some deep code introspection (and maybe some sentience)
		--  this can't be automatically moved around and updated
		-- {0x07c8f6, 0x07c8fc},	-- 6 bytes of draygon's room pausing code
		-- {0x07c8fc, 0x07c90a,	-- 14 bytes of draygon's room unpausing code 
		
		-- {0x07c90a, 0x07c98e},	-- layer handling code
		{0x7c98e, 0x7e0fd},			-- rooms of regions 3-6

		-- {0x07e0fd, 0x07e1d8},	-- bg_t's TODO verifying padding at 0x07e132 isn't used
		-- {0x07e1d8, 0x07e248},	-- door code
		-- {0x07e248, 0x07e26c},	-- bg_t
		-- {0x07e26c, 0x07e3e8},	-- door code (with padding at a few places)
		-- {0x07e3e8, 0x07e4c0},	-- bg_t
		-- {0x07e4c0, 0x07e51f},	-- door code
		-- {0x07e51f, 0x07e5e6},	-- 199 bytes of padding
		-- {0x07e5e6, 0x07e6a2},	-- room select code (with some padding)
		-- {0x07e6a2, 0x07e7a7},	-- tileSet_t's

		-- (TODO double check:) 
		-- e514-e689 = room select asm.  notice these call one another, so you can't just move them around willy nilly
		-- e68a-e82b = more tables and stuff
		
		--{0x07e82c, 0x07e85b},     -- single mdb of region 7
		-- then comes door code
		-- {0x7e87f, 0x7e880},     -- a single plm_t 2-byte terminator ... why do I think this is overlapping with some other data?
		
		{0x7e82c, 0x7e881},	-- within this region is e85b-e87e, which is assumed to be unused ... (assumed/used by what?)
		-- e88f-e99a = setup asm
		{0x7e99b, 0x80000},	-- free space: 
	
-- TODO make sure 06/00 is at $07c96e, or update whatever points to Ceres
		-- then comes door code
	}, 'plm_t+room_t')
	

	do
		local rom = self.rom
		local writeRanges = WriteRange({
			--{0x1c8000, 0x1ca634},	-- common room graphics tiles + tilemaps
			--{0x1ca634, 0x1d4629},	-- bg tilemapElem_t lz data ... have random padding but doesn't seem to be used 
			--{0x1d4629, 0x20b6f6},	-- tileSet graphicsTile_t lz data
			--{0x20b6f6, 0x212d7c},	-- tileSet tilemaps lz data
			--{0x212d7c, 0x2142bb},	-- tileSet palette rgb_t lz data
			--{0x2142bb, 0x27322e},	-- roomblocks lz data
			--{0x27322e, 0x278000},	-- padding
		
			-- the whole block:
			{0x1c8000, 0x278000},
			-- and with recompressiong only up to 0x23a02d is being used
		}, 'common room graphics tiles + tilemaps + bg tilemaps + tileSet tilemap+graphicsTileSet+palette lz data, and roomblocks lz data')
		
		local compressInfo = Blob.CompressInfo'common room graphics tiles + tilemaps + bg tilemaps'
		
		-- write back the common graphics tiles/tilemaps
		-- recompress them and see how well that works

		self.commonRoomGraphicsTiles:recompress(writeRanges, compressInfo)
--DEBUG = true		
		self.commonRoomTilemaps:recompress(writeRanges, compressInfo)
--DEBUG = false	
	
		-- now update the common room tilemap ptrs
		for _,loc in ipairs(commonRoomTilemapAddrLocs) do
			local bank, ofs = frompc(self.commonRoomTilemaps.addr)
			ffi.cast('uint16_t*', rom + loc.ofsaddr)[0] = ofs
			rom[loc.bankaddr] = bank
		end

		-- now recompress bgTilemaps
		for _,tilemap in ipairs(self.bgTilemaps) do
			tilemap:recompress(writeRanges, compressInfo)

			-- update bgTilemap pointers within the bg_t's
			tilemap.bg:ptr().addr24:frompc(tilemap.addr)
			tilemap.bg:obj().addr24:frompc(tilemap.addr)
		end

		-- update the kraid code that points to the kraid bg tilemaps
		if not self.mapKraidBGTilemapTop then
			print("WARNING - I didn't read the kraid BG tilemap correctly so I'm also not writing it")
		else
			local bank, ofs = frompc(self.mapKraidBGTilemapTop.addr)
			rom[mapKraidBGTilemapTopAddrLoc.ofs1addr] = bit.band(ofs, 0xff)
			rom[mapKraidBGTilemapTopAddrLoc.ofs2addr] = bit.rshift(ofs, 8)
			rom[mapKraidBGTilemapTopAddrLoc.bankaddr] = bank
		end
			
		if not self.mapKraidBGTilemapBottom then
			print("WARNING - I didn't read the kraid BG tilemap correctly so I'm also not writing it")
		else
			local bank, ofs = frompc(self.mapKraidBGTilemapBottom.addr)
			rom[mapKraidBGTilemapBottomAddrLoc.ofs1addr] = bit.band(ofs, 0xff)
			rom[mapKraidBGTilemapBottomAddrLoc.ofs2addr] = bit.rshift(ofs, 8)
			rom[mapKraidBGTilemapBottomAddrLoc.bankaddr] = bank
		end

		-- TODO write out the bg_t's ... but they are intermingled with door code, which can't be moved without updating addresses ... soo ...
		-- TODO TODO disassembler where I replace all jmps and jsrs and br*'s with address names and labels
		-- 			and then create a DAG call graph
		-- and then update the roomstate bg_t's

		print()
		print(compressInfo)
	
		-- write these before writing roomstates
		self:mapWriteTileSets(writeRanges)		-- tileSet_t's...
		self:mapWriteRoomBlocks(writeRanges)		-- roomBlockData ...
		
		-- output memory ranges
		writeRanges:print()
	end


	self:mapWritePLMSets(roomBankWriteRanges)

	-- do this before writing anything that uses enemy spawn sets
	self:mapWriteEnemyGFXSets()
	self:mapWriteEnemySpawnSets()

	self:mapWriteRooms(roomBankWriteRanges)

	
	-- now that we've moved some rooms around, update them in the loading station and demo section
	-- or TODO instead, lookup save stations within the rooms and write those back
	--				and also with lifts
	assert(#self.loadStationsForRegion <= loadStationRegionCount)
	do
		local rom = self.rom
		local loadStationEndPtr = topc(loadStationBank, loadStationEndOffset)
		local addr = topc(loadStationBank, loadStationRegionTableOffset) + 2 * loadStationRegionCount
		for _,lsr in ipairs(self.loadStationsForRegion) do
			lsr.pageOffset = select(2, frompc(addr))
			self.loadStationOffsetTable.v[lsr.region] = lsr.pageOffset

			for _,ls in ipairs(lsr.stations) do
				if addr >= loadStationEndPtr then
					print'WARNING - ran out of room writing the loadStations!'
					break
				end
				ls.addr = addr

				-- refresh the room from the door

				-- refresh the room
				if ls.door then
					local bank, pageofs = frompc(ls.door.destRoom.addr)
					assert(bank == self.roomBank)
					ls:obj().roomPageOffset = pageofs
				
					local bank, pageofs = frompc(ls.door.addr)
					assert(bank == self.doorBank)
					ls:obj().doorPageOffset = pageofs
				else
					ls:obj().roomPageOffset = 0
					ls:obj().doorPageOffset = 0
				end
				ls:writeToROM()
				addr = addr + ffi.sizeof'loadStation_t'
			end
			if addr >= loadStationEndPtr then break end
		end
		self.loadStationOffsetTable:writeToROM()
	end

	roomBankWriteRanges:print()
end


return SMMap
