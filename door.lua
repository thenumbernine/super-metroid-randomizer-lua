local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local frompc = require 'pc'.from
local topc = require 'pc'.to
local disasm = require 'disasm'

local Door = class()

--[[
args: 
	sm = for the super metroid hack global info
	addr = right now - points to the door structure

looks like right now I am not rearranging any of the door_t or lift_t's
--]]
function Door:init(args)
	args = table(args):setmetatable(nil)
	
	local sm = args.sm
	local rom = sm.rom
	
	local addr = assert(args.addr)
	local data = rom + addr 
	local destRoomPageOffset = ffi.cast('uint16_t*', data)[0]
	-- if destRoomPageOffset == 0 then it is just a 2-byte 'lift' structure ...
	local ctype = destRoomPageOffset == 0 and 'lift_t' or 'door_t'

	self.addr = addr
	--local addr = topc(sm.doorBank, self.addr)
	
	-- derived fields:
	
	self.type = ctype
	self.ptr = ffi.cast(ctype..'*', data)
	self.obj = ffi.new(ctype, self.ptr[0])

	if ctype == 'door_t' 
	and self.ptr.code > 0x8000 
	then
		self.doorCodeAddr = topc(sm.doorCodeBank, self.ptr.code)
		self.doorCode = disasm.readUntilRet(self.doorCodeAddr, rom)
	end
end

function Door:setDestRoom(room)
	self.destRoom = room
	-- TODO don't bother do this until writing
	local bank, ofs = frompc(room.addr)
	assert(bank == self.roomBank)
	self.ptr.destRoomPageOffset = ofs
end

return Door
