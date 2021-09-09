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
local config = require 'config'
local strtohex = require 'util'.strtohex

local SM = class(
	require 'sm-enemies',
	require 'sm-items',
	require 'sm-map',
	require 'sm-weapons',
	require 'sm-graphics',
	require 'sm-samus'
)

local nameAddr = 0x7fc0
local nameLen = 0x15

--[[
rom = c string of the ROM
--]]
function SM:init(rom, romlen)
	self.rom = rom
	self.romlen = romlen

	self.md5hash = strtohex(require 'md5'(rom, romlen))
	print('md5: '..self.md5hash)

	local name = ffi.string(rom + nameAddr, nameLen)
	print(name)

	self:graphicsInit()
	self:samusInit()
	self:weaponsInit()
	self:enemiesInit()
	self:mapInit()		-- do this before itemsInit
	self:itemsInit()
end

function SM:buildMemoryMap()
	local mem = MemoryMap()
	mem:add(nameAddr, nameLen, 'game name') 
	-- TODO make this return a 'memorymap' object that prints out
	self:graphicsBuildMemoryMap(mem)
	self:samusBuildMemoryMap(mem)
	self:weaponsBuildMemoryMap(mem)
	self:enemiesBuildMemoryMap(mem)
	self:itemsBuildMemoryMap(mem)
	self:mapBuildMemoryMap(mem)
	return mem
end

function SM:print()
	self:samusPrint()
	self:enemiesPrint()
	self:mapPrint()
end

return SM
