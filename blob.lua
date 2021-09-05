--[[
represents a binary region of memory in the Rom
creates a copy of its own of the data
but maintains the address back in the source ROM (for writing back)
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local lz = require 'lz'

local Blob = class()

-- default ctype
Blob.ctype = 'uint8_t'

--[[
source dilemma:
ptr?  then it can read from sources outside the rom, like compressed, but how to save addr?
rom,addr?  but then what about non-rom (compressed) sources?

args:
	rom
	addr
	ctype (optional) default uint8_t
	compressed = flag for whether to decompress
	count = if 'compressed' is not used then this is required.
			if 'compressed' is used then this is inferred from the decompressed size.
--]]
function Blob:init(args)--rom, addr, count, ctype)
	local rom = assert(args.rom)
	self.addr = assert(args.addr)
	self.ctype = args.ctype	-- or class ctype
	
	if args.compressed then
		assert(not args.count, "can't be compressed and specify count")
		self.data, self.compressedSize = lz.decompress(rom, self.addr, self.ctype)
		assert(ffi.sizeof(self.data) % ffi.sizeof(self.ctype) == 0)
		self.count = ffi.sizeof(self.data) / ffi.sizeof(self.ctype)
	else
		self.count = assert(args.count)
		self.data = ffi.new(self.ctype..'[?]', self.count)
		ffi.copy(self.data, rom + self.addr, self.count * ffi.sizeof(self.ctype))
	end
end

function Blob:size()
	return self.count * ffi.sizeof(self.ctype)
end

function Blob:addMem(mem, ...)
	mem:add(self.addr, self:size(), ...)
end

return Blob
