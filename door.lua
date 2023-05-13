local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local frompc = require 'super_metroid_randomizer.pc'.from
local topc = require 'super_metroid_randomizer.pc'.to
local struct = require 'super_metroid_randomizer.smstruct'
local Blob = require 'super_metroid_randomizer.blob'

local Door = class(Blob)

Door.directions = {
	right = 0,
	left = 1,
	down = 2,
	up = 3,
	closeBehind = 4,	-- flag
}

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
		bits i=0-6 = set elevator index 'i' as used ... from https://wiki.metroidconstruction.com/doku.php?id=super:technical_information:data_structures
		what do elevator used bits do? never noticed in the game that this mattered

		0x40 = change regions
		0x80 = elevator
		--]]
		{flags = 'uint8_t'},				-- 2

		-- Door.directions
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

-- Blob vector size
Door.count = 1

--[[
args: 
	sm = for the super metroid hack global info
	addr = right now - points to the door structure

fields:
who owns this door? either or:
	srcRooms = room owning this door
	srcLoadStations = load station owning this door

looks like right now I am not rearranging any of the door_t or lift_t's
--]]
function Door:init(args)
	args = table(args):setmetatable(nil)

	if args.addr then
		local destRoomPageOffset = ffi.cast('uint16_t*', args.sm.rom + assert(args.addr))[0]
		-- if destRoomPageOffset == 0 then it is just a 2-byte 'lift' structure ...
		-- TODO isn't that just a terminator?  how is it a lift_t?

		args.type = destRoomPageOffset == 0 and 'lift_t' or 'door_t'
	else
		args.type = args.type or 'door_t'
	end

	Door.super.init(self, args)

	if not args.addr then
		self:obj().destRoomPageOffset = 0
		self:obj().flags = 0
		self:obj().direction = 0
		self:obj().capX = 0		-- target room x offset lo
		self:obj().capY = 0		-- target room y offset lo
		self:obj().screenX = 0	-- target room x offset hi
		self:obj().screenY = 0	-- target room y offset hi
		self:obj().distToSpawnSamus = 0
		self:obj().code = 0
	end

	self.srcRooms = table()
	self.srcLoadStations = table()

	if self.type == 'door_t' 
	and self:obj().code >= 0x8000 
	then
		xpcall(function()
			self.doorCode = self.sm:codeAdd(topc(self.sm.doorCodeBank, self:obj().code))
			self.doorCode.srcs:insert(self)
		end, function(err)
			print(err..'\n'..debug.traceback())
		end)
	end
end

function Door:setDestRoom(room)
	if self.type ~= 'door_t' then return false end
		
	self.destRoom = room

	-- TODO no need to update this now at all, addr or not, this will be updated upon writing
	if room.addr then
		-- TODO TODO treat Door like all other Blobs
		-- store .obj or .data or whatever
		local bank, ofs = frompc(room.addr)
		if bank ~= sm.roomBank then
			error("setDestRoom room target had a bad address: "..(('$%06x'):format(room.addr)..' '..('$%02x:%04x'):format(frompc(room.addr)))
				..' bank='..('%02x'):format(bank)
				..' roomBank='..('%02x'):format(self.roomBank)
			)
		end
		self:obj().destRoomPageOffset = ofs
	end
	return true
end

function Door:buildRoom()
	-- TODO make sure the door is added to sm.doors before doing this
	if self.type ~= 'door_t' then return false end
	local sm = self.sm
	if not self.destRoom then
		xpcall(function()
			self.destRoom = sm:mapAddRoom(topc(sm.roomBank, self:obj().destRoomPageOffset))
		end, function(err)
			print("while loading door "..('%04x'):format(self.addr))
			print(err..'\n'..debug.traceback())
		end)
	end
	return true 
end

return Door
