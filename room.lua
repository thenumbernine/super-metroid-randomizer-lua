local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local frompc = require 'pc'.from
local topc = require 'pc'.to
local RoomState = require 'roomstate'
local Blob = require 'blob'



-- these are 1-1 with RoomState's
-- and contain addresses that point to RoomStates
local RoomSelect = class(Blob)
RoomSelect.count = 1 


local Room = class(Blob)

Room.type = 'room_t'

Room.count = 1

function Room:init(args)
	Room.super.init(self, args)
		
	self.roomStates = table()
	self.doors = table()
	
	local sm = self.sm
	local rom = sm.rom

	-- skip to end of room_t to start reading roomstates
	local data = rom + self.addr + ffi.sizeof'room_t'

	-- roomstates
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

		local roomSelect = RoomSelect{
			sm = sm,
			addr = data - rom,
			type = select_ctype,
		}
		
		local rs = RoomState{
			room = self,
			roomSelect = roomSelect,
		}
		self.roomStates:insert(rs)
		
		data = data + ffi.sizeof(select_ctype)

		if select_ctype == 'roomselect1_t' then break end	-- term
	end

	-- after the last roomselect is the first roomstate_t
	local rs = self.roomStates:last()
	-- uint16_t select means a terminator
	if rs.roomSelect.type ~= 'roomselect1_t' then
		error("expected rs.roomSelect.type==roomselect1_t, found "..rs.roomSelect.type)
	end
	rs.ptr = ffi.cast('roomstate_t*', data)
	rs.obj = ffi.new('roomstate_t', rs.ptr[0])
	data = data + ffi.sizeof'roomstate_t'

	-- then the rest of the roomstates come
	for _,rs in ipairs(self.roomStates) do
		if rs.roomSelect.type ~= 'roomselect1_t' then
			assert(not rs.ptr)
			local addr = topc(sm.roomStateBank, rs.roomSelect:obj().roomStatePageOffset)
			rs.ptr = ffi.cast('roomstate_t*', rom + addr)
			rs.obj = ffi.new('roomstate_t', rs.ptr[0])
		end

		assert(rs.ptr)
	end

	-- I wonder if I can assert that all the roomstate_t's are in contiguous memory after the roomselect's ... 
	-- they sure aren't sequential
	-- they might be reverse-sequential
	-- sure enough, YES.  roomstates are contiguous and reverse-sequential from roomselect's
	--[[
	for i=1,#self.roomStates-1 do
		assert(self.roomStates[i+1].ptr + 1 == self.roomStates[i].ptr)
	end
	--]]

	for _,rs in ipairs(self.roomStates) do
		if rs.obj.scrollPageOffset > 0x0001 and rs.obj.scrollPageOffset ~= 0x8000 then
			local addr = topc(sm.scrollBank, rs.obj.scrollPageOffset)
			local size = self:obj().width * self:obj().height
			rs.scrollData = range(size):map(function(i)
				return rom[addr+i-1]
			end)
		end
	end

	-- add plms in reverse order, because the roomstates are in reverse order of roomselects,
	-- and the plms are stored in-order with roomselects
	-- so now, when writing them out, they will be in the same order in memory as they were when being read in
	for i=#self.roomStates,1,-1 do
		local rs = self.roomStates[i]
		if rs.obj.plmPageOffset ~= 0 then
			local plmset = sm:mapAddPLMSetFromAddr(topc(sm.plmBank, rs.obj.plmPageOffset), self)
			rs:setPLMSet(plmset)
		end
	end

	-- enemySpawnSet
	-- but notice, for writing back enemy spawn sets, sometimes there's odd padding in there, like -1, 3, etc
	for _,rs in ipairs(self.roomStates) do
		local enemySpawnSet = sm:mapAddEnemySpawnSet(topc(sm.enemySpawnBank, rs.obj.enemySpawnPageOffset))
		rs:setEnemySpawnSet(enemySpawnSet)
	end
	
	for _,rs in ipairs(self.roomStates) do
		rs:setEnemyGFXSet(sm:mapAddEnemyGFXSet(topc(sm.enemyGFXBank, rs.obj.enemyGFXPageOffset)))
	end

	-- some rooms use the same fx1 ptr
	-- and from there they are read in contiguous blocks until a term is encountered
	-- so I should make these fx1sets (like plmsets)
	-- unless -- another optimization -- is, if one room's fx1's (or plms) are a subset of another,
	-- then make one set and just put the subset's at the end
	-- (unless the order matters...)
	for _,rs in ipairs(self.roomStates) do
		local startaddr = topc(sm.fx1Bank, rs.obj.fx1PageOffset)
		local addr = startaddr
		local retry
		while true do
			local cmd = ffi.cast('uint16_t*', rom+addr)[0]
			
			-- null sets are represented as an immediate ffff
			-- whereas sets of more than 1 value use 0000 as a term ...
			-- They can also be used to terminate a set of fx1_t
			if cmd == 0xffff then
				-- include terminator bytes in block length:
				rs.fx1term = true
				addr = addr + 2
				break
			end
			
			--if cmd == 0
			-- TODO this condition was in smlib, but self.doors won't be complete until after all doors have been loaded
			--or self.doors:find(nil, function(door) return door.addr == cmd end)
			--then
			if true then
				local fx1 = sm:mapAddFX1(addr)
-- this misses 5 fx1_t's
local done = fx1.ptr.doorPageOffset == 0 
				fx1.rooms:insert(self)
				rs.fx1s:insert(fx1)
				
				addr = addr + ffi.sizeof'fx1_t'

-- term of 0 past the first entry
if done then break end
			end
		end
	end

	for _,rs in ipairs(self.roomStates) do
		if rs.obj.bgPageOffset > 0x8000 then
			local addr = topc(sm.bgBank, rs.obj.bgPageOffset)
			while true do
				local bg = sm:mapAddBG(addr, rom)
				bg.roomStates:insert(rs)
				rs.bgs:insert(bg)
				addr = addr + ffi.sizeof(bg.type.name)
				if bg.obj.header == 0 then break end
			end
		end
	end

	for _,rs in ipairs(self.roomStates) do
		if rs.obj.layerHandlingPageOffset > 0x8000 then
			local addr = topc(sm.layerHandlingBank, rs.obj.layerHandlingPageOffset)
			rs.layerHandlingPageOffset = sm:mapAddLayerHandling(addr)
			rs.layerHandlingPageOffset.roomStates:insert(rs)
		end
	
		xpcall(function()
			rs:setRoomBlockData(sm:mapAddRoomBlockData(rs.obj.roomBlockAddr24:topc(), self))
		end, function(err)
			print(err..'\n'..debug.traceback())
		end)
	end

	-- list of door offsets
	local startaddr = topc(sm.doorAddrBank, self:obj().doorPageOffset)
	local addr = startaddr
	local doorPageOffset = ffi.cast('uint16_t*', rom + addr)[0]
	addr = addr + 2
	-- TODO should this test be > or >= ?
	while doorPageOffset > 0x8000 do
		self.doors:insert(sm:mapAddDoor(topc(sm.doorBank, doorPageOffset)))
		doorPageOffset = ffi.cast('uint16_t*', rom + addr)[0]
		addr = addr + 2
	end
	

	-- $079804 - 00/15 - grey torizo room - has 14 bytes here 
	-- pointed to by room[00/15].roomstate_t[#1].roomvarPageOffset
	-- has data @$986b: 0f 0a 52 00 | 0f 0b 52 00 | 0f 0c 52 00 | 00 00
	-- this is the rescue animals roomstate
	-- so this data has to do with the destructable wall on the right side
	--if roomPageOffset == 0x79804 then
	for _,rs in ipairs(self.roomStates) do
		if rs.obj.roomvarPageOffset ~= 0 then
			local d = rom + topc(sm.plmBank, rs.obj.roomvarPageOffset)
			local roomvar = table()
			repeat
				roomvar:insert(d[0])	-- x
				roomvar:insert(d[1])	-- y
				if ffi.cast('uint16_t*', d)[0] == 0 then break end
				roomvar:insert(d[2])	-- mod 1 == 0x52
				roomvar:insert(d[3])	-- mod 2 == 0x00
				-- TODO insert roomvar_t and uint16_t term (or omit term)
				d = d + 4
			until false
			-- TODO should be roomstate
			rs.roomvar = roomvar
		end
	end

	-- try to load tile graphics from rs.tileSet
	-- TODO cache this per tileSet, since there are only 256 possible, and probably much less used?
	for _,rs in ipairs(self.roomStates) do
		local tileSetIndex = rs.obj.tileSet
		local tileSet = assert(sm.tileSets[tileSetIndex+1])
		assert(tileSet.index == tileSetIndex)
		rs:setTileSet(tileSet)
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
