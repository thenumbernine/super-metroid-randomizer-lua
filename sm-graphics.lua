local ffi = require 'ffi'
local bit = require 'bit'
local class = require 'ext.class'
local range = require 'ext.range'
local table = require 'ext.table'
local Blob = require 'blob'
local Palette = require 'palette'
local Image = require 'image'

local pc = require 'pc'
local topc = pc.to
local frompc = pc.from


local SMGraphics = {}


-- 128x128 tile indexes (0-255), each tile is [256][8][8]
local graphicsTileSizeInPixels = 8
local graphicsTileSizeInBytes = graphicsTileSizeInPixels * graphicsTileSizeInPixels / 2	-- 4 bits per pixel ... = 32 bytes

-- let other SM traits use these
SMGraphics.graphicsTileSizeInPixels = graphicsTileSizeInPixels 
SMGraphics.graphicsTileSizeInBytes = graphicsTileSizeInBytes 


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


--[[
convert a 2D array of tilemap elements, plus a list of graphics tiles, into a bitmap

dst = destination, in uint8_t[tilemapElemSizeY*graphicsTileSizeInPixels][tilemapElemSizeX*graphicsTileSizeInPixels]
tilemapElem = source tilemap element array, tilemapElem_t[tilemapElemSizeY][tilemapElemSizeX] ... for each graphicsTile reference
graphicsTiles = source graphicsTile data ... usu 0x4800 or 0x8000 incl common data
tilemapElemSizeX = 8*8 graphicsTiles wide
tilemapElemSizeY = 8*8 graphicsTiles high

dst should be the destination indexed bitmap
tilemapElem is read from tileSet.tilemapByteVec.v (sets of 2x2), bg.tilemap.data (sets of 32x32), or whatever else
graphicsTiles should be tileSet.graphicsTileVec.v

--]]
function SMGraphics:graphicsConvertTilemapToBitmap(
	tilemap,
	tilemapElemSizeX,
	tilemapElemSizeY,
	graphicsTiles
)
	local dstImg = Image(
		graphicsTileSizeInPixels * tilemapElemSizeX,
		graphicsTileSizeInPixels * tilemapElemSizeY,
		1, 'uint8_t')

	dst = ffi.cast('uint8_t*', dstImg.buffer)
	tilemap = ffi.cast('tilemapElem_t*', tilemap)
	graphicsTiles = ffi.cast('uint8_t*', graphicsTiles)	-- 8 bytes per 32x32x4bpp graphicsTile
	local graphicsTileOffset = ffi.new'graphicsTileOffset_t'
	
	for dstSubtileY=0,tilemapElemSizeY-1 do
		local dstcol = dst
		for dstSubtileX=0,tilemapElemSizeX-1 do
			local xflip = tilemap.xflip ~= 0 and 7 or 0
			local yflip = tilemap.yflip ~= 0 and 7 or 0
			local colorIndexHi = bit.lshift(tilemap.colorIndexHi, 4)			-- 1c00h == 0001 1100:0000 0000 b, 1c00h >> 6 == 0000 0000:0111 0000
			local graphicsTileIndex = tilemap.graphicsTileIndex
			for y=0,7 do
				for x=0,7 do
					-- graphicsTileOffset = cccc cccc:ccbb baaa
					-- a = x or ~x depending on xflip
					-- b = y or ~y depending on yflip
					-- c = tilemap.graphicsTileIndex
					local graphicsTileOffset = bit.bor(
						bit.bxor(x, xflip),
						bit.lshift(bit.bxor(y, yflip), 3),
						bit.lshift(graphicsTileIndex, 6)
					)
					--graphicsTileOffset.x = bit.bxor(x, xflip)
					--graphicsTileOffset.y = bit.bxor(y, yflip)
					--graphicsTileOffset.graphicsTileIndex = graphicsTileIndex
					-- graphicsTileOffset is a nibble index
					-- so the real byte index into the graphicsTiles is ... 0ccc cccc:cccb bbaa
					-- and that means the graphicsTiles are 32 bytes each ... 8 * 8 * 4bpp / 8 bits/byte = 32 bytes
					-- and that last 0'th bit of a == (x or ~x depending on xflip) determines which nibble to use
					local colorIndexLo = graphicsTiles[bit.rshift(graphicsTileOffset, 1)]
					if bit.band(graphicsTileOffset, 1) ~= 0 then colorIndexLo = bit.rshift(colorIndexLo, 4) end
					colorIndexLo = bit.band(colorIndexLo, 0xf)
					-- so if graphicsTileOffset & 1 == 1 (i.e. if tilemap.x & 1 == 1) then we <<= 2
					--colorIndexLo = bit.band(bit.rshift(colorIndexLo, bit.lshift(bit.band(graphicsTileOffset.ptr[0], 1), 2)), 0xf)
					dstcol[x + 8 * tilemapElemSizeX * y] = bit.bor(colorIndexHi, colorIndexLo)
				end
			end
			
			dstcol = dstcol + 8
			tilemap = tilemap + 1
		end
		dst = dst + 8 * 8 * tilemapElemSizeX
	end
	
	-- [[
	-- what is this used for?  
	-- dest paletteIndex bit 1<<7 has both values 0 and 1 ...  
	-- and all palettes are 128 entries so that bit shouldn't be needed
	for i=0,8*8*tilemapElemSizeX*tilemapElemSizeY-1 do
		dstImg.buffer[i] = bit.band(dstImg.buffer[i], 0x7f)
	end
	--]]

	return dstImg
end


--[[
create w * h bitmap from an 8x8 set of graphicsTiles
--]]
function SMGraphics:graphicsCreateIndexedBitmapForTiles(
	graphicsTilePtr,
	numTiles,
	tilesWide 
)
	tilesWide = tilesWide or 16
	local tilesHigh = math.floor(numTiles / tilesWide)
	if tilesWide * tilesHigh ~= numTiles then
		error(require 'ext.tolua'{
			numTiles = numTiles,
			tilesWide = tilesWide,
			tilesHigh = tilesHigh,
		})
	end
	local tilemap = ffi.new('tilemapElem_t[?]', tilesWide * tilesHigh)
	for i=0,numTiles-1 do
		tilemap[i].graphicsTileIndex = i
		tilemap[i].colorIndexHi = 0
		tilemap[i].xflip = 0
		tilemap[i].yflip = 0
	end
	return self:graphicsConvertTilemapToBitmap(
		tilemap,						-- tilemapElem_t[tilesHigh][tilesWide]
		tilesWide,						-- tilesWide
		tilesHigh,						-- tilesHigh
		graphicsTilePtr)				-- graphicsTiles = uint8_t[tilesHigh][tilesWide][graphicsTileSizeInBytes]
end

-- tempted to move this to Image ...
function SMGraphics:graphicsBitmapIndexedToRGB(srcIndexedBmp, palette)
	local dstRgbBmp = Image(srcIndexedBmp.width, srcIndexedBmp.height, 3, 'unsigned char')
	dstRgbBmp:clear()
	for y=0,srcIndexedBmp.height-1 do
		for x=0,srcIndexedBmp.width-1 do
			local i = x + srcIndexedBmp.width * y
			local paletteIndex = srcIndexedBmp.buffer[i]
			if bit.band(paletteIndex, 0xf) > 0 then	-- is this always true?
				local rgb = palette.data[paletteIndex]
				dstRgbBmp.buffer[0 + 3 * i] = math.floor(rgb.r*255/31)
				dstRgbBmp.buffer[1 + 3 * i] = math.floor(rgb.g*255/31)
				dstRgbBmp.buffer[2 + 3 * i] = math.floor(rgb.b*255/31)
			else
				dstRgbBmp.buffer[0 + 3 * i] = 0
				dstRgbBmp.buffer[1 + 3 * i] = 0
				dstRgbBmp.buffer[2 + 3 * i] = 0
			end
		end
	end
	return dstRgbBmp
end

function SMGraphics:graphicsCreateRGBBitmapForTiles(
	graphicsTilePtr,
	numTiles,
	palette,
	tilesWide
)
	local indexedBmp = self:graphicsCreateIndexedBitmapForTiles(graphicsTilePtr, numTiles, tilesWide)
	return self:graphicsBitmapIndexedToRGB(indexedBmp, palette)
end

--[[
srcImg = source image
rowHeight = how many pixels high is a row
numDstTileCols = how many columns to wrap the rows

for rowHeight=3, numDstTileCols=2,turns 

A B
C D
E F
G H
I J
K L
...

into

A B G H
C D I J
E F K L
...

--]]
function SMGraphics:graphicsWrapRows(
	srcImg,
	tileHeight,
	numDstTileCols
)
	local channels = srcImg.channels
	local tileWidth = srcImg.width
	local numSrcTileRows = math.ceil(srcImg.height / tileHeight)
	local numDstTileRows = math.ceil(numSrcTileRows / numDstTileCols)
	local sizeofChannels = channels * ffi.sizeof(srcImg.format)
	local dstImg = Image(
		tileWidth * numDstTileCols,
		tileHeight * numDstTileRows,
		channels,
		srcImg.format)
	dstImg:clear()
	for j=0,numDstTileRows-1 do
		for i=0,numDstTileCols-1 do
			for k=0,tileHeight-1 do
				local srcY = k
					+ i * tileHeight
					+ j * tileHeight * numDstTileCols
				if srcY < srcImg.height then
					local dstX = tileWidth * i
					local dstY = k + tileHeight * j
					ffi.copy(
						dstImg.buffer + channels * (dstX + dstImg.width * dstY),
						srcImg.buffer + channels * (srcImg.width * srcY),
						sizeofChannels * tileWidth)
				end
			end
		end
	end
	return dstImg
end


function SMGraphics:graphicsInitPauseScreen()
	
	--[[
	items (2x images of 2x2 graphicsTiles (which are 8x8 each))
	in order:
	bombs
	gravity suit
	spring ball
	varia suit
	hi-jump
	screw attack
	space jump
	morph ball
	grappling
	x-ray
	speed
	charge
	ice
	wave
	plasma
	spazer
	reserve
	--]]
	self.itemTiles = Blob{sm=self, addr=topc(0x89, 0x8000), count=0x9100-0x8000}

	-- what uses this?
	self.fxTilemapPalette = Palette{sm=self, addr=topc(0x89, 0xaa02), count=(0xab02-0xaa02)/2}


	-- what tiles does this index into? the common room tiles?
	self.lavaTilemap = Blob{sm=self, addr=topc(0x8a, 0x8000), count=0x840}
	self.acidTilemap = Blob{sm=self, addr=topc(0x8a, 0x8840), count=0x840}
	self.waterTilemap = Blob{sm=self, addr=topc(0x8a, 0x9080), count=0x840}
	self.sporeTilemap = Blob{sm=self, addr=topc(0x8a, 0x98c0), count=0x840}
	self.rainTilemap = Blob{sm=self, addr=topc(0x8a, 0xa100), count=0x840}
	self.fogTilemap = Blob{sm=self, addr=topc(0x8a, 0xa940), count=0x840}
	
	self.scrollingSkyTilemaps = range(0xb180, 0xe980, 0x800):mapi(function(ofs)
		return Blob{sm=self, addr=topc(0x8a, ofs), count=0x800}
	end)
	-- and from 0xe980 - end of page is free


	-- 1-based, so -1 to get the region #
	-- 0x1000 = 4096 = 32x64 tiles
	-- and then the bottom half 32x32 is moved to the right of the top half
	self.regionTilemaps = range(0x8000,0xf000,0x1000):mapi(function(ofs)
		return Blob{sm=self, addr=topc(0xb5, ofs), count=0x1000}
	end)

	-- read pause & equip screen tiles
	self.pauseScreenTiles = Blob{sm=self, addr=topc(0xb6, 0x8000), count=0x6000}
	
	-- 2 bytes per tile means 0x400 tiles = 32*32 (or some other order)
	self.pauseScreenTilemap = Blob{sm=self, addr=topc(0xb6, 0xe000), count=0x800}
	self.equipScreenTilemap = Blob{sm=self, addr=topc(0xb6, 0xe800), count=0x800}

	-- 0x100 * 2 bytes per rgb_t = 0x200
	self.pauseScreenPalette = Palette{sm=self, addr=topc(0xb6, 0xf000), count=0x100}
	-- and then b6:f200 on is free

	for _,tiles in ipairs{
		self.itemTiles,
		self.pauseScreenTiles,
	} do
		-- if you swizzle a buffer then don't use it (until I write an un-swizzle ... or just write the bit order into the renderer)
		self:graphicsSwizzleTileBitsInPlace(tiles.data, tiles:sizeof())
	end
end

function SMGraphics:graphicsInit()
	self:graphicsInitPauseScreen()
end

function SMGraphics:graphicsSavePauseScreenImages()
	for _,info in ipairs{
		{
			name = 'itemtiles',
			tiles = self.itemTiles,
			tilesWide = 2,
			tilesWide2 = 2,
		},
		{
			name = 'pausescreentiles',
			tiles = self.pauseScreenTiles,
		},
	} do
		assert(info.tiles:sizeof() % graphicsTileSizeInBytes == 0)
		local numTiles = info.tiles:sizeof() / graphicsTileSizeInBytes
	
		-- TODO this function can just make 8 x (8*numTiles) and just use graphicsWrapRows twice?
		local img = self:graphicsCreateIndexedBitmapForTiles(info.tiles.data, numTiles, info.tilesWide)

		if info.tilesWide2 then
			img = self:graphicsWrapRows(img, img.width, info.tilesWide2)
		end
		
		img = self:graphicsBitmapIndexedToRGB(img, self.pauseScreenPalette)
		
		img:save(info.name..'.png')
	end

	for _,info in ipairs(
		table()
		:append(
			table{
				'lavaTilemap',
				'acidTilemap',
				'waterTilemap',
				'sporeTilemap',
				'rainTilemap',
				'fogTilemap',
			}:mapi(function(name)
				return {
					destName = 'effectTilemaps/'..name,
					tilemap = self[name],
					tilemapWidth = 32,
					tilemapHeight = 33,
					palette = self.pauseScreenPalette,	-- TODO ???
					tiles = self.pauseScreenTiles,		-- TODO I think this should be commonTiles
				}
			end)
		):append(
			self.scrollingSkyTilemaps:mapi(function(tilemap, i)
				return {
					destName = 'scrollingSkyTilemap'..(i-1),
					tilemap = tilemap,
					tilemapWidth = 32,
					tilemapHeight = 32,
					palette = self.pauseScreenPalette,	-- TODO ???
					tiles = self.pauseScreenTiles,		-- TODO I think this should be commonTiles
				}
			end)
		):append(
			self.regionTilemaps:mapi(function(regionTilemap,i)
				return {
					destName = 'regions/regionTilemap'..(i-1),
					tilemap = regionTilemap,
					tilemapWidth = 32,
					tilemapHeight = 64,
					palette = self.pauseScreenPalette,
					tilesWide2 = 2,
					tiles = self.pauseScreenTiles,
				}
			end)
		):append{
			{
				destName = 'pausescreen',
				tilemap = self.pauseScreenTilemap,
				tilemapWidth = 32,
				tilemapHeight = 32,
				palette = self.pauseScreenPalette,
				tiles = self.pauseScreenTiles,
			},
			{
				destName = 'equipscreen',
				tilemap = self.equipScreenTilemap,
				tilemapWidth = 32,
				tilemapHeight = 32,
				palette = self.pauseScreenPalette,
				tiles = self.pauseScreenTiles,
			}
		}
	) do
		assert(info.tilemapWidth * info.tilemapHeight * 2 == info.tilemap:sizeof())

		local img = self:graphicsConvertTilemapToBitmap(
			info.tilemap.data,
			info.tilemapWidth,
			info.tilemapHeight,
			info.tiles.data)

		img = self:graphicsBitmapIndexedToRGB(
			img, 
			info.palette
		)
		if info.tilesWide2 then
			img = self:graphicsWrapRows(img, img.width, info.tilesWide2)
		end
		img:save(info.destName..'.png')
	end
end

function SMGraphics:graphicsBuildMemoryMap(mem)
	
	self.itemTiles:addMem(mem, 'item graphics tiles')
	self.fxTilemapPalette:addMem(mem, 'fx tilemap palette')


	self.lavaTilemap:addMem(mem, 'lavaTilemap')
	self.acidTilemap:addMem(mem, 'acidTilemap')
	self.waterTilemap:addMem(mem, 'waterTilemap')
	self.sporeTilemap:addMem(mem, 'sporeTilemap')
	self.rainTilemap:addMem(mem, 'rainTilemap')
	self.fogTilemap:addMem(mem, 'fogTilemap')
	
	for _,tilemap in ipairs(self.scrollingSkyTilemaps) do
		tilemap:addMem(mem, 'scrollingSkyTilemaps')
	end

	for i,regionTilemap in ipairs(self.regionTilemaps) do
		regionTilemap:addMem(mem, 'region '..(i-1)..' tilemap')
	end

	self.pauseScreenTiles:addMem(mem, 'pause and equip screen graphics tiles')
	self.pauseScreenTilemap:addMem(mem, 'pause screen tilemap')
	self.equipScreenTilemap:addMem(mem, 'equip screen tilemap')
	self.pauseScreenPalette:addMem(mem, 'pause screen palette')
end


return SMGraphics 
