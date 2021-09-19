local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local frompc = require 'pc'.from
local topc = require 'pc'.to
local struct = require 'struct'
local RoomState = require 'roomstate'
local Blob = require 'blob'


-- the 'mdb' defined in section 6 of metroidconstruction.com/SMMM
local room_t = struct{
	name = 'room_t',
	fields = {	-- aka mdb, aka mdb_header
		{index = 'uint8_t'},
		{region = 'uint8_t'},
		{x = 'uint8_t'},
		{y = 'uint8_t'},
		{width = 'uint8_t'},
		{height = 'uint8_t'},
		{upScroller = 'uint8_t'},
		{downScroller = 'uint8_t'},
		{gfxFlags = 'uint8_t'},
		{doorPageOffset = 'uint16_t'},
	},
}

-- roomselect testCodePageOffset is stored from $e5e6 to $e689 (inclusive)

local roomselect1_t = struct{
	name = 'roomselect1_t',
	fields = {
		{testCodePageOffset = 'uint16_t'},
	},
}

local roomselect2_t = struct{
	name = 'roomselect2_t',
	fields = {
		{testCodePageOffset = 'uint16_t'},
		{roomStatePageOffset = 'uint16_t'},
	},
}

-- this is how the mdb_format.txt describes it, but it looks like the structure might be a bit more conditional...
local roomselect3_t = struct{
	name = 'roomselect3_t',
	fields = {
		{testCodePageOffset = 'uint16_t'},		-- ptr to test code in bank $8f
		{testvalue = 'uint8_t'},
		{roomStatePageOffset = 'uint16_t'},		-- ptr to roomstate in bank $8f
	},
}


-- these are 1-1 with RoomState's
-- and contain addresses that point to RoomStates
local RoomSelect = class(Blob)
RoomSelect.count = 1 

function RoomSelect:init(args)
	RoomSelect.super.init(self, args)
	self.testCode = self.sm:codeAdd(topc(self.sm.roomBank, self:obj().testCodePageOffset))
	self.testCode.srcs:insert(self)
end


local Room = class(Blob)

Room.type = 'room_t'
Room.room_t = room_t
Room.count = 1

function Room:init(args)
	Room.super.init(self, args)
		
	self.doors = table()
	
	local sm = self.sm
	local rom = sm.rom

	-- skip to end of room_t to start reading roomstates
	local data = rom + self.addr + ffi.sizeof'room_t'

	-- roomstates
	local roomSelects = table()
	while true do
		local codepageofs = ffi.cast('uint16_t*',data)[0]
		
		local select_ctype
		if codepageofs == 0xe5e6 then 
			select_ctype = 'roomselect1_t'	-- default / end of the list
		elseif codepageofs == 0xe612
		or codepageofs == 0xe629
		or codepageofs == 0xe5eb
		then
			select_ctype = 'roomselect3_t'	-- this is for doors.  but it's not used. so whatever.
		else
			select_ctype = 'roomselect2_t'
		end

		roomSelects:insert(RoomSelect{
			sm = sm,
			addr = data - rom,
			type = select_ctype,
		})
		
		data = data + ffi.sizeof(select_ctype)

		if select_ctype == 'roomselect1_t' then break end	-- term
	end

	-- process in reverse order so plms will be saved int ehs ame order
	-- so that door indexes will be mainetained when writing out
	self.roomStates = table()
	for i=#roomSelects,1,-1 do
		local roomSelect = roomSelects[i]
		self.roomStates[i] = RoomState{
			sm = sm,
			room = self,
			roomSelect = roomSelect,
			
			-- terminator - use end of roomselects for the roomstate pointer
			-- after the last roomselect is the first roomstate_t
			-- ... pointed to by the roomselect?  nah, since the last roomselect / terminator roomselect1_t has no roomStatePageOffset
			-- uint16_t select means a terminator
			addr = roomSelect.type == 'roomselect1_t'
				and data - rom
				or topc(sm.roomStateBank, roomSelect:obj().roomStatePageOffset),
		}
	end

	-- I wonder if I can assert that all the roomstate_t's are in contiguous memory after the roomselect's ... 
	-- they sure aren't sequential
	-- they might be reverse-sequential
	-- sure enough, YES.  roomstates are contiguous and reverse-sequential from roomselect's
	--[[
	for i=1,#self.roomStates-1 do
		assert(self.roomStates[i+1]:ptr() + 1 == self.roomStates[i]:ptr())
	end
	--]]

	do -- list of door offsets
		local addr = topc(sm.doorAddrBank, self:obj().doorPageOffset)
		while true do
			local doorPageOffset = ffi.cast('uint16_t*', rom + addr)[0]
			addr = addr + 2

			-- TODO should this test be < or <= ?
			if doorPageOffset <= 0x8000 then break end

			local door = sm:mapAddDoor(topc(sm.doorBank, doorPageOffset))
			door.srcRooms:insertUnique(self)
			
			door.srcRoom = self
			self.doors:insert(door)
		end
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
