local ffi = require 'ffi'
local bit = require 'bit'
local class = require 'ext.class'
local table = require 'ext.table'
local Blob = require 'blob'
local Palette = require 'palette'

local pc = require 'pc'
local topc = pc.to
local frompc = pc.from


local SMGraphics = {}


-- 128x128 tile indexes (0-255), each tile is [256][8][8]
local graphicsTileSizeInPixels = 8
local graphicsTileSizeInBytes = graphicsTileSizeInPixels * graphicsTileSizeInPixels / 2	-- 4 bits per pixel ... = 32 bytes



function SMGraphics:graphicsSwizzleTileBitsInPlace(ptr, size)
	-- rearrange the graphicsTiles ... but why?  why not keep them in their original order? and render the graphicsTiles + tilemap => bitmap using the original format?
	--[[
	8 pixels wide * 8 pixels high * 1/2 byte per pixel = 32 bytes per 8x8 tile
	--]]
	assert(size % graphicsTileSizeInBytes == 0)	
	
	local sprite = ffi.new('uint8_t[?]', graphicsTileSizeInBytes)
	local uint32 = ffi.new('uint32_t[1]', 0)
	local uint8 = ffi.cast('uint8_t*', uint32)
	for i=0,size-1,graphicsTileSizeInBytes do
		ffi.copy(sprite, ptr + i, graphicsTileSizeInBytes)
		-- in place convert, row by row ... why are we converting ?
		ffi.fill(ptr + i, graphicsTileSizeInBytes, 0)
		for y=0,7 do
			for x=0,7 do
				uint32[0] = 0
				
				for n=0,1 do
					for m=0,1 do
						local j = bit.bor(m, bit.lshift(n, 1))
						--[[
						u |= ((sprite[m + y<<1 + n<<4] >> x) & 1) << (((7-x)<<2)|j)
						--]]
						uint32[0] = bit.bor(
							uint32[0],
							bit.lshift(
								bit.band(
									bit.rshift(
										sprite[m+2*y+16*n],
										x
									),
									1
								),
								bit.bor(
									bit.lshift(7 - x, 2),
									j
								)
							)
						)
					end
				end
				--[[
				dst[j + 4*y + 32*index] |= u[j]
				--]]
				for j=0,3 do
					ptr[j + 4*y + i] = 
						bit.bor(
							ptr[j + 4*y + i],
							uint8[j]
						)
				end
			end
		end
	end
end



function SMGraphics:graphicsInitPauseScreen()
	-- read pause & equip screen tiles
	self.pauseAndEquipScreenTiles = Blob{rom=self.rom, addr=topc(0xb6, 0x8000), count=0x4000}
	
	-- TODO who uses this?  nobody? 
	--  or should it be merged with the prev graphicsTiles
	self.tileSelectAndPauseSpriteTiles = Blob{rom=self.rom, addr=topc(0xb6, 0xc000), count=0x2000}
	
	self.pauseScreenTilemap = Blob{rom=self.rom, addr=topc(0xb6, 0xe000), count=0x800}	-- 2 bytes per tile means 0x400 tiles = 32*32 (or some other order)
	self.equipScreenTilemap = Blob{rom=self.rom, addr=topc(0xb6, 0xe800), count=0x800}
	self.pauseScreenPalette = Palette{rom=self.rom, addr=topc(0xb6, 0xf000), count=0x100}
	-- and then b6:f200 on is free

	-- if you swizzle a buffer then don't use it (until I write an un-swizzle ... or just write the bit order into the renderer)
	self:graphicsSwizzleTileBitsInPlace(self.pauseAndEquipScreenTiles.data, self.pauseAndEquipScreenTiles:sizeof())
	self:graphicsSwizzleTileBitsInPlace(self.tileSelectAndPauseSpriteTiles.data, self.tileSelectAndPauseSpriteTiles:sizeof())
end

function SMGraphics:graphicsInit()
	self:graphicsInitPauseScreen()
end

function SMGraphics:graphicsSaveEquipScreenImages()
	local Image = require 'image'

	local tilemapWidth = 32
	local tilemapHeight = 32

	assert(tilemapWidth * tilemapHeight * 2 == self.pauseScreenTilemap:sizeof())
	self.pauseScreenBmp = ffi.new('uint8_t[?]', graphicsTileSizeInPixels * graphicsTileSizeInPixels * tilemapWidth * tilemapHeight)
	self:convertTilemapToBitmap(
		self.pauseScreenBmp,
		self.pauseScreenTilemap.data,
		self.pauseAndEquipScreenTiles.data,
		tilemapWidth,
		tilemapHeight,
		1)

	self.pauseScreenImage = Image(
		graphicsTileSizeInPixels * tilemapWidth,
		graphicsTileSizeInPixels * tilemapHeight,
		3,
		'unsigned char')
	self.pauseScreenImage:clear()
	self:indexedBitmapToRGB(
		self.pauseScreenImage.buffer,
		self.pauseScreenBmp,
		self.pauseScreenImage.width,
		self.pauseScreenImage.height,
		self.pauseScreenPalette)
	self.pauseScreenImage:save'pausescreen.png'


	assert(tilemapWidth * tilemapHeight * 2 == self.equipScreenTilemap:sizeof())
	self.equipScreenBmp = ffi.new('uint8_t[?]', graphicsTileSizeInPixels * graphicsTileSizeInPixels * tilemapWidth * tilemapHeight)
	self:convertTilemapToBitmap(
		self.equipScreenBmp,
		self.equipScreenTilemap.data,	-- which graphicsTileSet?  or should the two be combined?
		self.pauseAndEquipScreenTiles.data, --self.tileSelectAndPauseSpriteTiles.data,
		tilemapWidth,
		tilemapHeight,
		1)

	self.equipScreenImage = Image(
		graphicsTileSizeInPixels * tilemapWidth,
		graphicsTileSizeInPixels * tilemapHeight,
		3,
		'unsigned char')
	self.equipScreenImage:clear()
	self:indexedBitmapToRGB(
		self.equipScreenImage.buffer,
		self.equipScreenBmp,
		self.equipScreenImage.width,
		self.equipScreenImage.height,
		self.pauseScreenPalette)
	self.equipScreenImage:save'equipscreen.png'
end

function SMGraphics:graphicsBuildMemoryMap(mem)
	self.pauseAndEquipScreenTiles:addMem(mem, 'pause and equip screen graphics tiles')
	self.tileSelectAndPauseSpriteTiles:addMem(mem, 'tile select and pause screen graphics tiles')
	self.pauseScreenTilemap:addMem(mem, 'pause screen tilemap')
	self.equipScreenTilemap:addMem(mem, 'equip screen tilemap')
	self.pauseScreenPalette:addMem(mem, 'pause screen palette')
end


-- let SMMap use these
SMGraphics.graphicsTileSizeInPixels = graphicsTileSizeInPixels 
SMGraphics.graphicsTileSizeInBytes = graphicsTileSizeInBytes 


return SMGraphics 
