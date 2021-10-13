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
		{upScroller = 'uint8_t'},		-- threshold y samus must exceed to start scrolling upwards
		{downScroller = 'uint8_t'},		-- threshold y samus must exceed to start scrolling downwards
		
		--[[
		flags:
		1 = disable layer1 door transitions
		2 = reload the CRE
		4 = load extra large tilesets
		--]]
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
	
	if not self.addr then
		-- testCodePageOffset seems to coincide with the roomselect*_t type
		-- and the roomselect*_t type is always 1 for the last room
		if self.type == 'roomselect1_t' then
			self:obj().testCodePageOffset = 0xe5e6 	-- point to something that does nothing
		elseif self.type == 'roomselect2_t' then
			self:obj().testCodePageOffset = 0xe652 	-- or 0xe5ff	or 0xe669
		elseif self.type == 'roomselect3_t' then
			self:obj().testCodePageOffset = 0xe5eb	-- or 0xe612 or 0xe629
		else
			error'here'
		end
	end
	
	--[[
	with flags == 0x00 we have no OOB branches
	with flags == 0x20 we have 1 OOB branches
	--]]
	xpcall(function()
		self.testCode = self.sm:codeAdd(topc(self.sm.roomBank, self:obj().testCodePageOffset))
		self.testCode.srcs:insert(self)
	end, function(err)
		print(err..'\n'..debug.traceback())
	end)
end


local Room = class(Blob)

Room.type = 'room_t'
Room.room_t = room_t
Room.count = 1

--[[
args:
	- load from rom -
	addr = points to an address to cast the room_t to initialize it from
	
	- new clean room -
	this will make new roomstate_t and new roomblocks as well
	width 
	height
--]]
function Room:init(args)
	Room.super.init(self, args)

	if self:obj().region >= 8 then
		error("room has an invalid region: "..self:obj())
	end
	
	self.doors = table()
	self.roomStates = table()
	
	local sm = self.sm

	if self.addr then
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
				
				-- which one should we use?
				door.srcRooms:insertUnique(self)
				door.srcRoom = self
				
				self.doors:insert(door)
			end
		end
	else
		local obj = self:obj()
		self:obj().region = assert(args.region)
		local region = select(2, sm.regions:find(nil, function(region) return region.index == self:obj().region end))
		if not region then
			error("couldn't find region "..self:obj().region)
		end

		if args.index then
			self:obj().index = args.index
		else
			local usedIndexes = region.rooms:mapi(function(room) return room:obj().index end):sort()
			local last = #usedIndexes == 0 and 1 or usedIndexes:last()+1
			usedIndexes = usedIndexes:mapi(function(i) return true, i end):setmetatable(nil)
			for i=0,last do
				if not usedIndexes[i] then
					self:obj().index = i
					break
				end
				if i == last then	
					error("couldn't find any used indexes")
				end
			end
		end
		self:obj().x = assert(args.x)
		self:obj().y = assert(args.y)
		self:obj().width = assert(args.width)
		self:obj().height = assert(args.height)
		
		--[[ TODO should the Room ctor bind to region rooms?
		-- or should mapNewRoom (since mapAddRoom from addr does there too?)
		region.rooms:insert(room)
		region.roomsForTiles[x][y]:insert(room)
		--]]
		
		--[[ values used ... idk what is what
		[0]=1
		[112]=239
		[144]=19
		[160]=3
		--]]
		self:obj().upScroller = 0x70
		
		--[[ values used ... idk what is what
		[0]=1
		[160]=261
		--]]
		self:obj().downScroller = 0xa0

		--[[ values used:
		[0]=253
		[1]=2
		[2]=4
		[5]=3
		--]]
		self:obj().gfxFlags = 0

		-- not reading from a ROM source, just making a new room altogether
		self.roomStates:insert(RoomState{
			sm = sm,
			room = self,
			-- single roomselect is a terminator
			-- roomselect is just a pointer to the roomstate_t data
			-- I guess it also has some pointers for code for rooms. 
			-- TODO store this as fields in the RoomState structure?
			-- then no need to store roomSelect -- I can generate it upon write -- especially if the last roomSelect is always a terminator roomselect1_t
			roomSelect = RoomSelect{
				sm = sm,
				type = 'roomselect1_t',
			},
		})
	end
end

function Room:findDoorTo(destRoom)
	local _, door = self.doors:find(nil, function(door) 
		return door.destRoom == destRoom
	end)
	return door
end


function Room:getIdentStr()
	return ('%02x/%02x'):format(self:obj().region, self:obj().index)
end
return Room
