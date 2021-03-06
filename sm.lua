--[[
TODO wrapper for io for all super metroid stuff
right now everything is a scattered mess of globals
which makes it easier to access
but not as organized
so TODO clean up and bureaucratize
--]]

local ffi = require 'ffi'
local class = require 'ext.class'
local MemoryMap = require 'memorymap'

local SM = class(
	require 'sm-enemies',
	require 'sm-items',
	require 'sm-map',
	require 'sm-weapons'
)

--[[
rom = c string of the ROM
--]]
function SM:init(rom)
	self.rom = rom
	
	local name = ffi.string(rom + 0x7fc0, 0x15)
	print(name)

	self:weaponsInit()
	self:enemiesInit()
	self:mapInit()		-- do this before itemsInit
	self:itemsInit()	-- itemsInit depends on mapInit
end

function SM:buildMemoryMap()
	local mem = MemoryMap()
	-- TODO make this return a 'memorymap' object that prints out
	self:weaponsBuildMemoryMap(mem)
	self:enemiesBuildMemoryMap(mem)
	self:itemsBuildMemoryMap(mem)
	self:mapBuildMemoryMap(mem)
	return mem
end

function SM:print()
	self:enemiesPrint()
	self:mapPrint()
end

return SM
