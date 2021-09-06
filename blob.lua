--[[
represents a binary region of memory in the Rom
creates a copy of its own of the data
but maintains the address back in the source ROM (for writing back)
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local lz = require 'lz'

local Blob = class()

-- default type
Blob.type = 'uint8_t'

--[[
args:
	sm
	addr
	type (optional) default uint8_t
	compressed = flag for whether to decompress
	count = if 'compressed' is not used then this is required.
			if 'compressed' is used then this is inferred from the decompressed size.

data source dilemma:
ptr?  then it can read from sources outside the rom, like compressed, but how to save addr?
rom,addr?  but then what about non-rom (compressed) sources?
I'll use the 'compressed' flag to distinguish these.

next dilemma: ffi arrays (which ffi.sizeof works) vs Lua tables (which are not contiguous in memory)?
things like tilemaps, decompressed data, etc use ffi arrays.
however room stuff like PLMSet use Lua tables.
a good balance would be using cpp/vector
but this would mean removing lots of ffi.sizeof() code and replacing it with .v and .size

--]]
function Blob:init(args)
	self.sm = assert(args.sm)
	self.addr = assert(args.addr)
	self.type = args.type	-- or class type
	self.compressed = args.compressed

	if self.compressed then
		assert(not args.count, "can't be compressed and specify count")
		
		-- TODO for some ill-formatted rooms, some old dangling rooms will still be accessible by room door pointers in the data (even if they are not in the game)
		-- and that will lead us to this function crashing
		self.data, self.compressedSize = lz.decompress(self.sm.rom, self.addr, self.type)
		
		assert(ffi.sizeof(self.data) % ffi.sizeof(self.type) == 0)
		self.count = ffi.sizeof(self.data) / ffi.sizeof(self.type)
	else
		self.count = assert(args.count)
		self.data = ffi.new(self.type..'[?]', self.count)
		ffi.copy(self.data, self.sm.rom + self.addr, self.count * ffi.sizeof(self.type))
	end
end

-- keep 'size' reserved in case I turn this into a 'ffi.cpp.vector'
function Blob:sizeof()
	return self.count * ffi.sizeof(self.type)
end

-- it's looking more and more like a vector...
function Blob:iend()
	return self.data + self.count
end

function Blob:ptr()
	return self.sm.rom + self.addr
end

function Blob:addMem(mem, ...)
	if self.compressed then
		mem:add(self.addr, self.compressedSize, ...)
	else
		mem:add(self.addr, self:sizeof(), ...)
	end
end

function Blob:recompress(writeRange, compressInfo)
	assert(self.compressed)

	local recompressed = lz.compress(self.data)
	compressInfo.totalOriginalCompressedSize = compressInfo.totalOriginalCompressedSize + self.compressedSize
	self.compressedSize = ffi.sizeof(recompressed)
	compressInfo.totalRecompressedSize = compressInfo.totalRecompressedSize + self.compressedSize
	local fromaddr, toaddr = writeRange:get(self.compressedSize)
	ffi.copy(self.sm.rom + fromaddr, recompressed, self.compressedSize)
	self.addr = fromaddr
end

return Blob
