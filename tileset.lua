local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local vector = require 'ffi.cpp.vector'
local struct = require 'super_metroid_randomizer.smstruct'
local topc = require 'super_metroid_randomizer.pc'.to
local Blob = require 'super_metroid_randomizer.blob'
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

local TileSet = class(Blob)

TileSet.type = 'tileSet_t'
TileSet.count = 1

function TileSet:init(args)
	local sm = args.sm
	local rom = sm.rom
	self.index = args.index
	assert(self.index >= 0 and self.index < sm.tileSetOffsets.count)
	
	args = table(args):setmetatable(nil)
	args.addr = topc(sm.tileSetBank, sm.tileSetOffsets.v[self.index])

	TileSet.super.init(self, args)

	-- have each room write keys here coinciding blocks
	self.roomStates = table()	-- which roomStates use this tileset

	self:setPalette(sm:mapAddTileSetPalette(self:obj().paletteAddr24:topc()))

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
	self index $0f: 06/01, 06/02, 06/03, 06/04
	self index $10: 06/01, 06/02, 06/03, 06/04
	self index $11: 06/00
	self index $12: 06/00
	self index $13: 06/05
	self index $14: 06/05
	
	so there you have it,
	ceres rooms is 1:1 with tileSets 0f-14
	and specifically
		ceres room 6-01 thru 6-04 is 1:1 with tileSets 0f-10
		ceres room 6-00 is 1:1 with tileSets 11-12
		ceres room 6-05 is 1:1 with tileSets 13-14
	--]]
	--local loadCommonRoomElements = rs.room:obj().region ~= 6 and #mode7graphicsTiles == 0
	local isCeres = self.index >= 0x0f and self.index <= 0x14		-- all ceres
	local isCeresRidleyRoom = self.index == 0x13 or self.index == 0x14
	local loadMode7 = self.index >= 0x11 and self.index <= 0x14		-- ceres rooms 6-00 and 6-05
	local loadCommonRoomElements = not isCeres
		
	self:setGraphicsTileSet(sm:mapAddTileSetGraphicsTileSet(self:obj().graphicsTileAddr24:topc()))

	--[[
	key by address, keep track of decompressed data, so that we don't have to re-decompress them
	and so I can keep track of tilesets used per decompressed region (so I can remove unused ones)

	EXCEPT for ceres space station (self 0f-14)
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
	so I wonder if that mode7 self.index if condition is even needed
	--]]
	local graphicsTileVec = vector'uint8_t'
	graphicsTileVec:insert(graphicsTileVec:iend(), self.graphicsTileSet.v, self.graphicsTileSet:iend())

	-- for self 0x11-0x14
	-- self 0x11, 0x12 = room 06/00
	-- self 0x13, 0x14 = room 06/05
	-- for these rooms, the self.tilemap.addr points to the mode7 data
	if loadMode7 then
--print('mode7 graphicsTileVec.size '..('%x'):format(graphicsTileVec.size))			
		self.mode7graphicsTiles, self.mode7tilemap = sm:graphicsLoadMode7(graphicsTileVec.v, graphicsTileVec.size)
		
		--[[ vanilla ceres ridley room layer handling, when layerHandlingPageOffset == $c97b
		used with roomstate_t's $07dd95, $07dd7b
		which are only for room_t $07dd69 06/05 -- and they are the only roomstates_t's of that room, so I can check via room
		roomstate_t $07dd95 => self $14 ... used by no one else
		roomstate_t $07dd7b => self $13 ... used by no one else
		so we can instead test by self.index here
		
		room 06/05's block tileIndex data is all value $1f anyways,
		so regardless of fixing this tileset, we still have nothing to display.
		--]]
		--if rs.layerHandlingPageOffset == 0xc97b then
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
		... which is interseting because it means that, for self $11 and $12 (only used in Ceres) we are sizing down from 0x8000 to 0x5000
		otherwise, for tileSets $0-$10, $13-$19, $1b, $1c  this is resized up from 0x4800 to 0x5000
		so ... should $11 and $12 be resized down?
		--]]
		-- all (except for $11-$14 above) tileSets are 0x4800 in size, except Kraid's room that alone uses self $0a, which is 0x8000 in size
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
		graphicsTileVec:insert(graphicsTileVec:iend(), sm.commonRoomGraphicsTiles.v, sm.commonRoomGraphicsTiles:iend())
	end

	sm:graphicsSwizzleTileBitsInPlace(graphicsTileVec.v, graphicsTileVec.size)
	
	self:setTilemap(sm:mapAddTileSetTilemap(self:obj().tileAddr24:topc()))

	local tilemapByteVec = vector'uint8_t'
	if loadCommonRoomElements then
		tilemapByteVec:insert(tilemapByteVec:iend(), sm.commonRoomTilemaps.v, sm.commonRoomTilemaps:iend())
	end
	tilemapByteVec:insert(tilemapByteVec:iend(), self.tilemap.v, self.tilemap:iend())
	
	-- 0x2000 size means 32*32*16*16 pixel sprites, so 8 bytes per 16x16 tile
--print('tilemapByteVec.size', ('$%x'):format(tilemapByteVec.size))
	self.tileGfxCount = bit.rshift(tilemapByteVec.size, 3)
	-- store as 16 x 16 x index rgb
	
	-- TODO don't do this unless you're writing out the textured map image?
	self.tileGfxBmp = sm:graphicsConvertTilemapToBitmap(
		tilemapByteVec.v,		-- tilemapElem_t[tileGfxCount][2][2]
		2,
		2 * self.tileGfxCount,
		graphicsTileVec.v)		-- each 32 bytes is a distinct 8x8 graphics tile, each pixel is a nibble

	-- bg_t's need this
	-- ... will they need this, or just the non-common portion of it?
	self.graphicsTileVec = graphicsTileVec
		
	-- TODO here - map from the graphicsTile address (should be 32-byte-aligned) to the tileIndex
	-- this way, if a background uses a graphicsTile, then we can flag all tileIndexes that are also used
	-- (it will have to map to multiple tileIndexes)
	-- used for tileIndex removal/optimization
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

return TileSet
