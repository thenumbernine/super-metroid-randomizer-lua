local ffi = require 'ffi'
local range = require 'ext.range'
local table = require 'ext.table'
local class = require 'ext.class'
local Blob = require 'blob'
local Palette = require 'palette'
local topc = require 'pc'.to
local disasm = require 'disasm'

local SMGraphics = require 'sm-graphics'
local graphicsTileSizeInBytes = SMGraphics.graphicsTileSizeInBytes 

local SMSamus = {}

function SMSamus:samusInit()
	
	-- animation
	-- offsets to spritemapSet_t's
	self.samusAnimTable = Blob{sm=self, addr=topc(0x92, 0x808d), count=(0x90ed - 0x808d) / 2, type='uint16_t'}

	--[==[
	spritemap format
	
	typedef struct {
		uint16_t count;
		struct {
			uint8_t xofs;
			uint8_t zero : 7;
			uint8_t sizebit : 1;
			uint8_t yofs;
			uint16_t tileIndex : 9;
			uint16_t zero2 : 3;
			uint16_t priority : 2;
			uint16_t xflip : 1;
			uint16_t yflip : 1;
		} spritemap_t[count]
	} spritemapSet_t;

	0x8000..0x808d = code
	
	0x808d..0x90ed uint16_t samusAnimTable[];
	0x90ed..0x9263 spritemapSet_t[]
	0x9263..0x945d uint16_t samusAnimTopIndexes[];		//index into samusAnimTable
	0x945d..0x9657 uint16_t samusAnimBottomIndexes[];	// "
	0x9657..0xcbee
	0xcbee..0xd7d3 = struct {
		addr24_t tiles?
		uint16_t size1;			// part 1 size, 0 implies 0x10000 bytes
		uint16_t size2;			// part 2 size, 0 implies 0 bytes
	} [];
	
		ex: first entry: 9E8000,0080,0080
		referenced by ... a lot
		what does size1 and size2 mean?  number of bytes?  number of tiles?
		tiles at 9e:8000 end at 9e:f6c0, which is 950 tiles, which is 30400 bytes
		whereas 0x80 = 128
			0x80 * 0x80 = 16384
			0x80 * 0x80 * 32 = 524288 bytes ... hmm ...
			0x80 * 32 = 4096 bytes ...

	0xd7d3..0xd91e spritemapSet_t[]
	0xd91e..0xdb48 uint16_t animIndexes? page offsets?
	
	0xdb48..0xed24 struct {
		uint8_t topIndex;		//	animTableIndex = samusAnimTopIndexes[topIndex]
		uint8_t topIndexInto;	//	spriteSetOffset = samusAnimTable[animTableIndex] <- points to the pageofs of the spritemapSet_t
								//	(spritemapSet_t*)(page + spriteSetOffset)->sprites[topIndexInto];
		
		uint8_t bottomIndex;	//	samusAnimBottomIndexes[indexOfAnimBottomIndexes] .. same
		uint8_t bottomIndexInto;
	}[][]; "Animation definitions are indexed by [Samus animation frame]"
	
	0xed24..0xedf4 code
	0xedf4..0x0000 = free
	--]==]

	-- TODO track branches and keep reading past the first RET
	-- also TODO use page size as the maxlen
--[==[
	self.samusAnimCodeAddr = topc(0x92, 0xedf4)
	self.samusAnimCode = disasm.readUntilRet(self.samusAnimCodeAddr, self.rom)
--]==]

	-- samus tiles ...
	-- where are the tilemaps?
	self.samusDeathTiles = Blob{sm=self, addr=topc(0x9b, 0x8000), count=0x9400-0x8000}	-- and then a lot more other stuff til the end of bank
	self.samusPalettes = range(0x9400, 0xa3c0, 0x20):mapi(function(ofs)
		return Palette{sm=self, addr=topc(0x9b, ofs), count=0x10}
	end)
	-- why is the last one not 16 in size?  garbage?
	self.samusPalettes:insert(Palette{sm=self, addr=topc(0x9b, 0xa3c0), count=6})
	-- then more padding	
	self.samus9BTiles = Blob{sm=self, addr=topc(0x9b, 0xe000), count=0xfda0-0xe000}	-- then padding to end of bank
	self.samus9CTiles = Blob{sm=self, addr=topc(0x9c, 0x8000), count=0xfa80-0x8000}	-- then padding to end of bank
	self.samus9DTiles = Blob{sm=self, addr=topc(0x9d, 0x8000), count=0xf780-0x8000}	-- "
	self.samus9ETiles = Blob{sm=self, addr=topc(0x9e, 0x8000), count=0xf6c0-0x8000}	-- "
	self.samus9FTiles = Blob{sm=self, addr=topc(0x9d, 0x8000), count=0xf740-0x8000}	-- "

	
	for _,tiles in ipairs{
		self.samusDeathTiles,
		self.samus9BTiles,
		self.samus9CTiles,
		self.samus9DTiles,
		self.samus9ETiles,
		self.samus9FTiles,
	} do
		-- if you swizzle a buffer then don't use it (until I write an un-swizzle ... or just write the bit order into the renderer)
		self:graphicsSwizzleTileBitsInPlace(tiles.data, tiles:sizeof())
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
		local img = self:graphicsCreateIndexedBitmapForTiles(info.tiles.data, numTiles, info.tilesWide)

		if info.tilesWide2 then
			img = self:graphicsWrapRows(img, img.width, info.tilesWide2)
		end
		
		img = self:graphicsBitmapIndexedToRGB(img, info.palette)
		
		img:save(info.name..'.png')
	end
end

function SMSamus:samusBuildMemoryMap(mem)
	self.samusAnimTable:addMem(mem, 'samusAnimTable')

--[==[
	mem:add(self.samusAnimCodeAddr, ffi.sizeof(self.samusAnimCode), 'samusAnimCode')
--]==]

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
