local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local frompc = require 'pc'.from
local topc = require 'pc'.to

local Room = class()

function Room:init(args)
	self.roomStates = table()
	self.doors = table()
	for k,v in pairs(args) do
		self[k] = v
	end
end

-- [[ TODO remove these and merge Room with Blob somehow
function Room:setOffset(sm, ofs)
	assert(ofs >= 0x8000 and ofs < 0xffff, "expects a 16-bit page offset, not 24-bit")
	self.ptr = sm.rom + topc(sm.roomBank, ofs)
end

function Room:getOffset(sm)
	assert(self.ptr, "you can't get the page offset if you don't know the ptr")
	local addr = ffi.cast('uint8_t*', self.ptr) - sm.rom
	local bank, ofs = frompc(addr)
	assert(bank == sm.roomBank)
	return ofs
end
--]]

function Room:findDoorTo(destRoom)
	local _, door = self.doors:find(nil, function(door) 
		return door.destRoom == destRoom
	end)
	return door
end

return Room
