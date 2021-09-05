local ffi = require 'ffi'
local class = require 'ext.class'
local Blob = require 'blob'
local struct = require 'struct'


local rgb_t = struct{
	name = 'rgb_t',
	fields = {
		{r = 'uint16_t:5'},
		{g = 'uint16_t:5'},
		{b = 'uint16_t:5'},
		{a = 'uint16_t:1'},
	},
}
assert(ffi.sizeof'rgb_t' == 2)


local Palette = class(Blob)

Palette.ctype = 'rgb_t' 

-- read decompressed data from an abs addr in mem
-- TODO abstract read source to be compressed/uncompressed
function Palette:init(args)
	assert(not args.ctype)
	Palette.super.init(self, args)
end

return Palette
