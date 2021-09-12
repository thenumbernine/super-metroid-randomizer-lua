local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local frompc = require 'pc'.from
local topc = require 'pc'.to
local disasm = require 'disasm'
local struct = require 'struct'


local Door = class()

-- described in section 12 of metroidconstruction.com/SMMM
-- if a user touches a xx-9x-yy tile then the number in yy (3rd channel) is used to lookup the door_t to see where to go
-- This isn't the door so much as the information associated with its destination.
-- This doesn't reference the in-room door object so much as vice-versa.
-- I'm tempted to call this 'exit_t' ... since you don't need a door
Door.door_t = struct{
	name = 'door_t',
	fields = {
		{destRoomPageOffset = 'uint16_t'},				-- 0: points to the room_t to transition into
		
	--[[
	0x40 = change regions
	0x80 = elevator
	--]]
		{flags = 'uint8_t'},				-- 2

	--[[
	0 = right
	1 = left
	2 = down
	3 = up
	| 0x04 flag = door closes behind samus
	--]]
		{direction = 'uint8_t'},			-- 3
		
		{capX = 'uint8_t'},					-- 4	target room x offset lo to place you at
		{capY = 'uint8_t'},					-- 5	target room y offset lo
		{screenX = 'uint8_t'},				-- 6	target room x offset hi
		{screenY = 'uint8_t'},				-- 7	target room y offset hi
		{distToSpawnSamus = 'uint16_t'},	-- 9	distance from door to spawn samus
		{code = 'uint16_t'},				-- A	custom asm for the door
	},
}

-- this is what the metroid ROM map says ... "Elevator thing"
-- two dooraddrs point to a uint16_t of zero, at $0188fc and $01a18a, and they point to structs that only take up 2 bytes
-- you find it trailing the door_t corresponding with the lift
Door.lift_t = struct{
	name = 'lift_t',
	fields = {
		{zero = 'uint16_t'},
	},
}



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
