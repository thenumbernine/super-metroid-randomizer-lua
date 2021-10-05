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
local Blob = require 'blob'
local topc = require 'pc'.to
local frompc = require 'pc'.from

local SM = class(
	require 'sm-code',
	require 'sm-enemies',
	require 'sm-items',
	require 'sm-graphics',
	require 'sm-regions',
	require 'sm-map',
	require 'sm-weapons',
	require 'sm-samus'
)

--[[
rom = c string of the ROM
--]]
function SM:init(rom, romlen)
	self.rom = rom
	self.romlen = romlen

	self.md5hash = strtohex(require 'md5'(rom, romlen))
	print('md5: '..self.md5hash)

	self.nameBlob = Blob{sm=self, addr=topc(0x80, 0xffc0), count=0x15}
	print(ffi.string(self.nameBlob.v, self.nameBlob:sizeof()))

	self:codeInit()
	self:graphicsInit()
	self:samusInit()
	self:weaponsInit()
	self:enemiesInit()
	self:regionsInit()	-- do before graphicsInit
	self:mapInit()		-- do before itemsInit
	self:itemsInit()

	-- TODO do this in mapInit as you build each room?
	self:regionsBindRooms()
end

function SM:buildMemoryMap()
	local mem = MemoryMap()
	self.nameBlob:addMem(mem, 'game name')
	-- TODO make this return a 'memorymap' object that prints out
	self:codeBuildMemoryMap(mem)
	self:graphicsBuildMemoryMap(mem)
	self:samusBuildMemoryMap(mem)
	self:weaponsBuildMemoryMap(mem)
	self:enemiesBuildMemoryMap(mem)
	self:regionsBuildMemoryMap(mem)
	self:mapBuildMemoryMap(mem)
	self:itemsBuildMemoryMap(mem)
	return mem
end

function SM:print()
	self:codePrint()
	self:samusPrint()
	self:enemiesPrint()
	self:regionsPrint()
	self:mapPrint()
end

return SM
