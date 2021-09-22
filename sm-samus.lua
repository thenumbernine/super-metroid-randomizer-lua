--[==[
page 0x92

spritemap format

0x8000..0x808d = code

0x808d..0x90ed uint16_t samusAnimOffsetTable[];
0x90ed..0x9263 spritemapSet_t[]

0x9263..0x945d uint16_t samusAnimTopIndexes[];		//index into samusAnimOffsetTable
0x945d..0x9657 uint16_t samusAnimBottomIndexes[];	// "

0x9657..0xcbee spritemapSet_t[]

0xcbee..0xd7d3 samusDMAEntry_t[] 						<- indexed into by samusTopDMASetOffset[] and samusBottomDMASetOffset[]
0xd7d3..0xd91e spritemapSet_t[]
0xd91e..0xd938 uint16_t samusTopDMASetOffset[]
0xd938..0xd94e uint16_t samusBottomDMASetOffset[]

-- offsets that point into animLookups[]
0xd94e..0xdb48 uint16_t samusOffsetInfoAnimLookup[]

-- first indexes into samusBottomDMASetOffset[], which is an offset to a samusDMAEntry_t*
-- second indexes into that samusDMAEntry_t*
--  which is in one of the spritemapSet_t[]
0xdb48..0xed24 animLookup_t animLookups[]		 

0xed24..0xedf4 code
0xedf4..0x0000 = free

--]==]
local ffi = require 'ffi'
local range = require 'ext.range'
local table = require 'ext.table'
local class = require 'ext.class'
local Blob = require 'blob'
local Palette = require 'palette'
local topc = require 'pc'.to
local struct = require 'struct'

local SMGraphics = require 'sm-graphics'
local graphicsTileSizeInBytes = SMGraphics.graphicsTileSizeInBytes 


local SMSamus = {}

SMSamus.samusSpriteBank = 0x92


--[[
typedef struct {
	uint16_t count;
	spritemap_t spritemap[count];	(see sm-enemies.lua for spritemap_t def)
} spritemapSet_t;
--]]
local SpritemapSet = class()

function SpritemapSet:init(addr)
	self.addr = addr
	self.spritemaps = table()
end


function SMSamus:samusAddSpritemapSet(addr)
	for _,smset in ipairs(self.samusSpritemapSets) do
		if smset.addr == addr then
			return smet
		end
	end

	local smset = SpritemapSet(addr)

	local ptr = self.rom + addr
	local count = ffi.cast('uint16_t*', ptr)[0]
	ptr = ptr + ffi.sizeof'uint16_t'
	ptr = ffi.cast('spritemap_t*', ptr)
	for i=0,count-1 do
		smset.spritemaps:insert(ffi.new('spritemap_t', ptr[i]))
	end

	self.samusSpritemapSets:insert(smset)
	return smset
end

--[[
ex: first entry: 9E8000,0080,0080
referenced by ... a lot
what does size1 and size2 mean?  number of bytes?  number of tiles?
tiles at 9e:8000 end at 9e:f6c0, which is 950 tiles, which is 30400 bytes
whereas 0x80 = 128
	0x80 * 0x80 = 16384
	0x80 * 0x80 * 32 = 524288 bytes ... hmm ...
	0x80 * 32 = 4096 bytes ...
--]]
local samusDMAEntry_t = struct{
	name = 'samusDMAEntry_t',
	fields = {
		{tiles = 'addr24_t'},
		{size1 = 'uint16_t'},			-- part 1 size, 0 implies 0x10000 bytes
		{size2 = 'uint16_t'},			-- part 2 size, 0 implies 0 bytes
	},
}	

--[[
typedef struct {
} animLookup_t;
--]]
local animLookup_t = struct{
	name = 'animLookup_t',
	fields = {
		{bottomIndex = 'uint8_t'},
		{bottomIndexInto = 'uint8_t'},
		{topIndex = 'uint8_t'},	
		{topIndexInto = 'uint8_t'},
	}
}
assert(ffi.sizeof'animLookup_t' == 4)

function SMSamus:samusInit()

	-- 0x8000..0x808d = code
	self.samusAnimCode = self:codeAdd(topc(0x92, 0x8000))

	-- this is a collection of unique SpritemapSet's
	self.samusSpritemapSets = table()

	-- indexed into by samusAnimTopIndexes(/Bottom)[] + samus animation frame
	-- offsets to spritemapSet_t's
	self.samusAnimOffsetTable = Blob{sm=self, addr=topc(self.samusSpriteBank, 0x808d), count=(0x90ed - 0x808d) / 2, type='uint16_t'}
	-- preserve 1-1 indexing with samusAnimOffsetTable, 0-based and does allow for nils (so don't use #)
	self.samusAnimOffsetTableSpritemapSets = {}

	for i=0,self.samusAnimOffsetTable.count-1 do
		local ofs = self.samusAnimOffsetTable.v[i]
		assert(ofs == 0 or (ofs >= 0x8000 and ofs < 0x10000))
		if ofs == 0 then
			-- hmm, these can be compressed out, right?
			-- remove all indexes to them from the top and bottom index arrays
		else
			self.samusAnimOffsetTableSpritemapSets[i] = self:samusAddSpritemapSet(topc(self.samusSpriteBank, ofs))
		end
	end

	-- indexed by "samus pose"
	-- indexes into samusAnimOffsetTable[]
	self.samusAnimTopIndexes = Blob{sm=self, addr=topc(0x92, 0x9263), count=(0x945d-0x9263)/2, type='uint16_t'}
	self.samusAnimBottomIndexes = Blob{sm=self, addr=topc(0x92, 0x945d), count=(0x9657-0x945d)/2, type='uint16_t'}

	-- offset to samusDMAEntry_t's ... which I haven't loaded yet ...
	self.samusTopDMASetOffset = Blob{sm=self, addr=topc(0x92, 0xd91e), count=13, type='uint16_t'}
	self.samusBottomDMASetOffset = Blob{sm=self, addr=topc(0x92, 0xd938), count=11, type='uint16_t'}

	self.samusAnimOfs = Blob{sm=self, addr=topc(0x92, 0xd94e), count=(0xdb48-0xd94e)/2, type='uint16_t'}

	-- this points into samusTopDMASetOffset and samusBottomDMASetOffset 
	self.samusAnimLookups = Blob{sm=self, addr=topc(0x92, 0xdb48), count=(0xed24-0xdb48)/ffi.sizeof'animLookup_t', type='animLookup_t'}

	-- indexed by "samus animation frame"
	for i=0,self.samusAnimLookups.count-1 do
		local lookup = self.samusAnimLookups.v[i]
		
		local topDMAOffset = self.samusTopDMASetOffset.v[lookup.topIndex]
		local spriteDMABase = ffi.cast('samusDMAEntry_t*', self.rom + topc(0x92, topDMAOffset))
		local topDMA = spriteDMABase[lookup.topIndexInto]
	
		local bottomDMAOffset = self.samusBottomDMASetOffset.v[lookup.bottomIndex]
		local spriteDMABase = ffi.cast('samusDMAEntry_t*', self.rom + topc(0x92, bottomDMAOffset))
		local bottomDMA = spriteDMABase[lookup.bottomIndexInto]
	
		-- and ... now what do we do with topDMA and bottomDMA?
	end


	-- code from 92:ED24 to EDF3
	self.samusAnimCode2 = self:codeAdd(topc(0x92, 0xed24))

	-- samus tiles ...
	-- where are the tilemaps?
	self.samusDeathTiles = Blob{sm=self, addr=topc(0x9b, 0x8000), count=0x9400-0x8000}	-- and then a lot more other stuff til the end of bank
	self.samusPalettes = range(0x9400, 0xa3c0, 0x20):mapi(function(ofs)
		return Palette{sm=self, addr=topc(0x9b, ofs), count=0x10}
	end)
	-- why is the last one not 16 in size?  garbage?
	self.samusPalettes:insert(Palette{sm=self, addr=topc(0x9b, 0xa3e0), count=6})
	-- then more padding
	self.samus9BTiles = Blob{sm=self, addr=topc(0x9b, 0xe000), count=0xfda0-0xe000}	-- then padding to end of bank
	self.samus9CTiles = Blob{sm=self, addr=topc(0x9c, 0x8000), count=0xfa80-0x8000}	-- then padding to end of bank
	self.samus9DTiles = Blob{sm=self, addr=topc(0x9d, 0x8000), count=0xf780-0x8000}	-- "
	self.samus9ETiles = Blob{sm=self, addr=topc(0x9e, 0x8000), count=0xf6c0-0x8000}	-- "
	self.samus9FTiles = Blob{sm=self, addr=topc(0x9f, 0x8000), count=0xf740-0x8000}	-- "

	
	for _,tiles in ipairs{
		self.samusDeathTiles,
		self.samus9BTiles,
		self.samus9CTiles,
		self.samus9DTiles,
		self.samus9ETiles,
		self.samus9FTiles,
	} do
		-- if you swizzle a buffer then don't use it (until I write an un-swizzle ... or just write the bit order into the renderer)
		self:graphicsSwizzleTileBitsInPlace(tiles.v, tiles:sizeof())
	end
end

function SMSamus:samusSaveImages()
	for _,info in ipairs(
		table()
		:append(
			table{
				{name='samusDeathTiles', palette=self.samusPalettes[4]},
				{name='samus9BTiles', tilesWide=1, tilesWide2=32},
				{name='samus9CTiles', tilesWide=1, tilesWide2=32},
				{name='samus9DTiles', tilesWide=1, tilesWide2=32},
				{name='samus9ETiles', tilesWide=1, tilesWide2=32},
				{name='samus9FTiles', tilesWide=1, tilesWide2=32},
			}:mapi(function(info)
				info.tiles = self[info.name]
				info.palette = info.palette or self.samusPalettes[1]
				return info
			end)
		)
	) do
		assert(info.tiles:sizeof() % graphicsTileSizeInBytes == 0)
		local numTiles = info.tiles:sizeof() / graphicsTileSizeInBytes
	
		-- TODO this function can just make 8 x (8*numTiles) and just use graphicsWrapRows twice?
		local img = self:graphicsCreateIndexedBitmapForTiles(info.tiles.v, numTiles, info.tilesWide)

		if info.tilesWide2 then
			img = self:graphicsWrapRows(img, img.width, info.tilesWide2)
		end
		
		img = self:graphicsBitmapIndexedToRGB(img, info.palette)
		
		img:save(info.name..'.png')
	end
end
	
function SMSamus:samusPrint()
	print'all samus spritemapSets'
	for _,smset in ipairs(self.samusSpritemapSets) do
		print(('%06x'):format(smset.addr))
		for _,spritemap in ipairs(smset.spritemaps) do
			print(' '..spritemap)
		end
	end
end

function SMSamus:samusBuildMemoryMap(mem)
	self.samusAnimOffsetTable:addMem(mem, 'samusAnimOffsetTable')

	for _,smset in ipairs(self.samusSpritemapSets) do
		mem:add(smset.addr, 2 + #smset.spritemaps * ffi.sizeof'spritemap_t', 'spritemap_t')
	end

	self.samusAnimTopIndexes:addMem(mem, 'samusAnimTopIndexes')
	self.samusAnimBottomIndexes:addMem(mem, 'samusAnimBottomIndexes')

	self.samusTopDMASetOffset:addMem(mem, 'samusTopDMASetOffset')
	self.samusBottomDMASetOffset:addMem(mem, 'samusBottomDMASetOffset')
	self.samusAnimOfs:addMem(mem, 'samusAnimOfs')
	self.samusAnimLookups:addMem(mem, 'samusAnimLookups')

	self.samusDeathTiles:addMem(mem, 'samusDeathTiles')
	for i,palette in ipairs(self.samusPalettes) do
		palette:addMem(mem, 'samusPalette'..(i-1))
	end
	self.samus9BTiles:addMem(mem, 'samus9BTiles')
	self.samus9CTiles:addMem(mem, 'samus9CTiles')
	self.samus9DTiles:addMem(mem, 'samus9DTiles')
	self.samus9ETiles:addMem(mem, 'samus9ETiles')
	self.samus9FTiles:addMem(mem, 'samus9FTiles')
end

return SMSamus
