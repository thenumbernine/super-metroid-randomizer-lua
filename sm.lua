--[[
TODO wrapper for io for all super metroid stuff
right now everything is a scattered mess of globals
which makes it easier to access
but not as organized
so TODO clean up and bureaucratize
--]]

local ffi = require 'ffi'
local class = require 'ext.class'

local SM = class()

--[[
rom = c string of the ROM
--]]
function SM:init(rom)
	self.rom = rom
	
	local name = ffi.string(rom + 0x7fc0, 0x15)
	print(name)
end

return SM
