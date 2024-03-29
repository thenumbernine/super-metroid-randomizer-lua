local ffi = require 'ffi'
local class = require 'ext.class'
local Blob = require 'super_metroid_randomizer.blob'
local struct = require 'super_metroid_randomizer.smstruct'


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

Palette.type = 'rgb_t' 

-- read decompressed data from an abs addr in mem
-- TODO abstract read source to be compressed/uncompressed
function Palette:init(args)
	assert(not args.type)
	Palette.super.init(self, args)
end

return Palette
