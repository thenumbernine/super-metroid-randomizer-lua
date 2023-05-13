--[[
represents a binary region of memory in the Rom
creates a copy of its own of the data
but maintains the address back in the source ROM (for writing back)
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local lz = require 'super_metroid_randomizer.lz'

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
	self.addr = args.addr
	self.type = args.type	-- or class type
	local sizetype = ffi.sizeof(self.type)
	
	self.compressed = args.compressed
	if self.compressed then
		assert(args.addr, "I think I still need addr to always exist for compressed blobs")
		assert(not args.count, "can't be compressed and specify count")
		
--print('data decompressing from address '..('0x%06x'):format(self.addr))
		-- TODO for some ill-formatted rooms, some old dangling rooms will still be accessible by room door pointers in the data (even if they are not in the game)
		-- and that will lead us to this function crashing
		--xpcall(function()
		self.v, self.compressedSize = lz.decompress(self.sm.rom, self.addr, self.type)
		--end, function(err)
		--	print(err..'\n'..debug.traceback())
		--end)
		local size = ffi.sizeof(self.v)
--print('data decompressed from size '..self.compressedSize..' to size '..size)
		
		assert(size % sizetype == 0)
		self.count = size / sizetype
	else
		self.count = args.count
		self.v = ffi.new(self.type..'[?]', self.count)
		if self.addr then
			ffi.copy(self.v, self.sm.rom + self.addr, self.count * sizetype)
		end
	end
end

-- keep 'size' reserved in case I turn this into a 'ffi.cpp.vector'
function Blob:sizeof()
	return self.count * ffi.sizeof(self.type)
end

-- it's looking more and more like a vector...
function Blob:iend()
	return self.v + self.count
end

function Blob:ptr()
	assert(self.addr)
	return ffi.cast(self.type..'*', self.sm.rom + self.addr)
end

-- TODO get rid of this, and just use .v[0]
function Blob:obj()
	return self.v[0]
end

function Blob:addMem(mem, name, ...)
	if not self.addr then return end -- made addr optional, so ..
	name = self.type..(name and (' '..name) or '')
	if self.compressed then
		mem:add(self.addr, self.compressedSize, name, ...)
	else
		mem:add(self.addr, self:sizeof(), name, ...)
	end
end


-- used in Blob:recompress()
local CompressInfo = class()

function CompressInfo:init(name)
	self.name = name
	self.totalOriginalCompressedSize = 0
	self.totalRecompressedSize = 0
end

function CompressInfo:__tostring()
	return self.name..' recompressed from '..self.totalOriginalCompressedSize..' to '..self.totalRecompressedSize..
		', saving '..(self.totalOriginalCompressedSize - self.totalRecompressedSize)..' bytes '
		..'(new data is '..math.floor(self.totalRecompressedSize/self.totalOriginalCompressedSize*100)..'% of original size)'
end

Blob.CompressInfo = CompressInfo


-- TODO rename this more to 'alloc' and 'writeToROM'
function Blob:recompress(writeRange, compressInfo)
	assert(self.compressed)
	local recompressed = lz.compress(self.v)

	--assert(self.addr)
	-- if we had an .addr then we should also have a .compressedSize
	if self.addr then
		compressInfo.totalOriginalCompressedSize = compressInfo.totalOriginalCompressedSize + self.compressedSize
	end	
	
	self.compressedSize = ffi.sizeof(recompressed)
	compressInfo.totalRecompressedSize = compressInfo.totalRecompressedSize + self.compressedSize
	local fromaddr, toaddr = writeRange:get(self.compressedSize)
	ffi.copy(self.sm.rom + fromaddr, recompressed, self.compressedSize)
	self.addr = fromaddr
end

-- copy .v[] data back to rom[]
function Blob:writeToROM()
	assert(self.addr)
	assert(not self.compressed)
	ffi.copy(self.sm.rom + self.addr, self.v, self:sizeof())
end

return Blob
