-- https://github.com/tewtal/smlib especially SMLib/ROMHandler.cs
-- metroidconstruction.com/SMMM
-- https://github.com/dansgithubuser/dansSuperMetroidLibrary/blob/master/sm.hpp
-- http://forum.metroidconstruction.com/index.php?topic=2476.0
-- http://www.metroidconstruction.com/SMMM/plm_disassembly.txt



local ffi = require 'ffi'
local struct = require 'struct'
local lz = require 'lz'
local WriteRange = require 'writerange'


local SMMap = {}


-- defined in section 6 of metroidconstruction.com/SMMM
-- mdb = 'map database' I'm guessing?
-- I am really tempted to defy convention and just call this 'room_t'
-- and then call 'rooms' => 'roomblocks' or something, since it is the per-block data
local mdb_t = struct'mdb_t'{	-- aka mdb, aka mdb_header
	{index = 'uint8_t'},		-- 0
	{region = 'uint8_t'},		-- 1
	{x = 'uint8_t'},			-- 2
	{y = 'uint8_t'},			-- 3
	{width = 'uint8_t'},		-- 4
	{height = 'uint8_t'},		-- 5
	{upScroller = 'uint8_t'},	-- 6
	{downScroller = 'uint8_t'},	-- 7
	{gfxFlags = 'uint8_t'},		-- 8
	{doors = 'uint16_t'},		-- 9 offset at bank  ... 9f?
}

-- this is how the mdb_format.txt describes it, but it looks like the structure might be a bit more conditional...
local roomselect_t = struct'roomselect_t'{
	{testcode = 'uint16_t'},	-- ptr to test code in bank $8f
	{testvalue = 'uint8_t'},
	{roomstate = 'uint16_t'},	-- ptr to alternative roomstate in bank $8f
}

local roomselect2_t = struct'roomselect2_t'{
	{testcode = 'uint16_t'},
	{roomstate = 'uint16_t'},
}

local roomstate_t = struct'roomstate_t'{
	{roomAddr = 'uint16_t'},
	{roomBank = 'uint8_t'},
	{gfxSet = 'uint8_t'},
	{musicTrack = 'uint8_t'},
	{musicControl = 'uint8_t'},
	{fx1 = 'uint16_t'},
	{enemyPop = 'uint16_t'},
	{enemySet = 'uint16_t'},
	{layer2scrollData = 'uint16_t'},	-- TODO
	
	--[[
	scroll is either a constant, or an offset in bank $8f to 1 byte per map block
	if scroll is 0 or 1 then it is a constant -- to fill all map blocks with that scroll value
	otherwise it is a ptr to an array of scroll values for each map block.
	0 = don't scroll up/down, or past the scroll==0 boundaries at all
	1 = scroll anywhere, but clip the top & bottom 2 blocks (which will hide vertical exits)
	2 = scroll anywhere at all ... but keeps samus in the middle, which makes it bad for hallways
	--]]
	{scroll = 'uint16_t'},
	
	--[[
	this is only used by the gold torizo room, and points to the extra data after mdb_t
	--]]
	{unknown = 'uint16_t'},				
	{fx2 = 'uint16_t'},					-- TODO - aka 'main asm ptr'
	{plm = 'uint16_t'},
	{bgdata = 'uint16_t'},
	{layerHandling = 'uint16_t'},
}

-- plm = 'post-load modification'
local plm_t = struct'plm_t'{
	{cmd = 'uint16_t'},
	{x = 'uint8_t'},
	{y = 'uint8_t'},
	{args = 'uint16_t'},
}

local enemyPop_t = struct'enemyPop_t'{
	{enemyAddr = 'uint16_t'},	-- matches enemies[].addr
	{x = 'uint16_t'},
	{y = 'uint16_t'},
	{initGFX = 'uint16_t'},	-- 'tilemaps'
	{prop1 = 'uint16_t'},	-- 'special'
	{prop2 = 'uint16_t'},	-- 'graphics'
	{roomArg1 = 'uint16_t'},-- 'speed 1'
	{roomArg2 = 'uint16_t'},-- 'speed 2'
}

-- what is this really?  'enemySet_t' seems like a bad name
local enemySet_t = struct'enemySet_t'{
	{enemyAddr = 'uint16_t'},	-- matches enemies[].addr
	{palette = 'uint16_t'},
}

-- http://metroidconstruction.com/SMMM/fx_values.txt
local fx1_t = struct'fx1_t'{
	-- bank $83, ptr to door data.  0 means no door-specific fx
	{doorSelect = 'uint16_t'},				-- 0
	-- starting height of water/lava/acid
	{liquidSurfaceStart = 'uint16_t'},		-- 2
	-- ending height of water
	{liquidSurfaceNew = 'uint16_t'},		-- 4

	--[[ from metroidconstruction.com/SMMM:
	how long until the water/lava/acid starts to rise or lower. For rooms with liquid, you must use a value between 01 (instantly) and FF (a few seconds). For rooms with no liquid, use 00.
	For liquids moving up, use a surface speed value between FE00-FFFF. Examples: FFFE (absolute slowest), FFD0 (slow), FFD0 (decent speed), and FE00 (very fast).
	For liquids moving down, use a surface speed value between 0001-0100. Examples: 0001 (absolute slowest), 0020 (slow), 0040 (decent speed), 0100 (very fast). 
	--]]
	{liquidSurfaceDelay = 'uint8_t'},		-- 6

	-- liquid, fog, spores, rain, etc
	{fxType = 'uint8_t'},					-- 7
	
	-- lighting options: 02 = normal, 28 = dark visor room, 2a = darker yellow-visor room
	{a = 'uint8_t'},						-- 8
	
	-- prioritize/color layers
	{b = 'uint8_t'},						-- 9
	
	-- liquid options
	{c = 'uint8_t'},						-- 0xa
	
	{paletteFXFlags = 'uint8_t'},			-- 0xb
	{tileAnimateFlags = 'uint8_t'},			-- 0xc
	{paletteBlend = 'uint8_t'},				-- 0xd
	
	{last = 'uint16_t'},					-- 0xe
}

local bg_t = struct'bg_t'{
	{header = 'uint16_t'},
	{addr = 'uint16_t'},
	{bank = 'uint8_t'},
	-- skip the next 14 bytes
	{unknown1 = 'uint16_t'},
	{unknown2 = 'uint16_t'},
	{unknown3 = 'uint16_t'},
	{unknown4 = 'uint16_t'},
	{unknown5 = 'uint16_t'},
	{unknown6 = 'uint16_t'},
	{unknown7 = 'uint16_t'},
}

-- described in section 12 of metroidconstruction.com/SMMM
-- if a user touches a xx-9x-yy tile then the number in yy (3rd channel) is used to lookup the door_t to see where to go
-- This isn't the door so much as the information associated with its destination.
-- This doesn't reference the in-room door object so much as vice-versa.
-- I'm tempted to call this 'exit_t' ... since you don't need a door
local door_t = struct'door_t'{
	{dest_mdb = 'uint16_t'},				-- 0: points to the mdb_t to transition into
	
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
	
	{capX = 'uint8_t'},					-- 4
	{capY = 'uint8_t'},					-- 5
	{screenX = 'uint8_t'},				-- 6	target room x offset to place you at?
	{screenY = 'uint8_t'},				-- 7	... y ...
	{distToSpawnSamus = 'uint16_t'},	-- 9
	{code = 'uint16_t'},				-- A
}

-- this is what the metroid ROM map says ... "Elevator thing"
-- two dooraddrs point to a uint16_t of zero, at $0188fc and $01a18a, and they point to structs that only take up 2 bytes
-- you find it trailing the door_t corresponding with the lift
local lift_t = struct'lift_t'{
	{zero = 'uint16_t'},
}

SMMap.plmCmdValueForName = table{
	-- normal exit
	exit_right = 0xb63b,
	exit_left = 0xb63f,
	exit_down = 0xb643,
	exit_up = 0xb647,

	scrollmod = 0xb703,
	
	door_grey_right_closing = 0xbaf4,

	-- gates
	normal_open_gate = 0xc826,
	normal_close_gate = 0xc82a,
	flipped_open_gate = 0xc82e,
	flipped_close_gate = 0xc832,
	shot_gate_top = 0xc836,
	-- grey
	door_grey_right = 0xc842,
	door_grey_left = 0xc848,
	door_grey_down = 0xc84e,
	door_grey_up = 0xc854,
	-- orange
	door_orange_right = 0xc85a,
	door_orange_left = 0xc860,
	door_orange_down = 0xc866,
	door_orange_up = 0xc86c,
	-- green
	door_green_right = 0xc872,
	door_green_left = 0xc878,
	door_green_down = 0xc87e,
	door_green_up = 0xc884,
	-- red
	door_red_right = 0xc88a,
	door_red_left = 0xc890,
	door_red_down = 0xc896,
	door_red_up = 0xc89c,
	-- blue
	-- where are the regular blue doors?
	door_blue_right_opening = 0xc8A2,
	door_blue_left_opening = 0xc8a8,
	door_blue_down_opening = 0xc8aE,
	door_blue_up_opening = 0xc8b4,
	door_blue_right_closing = 0xc8BA,
	door_blue_left_closing = 0xc8bE,
	door_blue_down_closing = 0xc8c2,
	door_blue_up_closing = 0xc8c6,

	door_eye_left = 0xdb4c,
	door_eye_left_part2 = 0xdb48,
	door_eye_left_part3 = 0xdb52,
	
	door_eye_right = 0xdb5a,
	door_eye_right_part2 = 0xdb56,
	door_eye_right_part3 = 0xdb60,

	-- items: (this is just like SMItems.itemTypes in sm-items.lua
	item_energy 		= 0xeed7,
	item_missile 		= 0xeedb,
	item_supermissile 	= 0xeedf,
	item_powerbomb		= 0xeee3,
	item_bomb			= 0xeee7,
	item_charge			= 0xeeeb,
	item_ice			= 0xeeef,
	item_hijump			= 0xeef3,
	item_speed			= 0xeef7,
	item_wave			= 0xeefb,
	item_spazer 		= 0xeeff,
	item_springball		= 0xef03,
	item_varia			= 0xef07,
	item_plasma			= 0xef13,
	item_grappling		= 0xef17,
	item_morph			= 0xef23,
	item_reserve		= 0xef27,
	item_gravity		= 0xef0b,
	item_xray			= 0xef0f,
	item_spacejump 		= 0xef1b,
	item_screwattack	= 0xef1f,
}

-- add 84 = 0x54 to items to get to chozo , another 84 = 0x54 to hidden
for _,k in ipairs(SMMap.plmCmdValueForName:keys():filter(function(k)
	return k:match'^item_'
end)) do
	local v = SMMap.plmCmdValueForName[k]
	SMMap.plmCmdValueForName[k..'_chozo'] = v + 0x54
	SMMap.plmCmdValueForName[k..'_hidden'] = v + 2*0x54
end


SMMap.plmCmdNameForValue = SMMap.plmCmdValueForName:map(function(v,k) return k,v end)

local RoomState = class()
function RoomState:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.fx1s = self.fx1s or table()
	self.bgs = self.bgs or table()
end

function RoomState:setPLMSet(plmset)
	if self.plmset then
		self.plmset.roomStates:removeObject(self)
	end
	self.plmset = plmset
	if self.plmset then
		self.plmset.roomStates:insert(self)
	end
end


local PLMSet = class()

function PLMSet:init(args)
	self.addr = args.addr	--optional
	self.plms = table(args.plms)
	self.scrollmods = table()
	self.roomStates = table()
end

function SMMap:newPLMSet(args)
	local plmset = PLMSet(args)
	self.plmsets:insert(plmset)
	return plmset
end

-- table of all unique plm regions
-- m is only used for MemoryMap.  you have to add to plmset.mdbs externally
function SMMap:mapAddPLMSetFromAddr(addr, m)
	local rom = self.rom
	local startaddr = addr
	local _,plmset = self.plmsets:find(nil, function(plmset) return plmset.addr == addr end)
	if plmset then return plmset end

	local startaddr = addr

	local plms = table()
	while true do
		local ptr = ffi.cast('plm_t*', rom+addr)
		if ptr.cmd == 0 then 
			-- include plm term
			addr = addr + 2
			break 
		end
		--inserting the struct by-value
		-- why did I have to make a copy?
		plms:insert(ffi.new('plm_t', ptr[0]))
		addr = addr + ffi.sizeof'plm_t'
	end
	
	-- nil plmset for no plms
	--if #plms == 0 then return end

	local plmset = self:newPLMSet{
		addr = startaddr,
		plms = plms,
	}

	-- now interpret the plms...
	for _,plm in ipairs(plmset.plms) do
		if plm.cmd == self.plmCmdValueForName.scrollmod then
			local startaddr = 0x70000 + plm.args
			local addr = startaddr
			local data = table()
			while true do
				local screen = rom[addr] addr=addr+1
				data:insert(screen)
				if screen == 0x80 then break end
				local scroll = rom[addr] addr=addr+1
				data:insert(scroll)
			end
			assert(addr - startaddr == #data)
			plmset.scrollmods:insert{
				addr = startaddr,
				data = data,
			}
		end
	end

	return plmset
end


function SMMap:mapAddEnemyPopSet(addr)
	local rom = self.rom
	local _,enemyPopSet = self.enemyPopSets:find(nil, function(enemyPopSet)
		return enemyPopSet.addr == addr
	end)
	if enemyPopSet then return enemyPopSet end

	local startaddr = addr
	local enemyPops = table()
	local enemiesToKill 
	while true do
		local ptr = ffi.cast('enemyPop_t*', rom + addr)
		if ptr.enemyAddr == 0xffff then
			-- include term and enemies-to-kill
			addr = addr + 2
			break
		end
		enemyPops:insert(ffi.new('enemyPop_t', ptr[0]))
		addr = addr + ffi.sizeof'enemyPop_t'
	end
	enemiesToKill = rom[addr]
	addr = addr + 1

	local enemyPopSet = {
		addr = startaddr,
		enemyPops = enemyPops,
		enemiesToKill = enemiesToKill, 
		roomStates = table(),
	}
	self.enemyPopSets:insert(enemyPopSet)
	return enemyPopSet
end

function SMMap:mapAddEnemySetSet(addr)
	local rom = self.rom
	local _,enemySetSet = self.enemySetSets:find(nil, function(enemySetSet)
		return enemySetSet.addr == addr
	end)
	if enemySetSet then return enemySetSet end

	local startaddr = addr
	local enemySets = table()

	while true do
		local ptr = ffi.cast('enemySet_t*', rom+addr)
		if ptr.enemyAddr == 0xffff then 
-- looks like there is consistently 10 bytes of data trailing enemySet_t, starting with 0xffff
--print('   enemySet_t term: '..range(0,9):map(function(i) return ('%02x'):format(data[i]) end):concat' ')
			-- include terminator
			addr = addr + 10
			break 
		end
		enemySets:insert(ffi.new('enemySet_t', ptr[0]))
		addr = addr + ffi.sizeof'enemySet_t'
	end

	local enemySetSet = {
		addr = startaddr,
		enemySets = enemySets,
		roomStates = table(),
	}
	self.enemySetSets:insert(enemySetSet)
	return enemySetSet
end


-- table of all unique bgs.
-- each entry has .addr and .ptr = (bg_t*)(rom+.addr)
-- doesn't create duplicates -- returns a previous copy if it exists
function SMMap:mapAddBG(addr)
	local _,bg = self.bgs:find(nil, function(bg) return bg.addr == addr end)
	if bg then return bg end
	bg = {
		addr = addr,
		ptr = ffi.cast('bg_t*', self.rom + addr),
		-- list of all m's that use this bg
		mdbs = table(),
	}
	self.bgs:insert(bg)
	return bg
end


function SMMap:mapAddFX1(addr)
	local _,fx1 = self.fx1s:find(nil, function(fx1) return fx1.addr == addr end)
	if fx1 then return fx1 end
	fx1 = {
		addr = addr,
		ptr = ffi.cast('fx1_t*', self.rom + addr),
		mdbs = table(),
	}
	self.fx1s:insert(fx1)
	return fx1
end


local Room = class()
function Room:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.mdbs = table()
end
function Room:getData()
	local w, h = self.width, self.height
	local ch12 = ffi.new('uint8_t[?]', 2 * w * h)
	local ch3 = ffi.new('uint8_t[?]', w * h)
	local k = 0
	for j=0,self.height-1 do
		for i=0,self.width-1 do
			ch12[0 + 2 * k] = self.blocks[0 + 3 * k]
			ch12[1 + 2 * k] = self.blocks[1 + 3 * k]
			ch3[k] = self.blocks[2 + 3 * k]
			k = k + 1
		end
	end

	return mergeByteArrays(
		self.head,
		ch12,
		ch3,
		self.tail
	)
end

-- this is the block data of the rooms
function SMMap:mapAddRoom(addr, m)
	local _,room = self.rooms:find(nil, function(room) 
		return room.addr == addr 
	end)
	if room then 
		-- rooms can come from separate mdb_t's
		-- which means they can have separate widths & heights
		-- so here, assert that their width & height matches
		assert(16 * room.mdbs[1].ptr.width == room.width, "expected room width "..room.width.." but got "..m.ptr.width)
		assert(16 * room.mdbs[1].ptr.height == room.height, "expected room height "..room.height.." but got "..m.ptr.height)
		return room 
	end
	
	local roomaddrstr = ('$%06x'):format(addr)
--print('roomaddr '..roomaddrstr)
	
	-- then we decompress the next 0x10000 bytes ...
--print('decompressing address '..('0x%06x'):format(addr))
	local data, compressedSize = lz.decompress(self.rom, addr, 0x10000)
--print('decompressed from '..compressedSize..' to '..ffi.sizeof(data))
	
	local ofs = 0
	local head = byteArraySubset(data, ofs, 2) ofs=ofs+2
	local w = m.ptr.width * 16
	local h = m.ptr.height * 16
	local ch12 = byteArraySubset(data, ofs, 2*w*h) ofs=ofs+2*w*h
	local ch3 = byteArraySubset(data, ofs, w*h) ofs=ofs+w*h -- referred to as 'bts' = 'behind the scenes' in some docs.  I'm just going to interleave everything.
	local blocks = ffi.new('uint8_t[?]', 3 * w * h)
	local k = 0
	for j=0,h-1 do
		for i=0,w-1 do
			blocks[0 + 3 * k] = ch12[0 + 2 * k]
			blocks[1 + 3 * k] = ch12[1 + 2 * k]
			blocks[2 + 3 * k] = ch3[k]
			k = k + 1
		end
	end
	local tail = byteArraySubset(data, ofs, ffi.sizeof(data) - ofs)
	assert(ofs <= ffi.sizeof(data), "didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..ffi.sizeof(data))

	-- keep track of doors
	
	-- ok, this correlates with the door plms, so it is useful
	--  but it isn't general to all exits
	local doors = table()	-- x,y,w,h
	-- so that's where this comes in.  it is general to all exits.
	-- 	key is the exit, value is a list of all positions of each exit xx9xyy block
	local blocksForExit = table()
	for j=0,h-1 do	-- ids of horizontal regions (up/down doors) are 2 blocks from the 4xfffefd pattern
		for i=0,w-1 do
			local a = blocks[0 + 3 * (i + w * j)]
			local b = blocks[1 + 3 * (i + w * j)]
			local c = blocks[2 + 3 * (i + w * j)]

-- [[
-- look for 0x9x in ch2 of of room.blocks
			if bit.band(b, 0xf0) == 0x90 then
				local exitindex = c
				blocksForExit[exitindex] = blocksForExit[exitindex] or table()
				blocksForExit[exitindex]:insert{i,j}
			end
--]]

--[[
doors are 40 through 43, followed by ff, fe, fd, either horizontally or vertically
 and then next to the 4 numbers, offset based on the door dir 40-43 <-> x+1,x-1,y+2,y-2, 
 will be the door_t index, repeated 4 times.
 for non-blue doors, this will match up with a plm in the roomstate that has x,y matching the door's location
 for blue doors, no plm is needed
however exits with no doors: 
 	* 00/0d the room to the right of the ship, exits 0 & 1 
 	* 01/09 the tall pink brinstar room, exit 5
 	* 04/01 maridia tube room, exits 1 & 2
 	* 04/0e maridia broken tube crab room, exits 0 & 1
 	* between maridia tall room 04/04 (exit 4) and maridia balloon room 04/08 (exit 4)
		-- this one is really unique, since the rest of them would always be 4 indexes in a row, and always at the same offsets %16 depending on their direction, (not always on the map edge)
			but 04/04 is only a single 04 on the edge of the map surrounded by 0's
			and 04/08 is two 0404's in a row, in the middle of the map, surrounded by 0's
	* 04/19 maridia upper right sandpit start
	* 04/1a maridia where sand pit #1 falls into. there's a third door_t for the sand entrance, 
			but no 02's in ch3 
	* 04/1d maridia sand pit #1.  has two door_t's.  only one is seen in the ch3's: exit 1 in the floor
	* 04/1e maridia sand pit #2.  same as #1 
	* 04/1f maridia sandfall room #1 ... has no up exit, but the bottom is all 01 tiles for exit #1
	* 04/20 maridia sandfall room #2 same.  interesting that there is no exit #0 used, only exit #1.
		the roomstate says there are two doors though, but no door for index 0 can be seen.
	* 04/21 maridia big pink room with two sand exits to 04/1f (exit 1) and 04/20 (exit 2)
		-- these are a row of 80 tiles over a row of exit # tiles 
	* 04/22 maridia upper right sandpit end
 	* 04/27 where sand pit 04/2b ends up
 	* 04/2b maridia room after botwoon, has 4 doors, two are doors, two are sandpit exits (#1 & #2)
	* 04/2e maridia upper right sandpit middle
	* 04/2f sandpit down from room after botwoon 
 will only have their dest door_t number and a door_t entry ... no plm even
so how does the map know when to distinguish those tiles from ordinary 00,01,etc shot tiles, especially with no plm there?
 and esp when the destination door_t structure doesn't say anything about the location from where the door is?
--]]			
			if i >= 1 and i <= w-2 
			and j >= 2 and j <= h-3
			and c >= 0x40 and c <= 0x43 
			then
				-- here's the upper-left of a door.  now, which way is it facing
				if i<w-3
				and (c == 0x42 or c == 0x43)
				and blocks[2 + 3 * ((i+1) + w * j)] == 0xff 
				and blocks[2 + 3 * ((i+2) + w * j)] == 0xfe 
				and blocks[2 + 3 * ((i+3) + w * j)] == 0xfd 
				then
					-- if c == 0x42 then it's down, if c == 0x43 then it's up 
					local doorIndex = c == 0x42 
						and blocks[2 + 3 * ( i + w * (j+2))]
						or blocks[2 + 3 * ( i + w * (j-2))]
					doors:insert{
						x = i,
						y = j,
						w = 4,
						h = 1,
						dir = bit.band(3, c),
						index = doorIndex,
					}
				elseif j<h-3	-- TODO assert this
				and (c == 0x40 or c == 0x41)
				and blocks[2 + 3 * (i + w * (j+1))] == 0xff 
				and blocks[2 + 3 * (i + w * (j+2))] == 0xfe 
				and blocks[2 + 3 * (i + w * (j+3))] == 0xfd 
				then
					-- if c == 0x41 then it's left, if c == 0x40 then it's right
					local doorIndex = c == 0x40 
						and blocks[2 + 3 * ((i+1) + w * j)]
						or blocks[2 + 3 * ((i-1) + w * j)]
					doors:insert{
						x = i,
						y = j,
						w = 1,
						h = 4, 
						dir = bit.band(3, c),
						index = doorIndex,
					}
				else
					-- nothing, there's lots of other 40..43's out there
				end
			end
		end
	end

	local room = Room{
		addr = addr,
		mdbs = table(),
		roomStates = table(),
		-- this is just 16 * mdb's (width, height)
		width = w,
		height = h,
		-- rule of thumb: do not exceed this
		compressedSize = compressedSize,
		-- decompressed data (in order):
		head = head,	-- first 2 bytes of data
		blocks = blocks,	-- interleaved 2-byte and 1-byte bts into 3-byte room block data
		tail = tail,	-- last bytes after blocks 
		-- extra stuff I'm trying to keep track of
		doors = doors,
		blocksForExit = blocksForExit,
	}
	room.mdbs:insert(m)
	self.rooms:insert(room)
	return room
end


local function readCode(rom, addr, maxlen)
	local code = table()
	for i=0,maxlen-1 do
		local r = rom[addr] addr=addr+1
		code:insert(r)
		if r == 0x60 then break end
		if i == maxlen-1 then error("code read overflow") end
	end
	return code
end


function SMMap:mapAddLayerHandling(addr)
	local _,layerHandling = self.layerHandlings:find(nil, function(layerHandling)
		return layerHandling.addr == addr
	end)
	if layerHandling then return layerHandling end
	local layerHandling = {
		addr = addr,
		code = readCode(self.rom, addr, 0x100),
		roomStates = table(),
	}
	self.layerHandlings:insert(layerHandling)
	return layerHandling
end

SMMap.scrollBank = 0x8f
SMMap.mdbBank = 0x8e
SMMap.roomStateBank = 0x8e	-- bank for roomselect_t.roomstate
SMMap.enemyPopBank = 0xa1
SMMap.enemySetBank = 0xb4
SMMap.fx1Bank = 0x83
SMMap.bgBank = 0x8f
SMMap.layerHandlingBank = 0x8f
SMMap.doorAddrBank = 0x8e	-- bank for mdb_t.doors
SMMap.doorBank = 0x83
SMMap.doorCodeBank = 0x8f

function SMMap:mapInit()
	local rom = self.rom

	-- check where the PLM bank is
	-- TODO this will affect the items.lua addresses
	self.plmBank = rom[0x204ac]
	
	self.mdbs = table()
	self.rooms = table()
	self.bgs = table()
	self.fx1s = table()
	self.layerHandlings = table()
	
	self.plmsets = table()
	self.enemyPopSets = table()
	self.enemySetSets = table()

	--[[
	from $078000 to $079193 is plm_t data
	the first mdb_t is at $0791f8
	from there it is a dense structure of ...
	mdb_t
	roomselect's (in reverse order)
	roomstate_t's (in forward order)
	dooraddrs
	... then comes extra stuff, sometimes:
	scrolldata (which is in one place wedged into nowhere)
	plm scrollmod

	TODO don't check *every* byte from 0x8000 to 0xffff
	--]]
	for x=0x8000,0xffff do
		local data = rom + topc(self.mdbBank, x)
		local function read(ctype)
			local result = ffi.cast(ctype..'*', data)
			data = data + ffi.sizeof(ctype)
			return result[0]
		end

		local mptr = ffi.cast('mdb_t*', data)
		if (
			(data[12] == 0xE5 or data[12] == 0xE6) 
			and mptr.region < 8 
			and (mptr.width ~= 0 and mptr.width < 20) 
			and (mptr.height ~= 0 and mptr.height < 20)
			and mptr.gfxFlags < 0x10 
			and mptr.doors > 0x7F00
		) then
			
			local m = {
				roomStates = table(),
				doors = table(),
-- TODO bank-offset addr vs pc addr for all my structures ...
				addr = x,
				ptr = mptr,
			}	
			self.mdbs:insert(m)
			data = data + ffi.sizeof'mdb_t'

			-- events
			while true do
				local testcode = ffi.cast('uint16_t*',data)[0]
				
				local ctype
				if testcode == 0xe5e6 then 
					ctype = 'uint16_t'
				elseif testcode == 0xE612
				or testcode == 0xE629
				then
					ctype = 'roomselect_t'
				elseif testcode == 0xE5EB then
					-- this is never reached
					error'here' 
					-- I'm not using this just yet
					-- struct {
					-- 	uint16_t testcode;
					-- 	uint16_t testvaluedoor;
					--	uint16_t roomstate;
					-- }
				else
					ctype = 'roomselect2_t'
				end
				local rs = RoomState{
					m = m,
					select = ffi.cast(ctype..'*', data),
					select_ctype = ctype,	-- using for debug print only
				}
				m.roomStates:insert(rs)
				
				data = data + ffi.sizeof(ctype)

				if ctype == 'uint16_t' then break end	-- term
			end

			do
				-- after the last roomselect is the first roomstate_t
				local rs = m.roomStates:last()
				-- uint16_t select means a terminator
				assert(rs.select_ctype == 'uint16_t')
				rs.ptr = ffi.cast('roomstate_t*', data)
				data = data + ffi.sizeof'roomstate_t'

				-- then the rest of the roomstates come
				for _,rs in ipairs(m.roomStates) do
					if rs.select_ctype ~= 'uint16_t' then
						assert(not rs.ptr)
						local addr = topc(self.roomStateBank, rs.select[0].roomstate)
						rs.ptr = ffi.cast('roomstate_t*', rom + addr)
					end

					assert(rs.ptr)
				end

				-- I wonder if I can assert that all the roomstate_t's are in contiguous memory after the roomselect's ... 
				-- they sure aren't sequential
				-- they might be reverse-sequential
				-- sure enough, YES.  roomstates are contiguous and reverse-sequential from roomselect's
				--[[
				for i=1,#m.roomStates-1 do
					assert(m.roomStates[i+1].ptr + 1 == m.roomStates[i].ptr)
				end
				--]]

				for _,rs in ipairs(m.roomStates) do
					if rs.ptr.scroll > 0x0001 and rs.ptr.scroll ~= 0x8000 then
						local addr = topc(self.scrollBank, rs.ptr.scroll)
						local size = m.ptr.width * m.ptr.height
						rs.scrollData = range(size):map(function(i)
							return rom[addr+i-1]
						end)
					end
				end

				-- add plms in reverse order, because the roomstates are in reverse order of roomselects,
				-- and the plms are stored in-order with roomselects
				-- so now, when writing them out, they will be in the same order in memory as they were when being read in
				for i=#m.roomStates,1,-1 do
					local rs = m.roomStates[i]
					if rs.ptr.plm ~= 0 then
						local addr = topc(self.plmBank, rs.ptr.plm)
						local plmset = self:mapAddPLMSetFromAddr(addr, m)
						rs:setPLMSet(plmset)
					end
				end

				-- enemyPopSet
				-- but notice, for writing back enemy populations, sometimes there's odd padding in there, like -1, 3, etc
				for _,rs in ipairs(m.roomStates) do
					rs.enemyPopSet = self:mapAddEnemyPopSet(topc(self.enemyPopBank, rs.ptr.enemyPop))
					rs.enemyPopSet.roomStates:insert(rs)
				end
				
				for _,rs in ipairs(m.roomStates) do
					rs.enemySetSet = self:mapAddEnemySetSet(topc(self.enemySetBank, rs.ptr.enemySet))
					rs.enemySetSet.roomStates:insert(rs)
				end

				-- some rooms use the same fx1 ptr
				-- and from there they are read in contiguous blocks until a term is encountered
				-- so I should make these fx1sets (like plmsets)
				-- unless -- another optimization -- is, if one room's fx1's (or plms) are a subset of another,
				-- then make one set and just put the subset's at the end
				-- (unless the order matters...)
				for _,rs in ipairs(m.roomStates) do
					local startaddr = topc(self.fx1Bank, rs.ptr.fx1)
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
						-- TODO this condition was in smlib, but m.doors won't be complete until after all doors have been loaded
						--or m.doors:find(nil, function(door) return door.addr == cmd end)
						--then
						if true then
							local fx1 = self:mapAddFX1(addr)
	-- this misses 5 fx1_t's
	local done = fx1.ptr.doorSelect == 0 
							fx1.mdbs:insert(m)
							rs.fx1s:insert(fx1)
							
							addr = addr + ffi.sizeof'fx1_t'

	-- term of 0 past the first entry
	if done then break end
						end
					end
				end
				
				for _,rs in ipairs(m.roomStates) do
					if rs.ptr.bgdata > 0x8000 then
						local addr = topc(self.bgBank, rs.ptr.bgdata)
						while true do
							local ptr = ffi.cast('bg_t*', rom+addr)
							
	-- this is a bad test of validity
	-- this says so: http://metroidconstruction.com/SMMM/ready-made_backgrounds.txt
	-- in fact, I never read more than 1 bg, and sometimes I read 0
	--[[
							if ptr.header ~= 0x04 then
								addr = addr + 8
								break
							end
	--]]
							-- so bgs[i].addr is the address where bgs[i].ptr was found
							-- and bgs[i].ptr.bank,addr points to where bgs[i].data was found
							-- a little confusing
							local bg = self:mapAddBG(addr)
							bg.mdbs:insert(m)
							rs.bgs:insert(bg)
							addr = addr + ffi.sizeof'bg_t'
						
							addr=addr+8
							do break end
						end
					
						--[[ load data
						-- this worked fine when I was discounting zero-length bg_ts, but once I started requiring bgdata to point to at least one, this is now getting bad values
						for _,bg in ipairs(rs.bgs) do
							local addr = topc(bg.ptr.bank, bg.ptr.addr)
							local decompressed, compressedSize = lz.decompress(rom, addr, 0x10000)
							bg.data = decompressed
							mem:add(addr, compressedSize, 'bg data', m)
						end
						--]]
					end
				end

				for _,rs in ipairs(m.roomStates) do
					if rs.ptr.layerHandling > 0x8000 then
						local addr = topc(self.layerHandlingBank, rs.ptr.layerHandling)
						rs.layerHandling = self:mapAddLayerHandling(addr)
						rs.layerHandling.roomStates:insert(rs)
					end
					
					local addr = topc(rs.ptr.roomBank, rs.ptr.roomAddr)
					rs.room = self:mapAddRoom(addr, m)
					rs.room.mdbs:insertUnique(m)
					rs.room.roomStates:insert(rs)
				end

				local startaddr = topc(self.doorAddrBank, m.ptr.doors)
				data = rom + startaddr 
				--data = rom + 0x70000 + m.ptr.doors
				local doorAddr = read'uint16_t'
				while doorAddr > 0x8000 do
					m.doors:insert{
						addr = doorAddr,
					}
					doorAddr = read'uint16_t'
				end
				-- exclude terminator
				data = data - 2
				local len = data-rom - startaddr
			
	--doorsSoFar = doorsSoFar or table()
				for _,door in ipairs(m.doors) do
					local addr = topc(self.doorBank, door.addr)
	--doorsSoFar[addr] = doorsSoFar[addr] or table()
	--doorsSoFar[addr]:insert(m)
					data = rom + addr 
					local dest_mdb = ffi.cast('uint16_t*', data)[0]
					-- if dest_mdb == 0 then it is just a 2-byte 'lift' structure ...
					local ctype = dest_mdb == 0 and 'lift_t' or 'door_t'
					door.ctype = ctype
					door.ptr = ffi.cast(ctype..'*', data)
					if ctype == 'door_t' 
					and door.ptr.code > 0x8000 
					then
						door.doorCodeAddr = topc(self.doorCodeBank, door.ptr.code)
						door.doorCode = readCode(rom, door.doorCodeAddr, 0x100)
					end
				end
			
				-- ok now we've got all the roomstates, rooms, plms, and door_t's ...
				-- now to link the doors in the rooms to their plm and door_t 
				--[[ turns out it is very slow, esp when building the map from roomstate to exit
				for _,rs in ipairs(m.roomStates) do
					for _,door in ipairs(rs.room.doors) do
						local exit = m.doors[door.index+1]
						if not exit then
							print("failed to find exit index "..door.index.." in "
								..('%02x/%02x'):format(m.ptr.region, m.ptr.index))
						else
							door.exit = door.exit or {}
							door.exit[rs] = exit 
						end

						local plmindex, plm = rs.plmset.plms:find(nil, function(plm)
							return plm.x == door.x and plm.y == door.y
						end)
						-- may or may not be there
						if plm then
							door.plms = door.plms or {}
							door.plms[rs] = plm
						end
					end
				end
				---]]
			end
		end
	end


	-- link all doors to their mdbs
	for _,m in ipairs(self.mdbs) do
		for _,door in ipairs(m.doors) do
			if door.ctype == 'door_t' then
				local dest_mdb = assert(
					select(2, self.mdbs:find(nil, function(m) 
						return m.addr == door.ptr.dest_mdb 
					end)), 
					'!!!! door '..('%06x'):format(ffi.cast('uint8_t*',door.ptr)-rom)..' points nowhere')
				-- points to the dest mdb
				door.dest_mdb = dest_mdb
			end
		end
	end
	
	--[[ get a table of doors based on their plm arg low byte
	self.doorPLMForID = table()
	for _,plmset in ipairs(self.plmsets) do
		for _,plm in ipairs(plmset.plms) do
			local name = self.plmCmdNameForValue[plm.cmd]
			if name and name:match'^door_' then
				local id = bit.band(plm.args, 0xff)
				assert(not self.doorPLMForID[id])
				self.doorPLMForID[id] = plm
			end	
		end
	end
	--]]


	-- ok, now to try and change a mdb_t


	--[[ seeing if any two rooms have door addrs that point to the same door ...
	-- looks like the only ones that do are the lift_t zero structure:
	-- $0188fc, used by 00/08 00/0f 00/14 00/19 01/00 01/0e 01/24 00/33 01/34 02/03 02/26 02/36
	-- $01a18a, used by 04/13 05/00
	print()
	for _,addr in ipairs(doorsSoFar:keys():sort()) do
		local ms = doorsSoFar[addr]
		if #ms > 1 then
			io.write('found overlapping doors at '..('$%06x'):format(addr)..', used by')
			for _,m in ipairs(ms) do
				io.write(' '..('%02x/%02x'):format(m.ptr.region, m.ptr.index))
			end
			print()
		end
	end
	--]]
	--[[ now lets look through all doors and see if there's any duplicates that *could have* been overlapping
	-- nope, all doors are unique.  any sort of duplication is handled by the overlapping door addresses above
	local alldoors = table():append(self.mdbs:map(function(m) return m.doors end):unpack())
	print()
	print('#alldoors '..#alldoors)
	for i=1,#alldoors-1 do
		local da = alldoors[i]
		for j=i+1,#alldoors do
			local db = alldoors[j]
			if da.addr ~= db.addr and da.ptr[0] == db.ptr[0] then
				print('doors '..('$%06x'):format(ffi.cast('uint8_t*',da.ptr)-rom)
					..' and '..('$%06x'):format(ffi.cast('uint8_t*',db.ptr)-rom)
					..' are identical (and could be consolidated)')
			end
		end
	end
	--]]



	-- [[ -------------------------------- ASSERT STRUCT ---------------------------------
	-- asserting underlying contiguousness of structure of the mdb_t's...
	-- verify that after each mdb_t, the roomselect / roomstate_t / dooraddrs are packed together

	-- before the first mdb_t is 174 plm_t's, 
	-- then 100 bytes of something
	assert(self.mdbs)
	for j,m in ipairs(self.mdbs) do
		local d = ffi.cast('uint8_t*',m.ptr)
		local mdbaddr = d - rom
		d = d + ffi.sizeof'mdb_t'
		-- if there's only 1 roomState then it is a term, and
		for i=1,#m.roomStates-1 do
			assert(d == ffi.cast('uint8_t*', m.roomStates[i].select))
			d = d + ffi.sizeof(m.roomStates[i].select_ctype)
		end
		-- last roomselect should always be 2 byte term
		d = d + 2
		-- next should always match the last room
		for i=#m.roomStates,1,-1 do
			assert(d == ffi.cast('uint8_t*', m.roomStates[i].ptr))
			d = d + ffi.sizeof'roomstate_t'
		end
		-- for a single room there is an extra 26 bytes of padding between the roomstate_t's and the dooraddrs
		-- and that room is $07ad1b, the speed booster room
		-- the memory map at http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
		-- says it is just part of the speed booster room
		if mdbaddr == 0x07ad1b then
	print('speed booster room extra trailing data: '..range(26):map(function(i) return (' %02x'):format(d[i-1]) end):concat())
			d = d + 26
		end
		local dooraddr = topc(self.doorAddrBank, m.ptr.doors)
		assert(d == rom + dooraddr)
		d = d + 2 * #m.doors
		
		-- now expect all scrolldatas of all rooms of this mdb_t
		-- the # of unique scrolldatas is either 0 or 1
		local scrolls = m.roomStates:map(function(rs)
			return true, rs.ptr.scroll
		end):keys():filter(function(scroll)
			return scroll > 1 and scroll ~= 0x8000
		end):sort()
		assert(#scrolls <= 1)
		-- mdb_t $07adad -- room before wave room -- has its scrolldata overlap with the dooraddr
		-- so... shouldn't this assertion fail?
		for _,scroll in ipairs(scrolls) do
			local addr = topc(self.scrollBank, scroll)
			assert(d == rom + addr)
			d = d + m.ptr.width * m.ptr.height
		end

		-- mdb_t $079804 - gold torizo room - has 14 bytes here -- pointed to by roomstate_t.unknown: 0f 0a 52 00 0f 0b 52 00 0f 0c 52 00 00 00
		-- mdb_t $07a66a - statues before tourian - has 8 bytes after it 
		-- mdb_t $07a923 - slope down to crocomire - has 5 bytes here 
		-- mdb_t $07a98d - crocomire's room - has 6 bytes here 
		-- mdb_t $07ad1b - speed booster room - has 26 bytes here
		-- mdb_t $07b1e5 - lava-lowering chozo statue - has 11 bytes here
		d = d + (({
			[0x79804] = 14,
			[0x7a66a] = 8,
			[0x7a923] = 5,
			[0x7a98d] = 6,
			[0x7ad1b] = 26,
			[0x7b1e5] = 11,
		})[mdbaddr] or 0)

	--[=[ continuity of plm scrollmods?
	print('d starts at '..('%06x'):format( d-rom ))
		-- plm scrollmod sometimes go here
		local plmsets = table()
		for _,rs in ipairs(m.roomStates) do
			plmsets:insertUnique(rs.plmset)
		end
		plmsets:sort(function(a,b) return a.addr < b.addr end)
		for _,plmset in ipairs(plmsets) do
			if plmset and #plmset.scrollmods > 0 then
				for _,scrollmod in ipairs(plmset.scrollmods) do
	--				assert(d == ffi.cast('uint8_t*', rom+scrollmod.addr))
					d = d + scrollmod.len
				end
			end
		end
	--]=]

		-- mdb_t $07c98e - wrecked ship chozo & reserve - has 12 bytes here
		-- mdb_t $07ca42 - hallway at top of wrecked ship - has 8 bytes here
		-- mdb_t $07cc6f - hallway before phantoon - has 3 bytes here

		-- see if the next mdb_t is immediately after
		--[=[
		if j+1 <= #self.mdbs then
			local m2 = ffi.cast('uint8_t*', self.mdbs[j+1].ptr)
			if d ~= m2 then
				print('non-contiguous mdb_t before '..('$%06x'):format(m2-rom))	
			end
		end
		--]=]
	end


	--]] --------------------------------------------------------------------------------
end






local blockSizeInPixels = 4
local blocksPerRoom = 16
local roomSizeInPixels = blocksPerRoom * blockSizeInPixels

local colormap = range(254)
--colormap = shuffle(colormap)
colormap[0] = 0
colormap[255] = 255
-- data is sized 32*m.width x 16*m.width
local ofsPerRegion = {
	function(m) 
		-- special case for crateria
		if m.region == 0	-- crateria
		and m.x > 45 
		then
			return 10,0
		end
		return 3,0
	end,	-- crateria
	function(m) return 0,18 end,	-- brinstar
	function(m) return 31,38 end,	-- norfair
	function(m) return 37,-10 end,	-- wrecked ship
	function(m) return 28,18 end,	-- maridia
	function(m) return 0,0 end,	-- tourian
	function(m) return -5,25 end,	-- ceres
	function(m) return 7,47 end,	-- testing
}

local function drawRoom(mapimg, m, blocks)
	local w, h = m.ptr.width, m.ptr.height
	local ofsx, ofsy = ofsPerRegion[m.ptr.region+1](m.ptr)
	local xofs = roomSizeInPixels * (ofsx - 4)
	local yofs = roomSizeInPixels * (ofsy + 1)
	local firstcoord
	for j=0,h-1 do
		for i=0,w-1 do
			for ti=0,blocksPerRoom-1 do
				for tj=0,blocksPerRoom-1 do
					local dx = ti + blocksPerRoom * i
					local dy = tj + blocksPerRoom * j
					local di = dx + blocksPerRoom * w * dy
					-- blocks is 1-based
					local d1 = blocks[0 + 3 * di] or 0
					local d2 = blocks[1 + 3 * di] or 0
					local d3 = blocks[2 + 3 * di] or 0
			
					-- empty background tiles:
					-- ff0000
					-- ff0083
					-- ff00ff
					-- ff8300
					-- ff8383
					-- ff83ff
					if d1 == 0xff
					--and d2 == 0x00
					and (d2 == 0x00 or d2 == 0x83)
					and (d3 == 0x00 or d3 == 0x83 or d3 == 0xff)
					then
					else
						for pi=0,blockSizeInPixels-1 do
							for pj=0,blockSizeInPixels-1 do
								local y = yofs + pj + blockSizeInPixels * (tj + blocksPerRoom * (m.ptr.y + j))
								local x = xofs + pi + blockSizeInPixels * (ti + blocksPerRoom * (m.ptr.x + i))
				--for y=(m.ptr.y + j)* roomSizeInPixels + yofs, (m.ptr.y + h) * roomSizeInPixels - 1 + yofs do
				--	for x=m.ptr.x * roomSizeInPixels + xofs, (m.ptr.x + w) * roomSizeInPixels - 1 + xofs do
								if x >= 0 and x < mapimg.width
								and y >= 0 and y < mapimg.height 
								then
									if not firstcoord then
										firstcoord = {x,y}
									end
									
									mapimg.buffer[0+3*(x+mapimg.width*y)] = colormap[tonumber(d1)]
									mapimg.buffer[1+3*(x+mapimg.width*y)] = colormap[tonumber(d2)]
									mapimg.buffer[2+3*(x+mapimg.width*y)] = colormap[tonumber(d3)]
								end
							end
						end
					end
				end
			end
		end
	end

-- it'd be really nice to draw the mdb region/index next to the room ...
-- now it'd be nice if i didn't draw over the numbers ... either by the room tile data, or by other numbers ...
local digits = {
	['$'] = {
		' **',
		'** ',
		' * ',
		' **',
		'** ',
	},
	['-'] = {
		'   ',
		'   ',
		'***',
		'   ',
		'   ',
	},
	['0'] = {
		' * ',
		'* *',
		'* *',
		'* *',
		' * ',
	},
	['1'] = {
		' * ',
		' * ',
		' * ',
		' * ',
		' * ',
	},
	['2'] = {
		'** ',
		'  *',
		' * ',
		'*  ',
		'***',
	},
	['3'] = {
		'** ',
		'  *',
		'** ',
		'  *',
		'** ',
	},
	['4'] = {
		'* *',
		'* *',
		'***',
		'  *',
		'  *',
	},
	['5'] = {
		'***',
		'*  ',
		'** ',
		'  *',
		'** ',
	},
	['6'] = {
		' **',
		'*  ',
		'***',
		'* *',
		'***',
	},
	['7'] = {
		'***',
		'  *',
		'  *',
		'  *',
		'  *',
	},
	['8'] = {
		'***',
		'* *',
		'***',
		'* *',
		'***',
	},
	['9'] = {
		'***',
		'* *',
		'***',
		'  *',
		'** ',
	},
	['a'] = {
		' * ',
		'* *',
		'***',
		'* *',
		'* *',
	},
	['b'] = {
		'** ',
		'* *',
		'** ',
		'* *',
		'** ',
	},
	['c'] = {
		' **',
		'*  ',
		'*  ',
		'*  ',
		' **',
	},
	['d'] = {
		'** ',
		'* *',
		'* *',
		'* *',
		'** ',
	},
	['e'] = {
		'***',
		'*  ',
		'***',
		'*  ',
		'***',
	},
	['f'] = {
		'***',
		'*  ',
		'***',
		'*  ',
		'*  ',
	},
}

	local function drawstr(s,pos)
		for i=1,#s do
			local ch = digits[s:sub(i,i)]
			if ch then
				for pj=0,4 do
					for pi=0,2 do
						local c = ch[pj+1]:byte(pi+1) == (' '):byte() and 0 or 255
						if c ~= 0 then	
							local x = pos[1] + pi + (i-1)*4
							local y = pos[2] + pj
						
							if x >= 0 and x < mapimg.width
							and y >= 0 and y < mapimg.height 
							then
								mapimg.buffer[0+3*(x+mapimg.width*y)] = c
								mapimg.buffer[1+3*(x+mapimg.width*y)] = c
								mapimg.buffer[2+3*(x+mapimg.width*y)] = c
							end	
						end	
					end
				end
			end
		end
	end
	drawstr(('%x-%02x'):format(m.ptr.region, m.ptr.index), firstcoord)
	drawstr(('$%04x'):format(m.addr), {
		firstcoord[1],
		firstcoord[2] + 6,
	})
end

local function drawline(mapimg, x1,y1,x2,y2, r,g,b)
	r = r or 0xff
	g = g or 0xff
	b = b or 0xff
	local dx = x2 - x1
	local dy = y2 - y1
	local adx = math.abs(dx)
	local ady = math.abs(dy)
	local d = math.max(adx, ady) + 1
	for k=1,d do
		local s = (k-.5)/d
		local t = 1 - s
		local x = math.round(s * x1 + t * x2)
		local y = math.round(s * y1 + t * y2)
		if x >= 0 and x < mapimg.width
		and y >= 0 and y < mapimg.height 
		then
			mapimg.buffer[0+3*(x+mapimg.width*y)] = r
			mapimg.buffer[1+3*(x+mapimg.width*y)] = g
			mapimg.buffer[2+3*(x+mapimg.width*y)] = b
		end
	end
end

local function drawRoomDoors(mapimg, room)
	local blocks = room.blocks
	-- for all blocks in the room, if any are xx9xyy, then associate them with exit yy in the door_t list (TODO change to exit_t)	
	-- then, cycle through exits, and draw lines from each block to the exit destination

	for _,srcm in ipairs(room.mdbs) do
		local srcm_ofsx, srcm_ofsy = ofsPerRegion[srcm.ptr.region+1](srcm.ptr)
		local srcm_xofs = roomSizeInPixels * (srcm_ofsx - 4)
		local srcm_yofs = roomSizeInPixels * (srcm_ofsy + 1)
		for exitindex,blockpos in pairs(room.blocksForExit) do
print('in mdb '..('%02x/%02x'):format(srcm.ptr.region, srcm.ptr.index)
	..' looking for exit '..exitindex..' with '..#blockpos..' blocks')
			-- TODO lifts will mess up the order of this, maybe?
			local door = srcm.doors[exitindex+1]
			if not door then
print('found no door')
			elseif door.ctype ~= 'door_t' then
print("door isn't a ctype")
			-- TODO handle lifts?
			else
				local dstm = assert(door.dest_mdb)
				local dstm_ofsx, dstm_ofsy = ofsPerRegion[dstm.ptr.region+1](dstm.ptr)
				local dstm_xofs = roomSizeInPixels * (dstm_ofsx - 4)
				local dstm_yofs = roomSizeInPixels * (dstm_ofsy + 1)
			
				-- draw an arrow or something on the map where the door drops us off at
				-- door.dest_mdb is the mdb
				-- draw it at door.ptr.screenX by door.ptr.screenY
				-- and offset it according to direciton&3 and distToSpawnSamus (maybe)

				local i = door.ptr.screenX
				local j = door.ptr.screenY
				local dir = bit.band(door.ptr.direction, 3)	-- 0-based
				local ti, tj = 0, 0	--table.unpack(doorPosForDir[dir])
					
				local k=blockSizeInPixels*3-1 
					
				local pi, pj
				if dir == 0 then		-- enter from left
					pi = k
					pj = bit.rshift(roomSizeInPixels, 1)
				elseif dir == 1 then	-- enter from right
					pi = roomSizeInPixels - k
					pj = bit.rshift(roomSizeInPixels, 1)
				elseif dir == 2 then	-- enter from top
					pi = bit.rshift(roomSizeInPixels, 1)
					pj = k
				elseif dir == 3 then	-- enter from bottom
					pi = bit.rshift(roomSizeInPixels, 1)
					pj = roomSizeInPixels - k
				end
			
				-- here's the pixel x & y of the door destination
				local x1 = dstm_xofs + pi + blockSizeInPixels * (ti + blocksPerRoom * (dstm.ptr.x + i))
				local y1 = dstm_yofs + pj + blockSizeInPixels * (tj + blocksPerRoom * (dstm.ptr.y + j))

				for _,pos in ipairs(blockpos) do
					-- now for src block pos
					local x2 = srcm_xofs + blockSizeInPixels/2 + blockSizeInPixels * (pos[1] + blocksPerRoom * srcm.ptr.x)
					local y2 = srcm_yofs + blockSizeInPixels/2 + blockSizeInPixels * (pos[2] + blocksPerRoom * srcm.ptr.y)
					drawline(mapimg,x1,y1,x2,y2)
				end
			end
		end
	end
end

function drawRoomPLMs(mapimg, room)
	for _,rs in ipairs(room.roomStates) do
		local m = rs.m
		local ofsx, ofsy = ofsPerRegion[m.ptr.region+1](m.ptr)
		local xofs = roomSizeInPixels * (ofsx - 4)
		local yofs = roomSizeInPixels * (ofsy + 1)
		if rs.plmset then
			for _,plm in ipairs(rs.plmset.plms) do
				local x = xofs + blockSizeInPixels/2 + blockSizeInPixels * (plm.x + blocksPerRoom * m.ptr.x)
				local y = yofs + blockSizeInPixels/2 + blockSizeInPixels * (plm.y + blocksPerRoom * m.ptr.y)
				drawline(mapimg,x+2,y,x-2,y, 0x00, 0xff, 0xff)
				drawline(mapimg,x,y+2,x,y-2, 0x00, 0xff, 0xff)
			end
		end
		if rs.enemyPopSet then
			for _,enemyPop in ipairs(rs.enemyPopSet.enemyPops) do
				local x = math.round(xofs + blockSizeInPixels/2 + blockSizeInPixels * (enemyPop.x / 16 + blocksPerRoom * m.ptr.x))
				local y = math.round(yofs + blockSizeInPixels/2 + blockSizeInPixels * (enemyPop.y / 16 + blocksPerRoom * m.ptr.y))
				drawline(mapimg,x+2,y,x-2,y, 0xff, 0x00, 0xff)
				drawline(mapimg,x,y+2,x,y-2, 0xff, 0x00, 0xff)
			end
		end
	end
end


function SMMap:mapSaveImage(filename)
	filename = filename or 'map.png'	
	local image = require 'image'
	local mapimg = image(roomSizeInPixels*68, roomSizeInPixels*58, 3, 'unsigned char')

	for _,room in ipairs(self.rooms) do
		for _,m in ipairs(room.mdbs) do
			drawRoom(mapimg, m, room.blocks)
		end
	end

	for _,room in ipairs(self.rooms) do
		drawRoomDoors(mapimg, room)
		drawRoomPLMs(mapimg, room)
	end

	mapimg:save(filename)
end


function SMMap:mapPrintRooms()
	-- print/draw rooms
	print()
	print'all rooms'
	for _,room in ipairs(self.rooms) do
		local w,h = room.width, room.height
		for _,m in ipairs(room.mdbs) do
			io.write(' '..('%02x/%02x'):format(m.ptr.region, m.ptr.index))
		end
		print()

		local function printblock(data, width)
			for i=1,ffi.sizeof(data) do
				io.write((('%02x'):format(tonumber(data[i-1])):gsub('0','.')))
				if i % width == 0 then print() end 
			end
			print()
		end

		printblock(room.head, 2) 
		printblock(room.blocks, 3*w) 
		print('found '..#room.doors..' door references in the blocks')
		for _,door in ipairs(room.doors) do
			print(' '..tolua(door))
		end
		print('blocksForExit'..tolua(room.blocksForExit))	-- exit information
	end
end

function SMMap:mapPrint()
	local rom = self.rom
	print()
	print("all plm_t's:")
	for _,plmset in ipairs(self.plmsets) do
		print(' '
			..(plmset.addr and ('$%06x'):format(plmset.addr) or 'nil')
			..' mdbs: '..plmset.roomStates:map(function(rs)
				local m = rs.m
				return ('%02x/%02x'):format(m.ptr.region, m.ptr.index)
			end):concat' '
		)
		for _,plm in ipairs(plmset.plms) do
			print('  '..plm)
		end
	end

	-- print bg info
	print()
	print("all bg_t's:")
	self.bgs:sort(function(a,b) return a.addr < b.addr end)
	for _,bg in ipairs(self.bgs) do
		print(' '..('$%06x'):format(bg.addr)..': '..bg.ptr[0]
			..' mdbs: '..bg.mdbs:map(function(m)
				return ('%02x/%02x'):format(m.ptr.region, m.ptr.index)
			end):concat' '
		)
	end

	-- print fx1 info
	print()
	print("all fx1_t's:")
	self.fx1s:sort(function(a,b) return a.addr < b.addr end)
	for _,fx1 in ipairs(self.fx1s) do
		print(' '..('$%06x'):format(fx1.addr)..': '..fx1.ptr[0]
			..' mdbs: '..fx1.mdbs:map(function(m)
				return ('%02x/%02x'):format(m.ptr.region, m.ptr.index)
			end):concat' '
		)
	end

	-- print mdb info
	print()
	print("all mdb_t's:")
	for _,m in ipairs(self.mdbs) do
		print(' mdb_t '..('$%06x'):format(ffi.cast('uint8_t*', m.ptr) - rom)..' '..m.ptr[0])
		for _,rs in ipairs(m.roomStates) do
			print('  roomstate_t: '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' '..rs.ptr[0]) 
			print('  '..rs.select_ctype..': '..('$%06x'):format(ffi.cast('uint8_t*', rs.select) - rom)..' '..rs.select[0]) 
			-- [[
			if rs.plmset then
				for _,plm in ipairs(rs.plmset.plms) do
					io.write('   plm_t: ')
					local plmName = self.plmCmdNameForValue[plm.cmd]
					if plmName then io.write(plmName..': ') end
					print(plm)
				end
				for _,scrollmod in ipairs(rs.plmset.scrollmods) do
					print('   plm scrollmod: '..('$%06x'):format(scrollmod.addr)..': '..scrollmod.data:map(function(x) return ('%02x'):format(x) end):concat' ')
				end
			end
			--]]
			for _,enemyPop in ipairs(rs.enemyPopSet.enemyPops) do	
				print('   enemyPop_t: '
					..((self.enemyForAddr[enemyPop.enemyAddr] or {}).name or '')
					..': '..enemyPop)
			end
			for _,enemySet in ipairs(rs.enemySetSet.enemySets) do
				print('   enemySet_t: '
					..((self.enemyForAddr[enemySet.enemyAddr] or {}).name or '')
					..': '..enemySet)
			end
			for _,fx1 in ipairs(rs.fx1s) do
				print('   fx1_t: '..('$%06x'):format( ffi.cast('uint8_t*',fx1.ptr)-rom )..': '..fx1.ptr[0])
			end
			for _,bg in ipairs(rs.bgs) do
				print('   bg_t: '..('$%06x'):format( ffi.cast('uint8_t*',bg.ptr)-rom )..': '..bg.ptr[0])
			end
		end
		for _,door in ipairs(m.doors) do
			print('  '..door.ctype..': '
				..('$83:%04x'):format(door.addr)
				..' '..door.ptr[0])
		end
	end
	
	self:mapPrintRooms()
end

function SMMap:mapBuildMemoryMap(mem)
	local rom = self.rom
	for _,m in ipairs(self.mdbs) do
		local addr = topc(self.mdbBank, m.addr)	
		mem:add(addr, ffi.sizeof'mdb_t', 'mdb_t', m)
		for _,rs in ipairs(m.roomStates) do
			assert(rs.select)
			mem:add(ffi.cast('uint8_t*', rs.select) - rom, ffi.sizeof(rs.select_ctype), 'roomselect', m)
			mem:add(ffi.cast('uint8_t*', rs.ptr) - rom, ffi.sizeof'roomstate_t', 'roomstate_t', m)
			if rs.scrollData then
				-- sized mdb width x height
				local addr = topc(self.scrollBank, rs.ptr.scroll)
				mem:add(addr, #rs.scrollData, 'scrolldata', m)
			end
			
			mem:add(topc(self.fx1Bank, rs.ptr.fx1), #rs.fx1s * ffi.sizeof'fx1_t' + (rs.fx1term and 2 or 0), 'fx1_t', m)
			mem:add(topc(self.bgBank, rs.ptr.bgdata), #rs.bgs * ffi.sizeof'bg_t' + 8, 'bg_t', m)
		end
		
		mem:add(topc(self.doorAddrBank, m.ptr.doors), #m.doors * 2, 'dooraddrs', m)
		for _,door in ipairs(m.doors) do
			mem:add(ffi.cast('uint8_t*',door.ptr)-rom, ffi.sizeof(door.ctype), door.ctype, m)
			if door.doorCode then
				mem:add(door.doorCodeAddr, #door.doorCode, 'door code', m)
			end
		end
	end

	for _,layerHandling in ipairs(self.layerHandlings) do
		mem:add(layerHandling.addr, #layerHandling.code, 'layer handling code', layerHandling.roomStates[1].m)
	end

	for _,enemyPopSet in ipairs(self.enemyPopSets) do
		mem:add(enemyPopSet.addr, 3 + #enemyPopSet.enemyPops * ffi.sizeof'enemyPop_t', 'enemyPop_t', enemyPopSet.roomStates[1].m)
	end
	for _,enemySetSet in ipairs(self.enemySetSets) do
		mem:add(enemySetSet.addr, 10 + #enemySetSet.enemySets * ffi.sizeof'enemySet_t', 'enemySet_t', enemySetSet.roomStates[1].m)
	end

	for _,plmset in ipairs(self.plmsets) do
		local m = plmset.roomStates[1].m
		--[[ entry-by-entry
		local addr = plmset.addr
		for _,plm in ipairs(plmset.plms) do
			mem:add(addr, ffi.sizeof'plm_t', 
				'plm_t',
				--'plm '..ffi.cast('plm_t*',rom+addr)[0], 
				m)
			addr = addr + ffi.sizeof'plm_t'
		end
		mem:add(addr, 2, 
			'plm_t term',
			--'plm '..ffi.cast('uint16_t*',rom+addr)[0], 
			m)
		--]]
		-- [[ all at once
		local len = 2 + #plmset.plms * ffi.sizeof'plm_t'
		mem:add(plmset.addr, len, 'plm_t', m)
		--]]
		for _,scrollmod in ipairs(plmset.scrollmods) do	
			mem:add(scrollmod.addr, #scrollmod.data, 'plm scrollmod', m)
		end
	end
	for _,room in ipairs(self.rooms) do
		mem:add(room.addr, room.compressedSize, 'room', room.mdbs[1])
	end
end

function SMMap:mapWritePLMs()
	local rom = self.rom
	
	-- [[ re-indexing the doors
	--[=[
	notes on doors:
	plm_t of door_* has an x and y that matches up with the door region in the map
	the plm arg low byte of each (non-blue) door is a unique index, contiguous 0x00..0x60 and 0x80..0xac
	(probably used wrt savefiles, to know what doors have been opened)
	certain grey doors have nonzero upper bytes, either  0x00, 0x04, 0x08, 0x0c, 0x18, 0x90, 0x94
	--]=]
	print'all door plm ids:'
	-- re-id all door plms?
	local doorid = 0
	for _,plmset in ipairs(self.plmsets) do
		local eyeparts
		local eyedoor
		for _,plm in ipairs(plmset.plms) do
			local name = self.plmCmdNameForValue[plm.cmd]
			if name 
			and name:match'^door_' 
			then
				-- if it's an eye door part then
				--  find the associated eye door, and make sure their ids match up
				if name:match'^door_eye_.*_part' then
					eyeparts = eyeparts or table()
					eyeparts:insert(plm)
				elseif name:match'^door_eye_' then
					assert(not eyedoor, "one eye door per room, I guess")
					eyedoor = plm
				end
				
				plm.args = bit.bor(bit.band(0xff00, plm.args), doorid)
				doorid = doorid + 1
			end
		end
		if eyedoor then 
			assert(eyeparts and #eyeparts > 0)
			for _,part in ipairs(eyeparts) do
				part.args = eyedoor.args
			end
		end
	end
	-- notice, I only see up to 0xac used, so no promises there is even 0xff available in memory
	assert(doorid <= 0xff, "got too many doors: "..doorid)
	--]]

	-- [[ re-indexing the items ...
	local itemid = 0
	for _,plmset in ipairs(self.plmsets) do
		for _,plm in ipairs(plmset.plms) do
			local name = self.plmCmdNameForValue[plm.cmd]
			if name and name:match'^item_' then
				plm.args = itemid
				itemid = itemid + 1 
			end
		end
	end
	--assert(itemid <= 100, "too many items (I think?)")
	--]]

	-- [[ optimizing plms ... 
	-- if a plmset is empty then clear all rooms that point to it, and remove it from the plmset master list
	for _,plmset in ipairs(self.plmsets) do
		if #plmset.plms == 0 then
			for j=#plmset.roomStates,1,-1 do
				local rs = plmset.roomStates[j]
				rs.ptr.plm = 0	-- don't need to change this -- it'll be reset later
				rs:setPLMSet(nil)
			end
		end
	end
	-- [=[ remove empty plmsets
	for i=#self.plmsets,1,-1 do
		local plmset = self.plmsets[i]
		if #plmset.plms == 0 then
			self.plmsets:remove(i)
		end
	end
	--]=]
	-- [[ remove plmsets not referenced by any roomstates
	for i=#self.plmsets,1,-1 do
		local plmset = self.plmsets[i]
		if #plmset.roomStates == 0 then
			print('!!! removing empty plmset !!!')	
			self.plmsets:remove(i)
		end
	end
	--]]
	-- get rid of any duplicate plmsets ... there are none by default
	for i=1,#self.plmsets-1 do
		local pi = self.plmsets[i]
		for j=i+1,#self.plmsets do
			local pj = self.plmsets[j]
			if #pi.plms == #pj.plms 
			-- a lot of zero-length plms match ... but what about non-zero-length plms? none match
			and #pi.plms > 0
			then
				local differ
				for k=1,#pi.plms do
					if pi.plms[k] ~= pj.plms[k] then
						differ = true
						break
					end
				end
				if not differ then
					print('plms '..('$%06x'):format(pi.addr)..' and '..('$%06x'):format(pj.addr)..' are matching')
				end
			end
		end
	end
	--]]

	-- [[ writing back plms...
	-- TODO this is causing a problem -- room 03/04, the main room of wrecked ship, isn't scrolling out of the room correctly
	--[=[
	plm memory ranges:
	 0/ 0: $078000..$079193 (plm_t x174) 
	 3/ 0: $07c215..$07c230 (plm_t x2) 
		... 20 bytes of padding ...
	 3/ 3: $07c245..$07c2fe (plm_t x15) 
		... 26 bytes of padding ...
	 3/ 3: $07c319..$07c8c6 (plm_t x91) 
		... 199 bytes of padding ...
	--]=]
	-- where plms were written before, so should be safe, right?
	-- ranges are inclusive
	local plmWriteRanges = WriteRange('plm', {
		{0x78000, 0x79193},	
		-- then comes 100 bytes of layer handling code, then mdb's
		{0x7c215, 0x7c8c6},
		-- next comes 199 bytes of layer handling code, which is L12 data, and then more mdb's
		{0x7e87f, 0x7e880},	-- a single plm_t 2-byte terminator ...
		-- then comes a lot of unknown data 
		{0x7e99B, 0x7ffff},	-- this is listed as 'free data' in the metroid rom map
					-- however $7ff00 is where the door code of room 01/0e points to... which is the door_t on the right side of the blue brinstar morph ball room
	})

	-- TODO any code that points to a PLM needs to be updated as well
	-- like whatever changes doors around from blue to grey, etc
	-- otherwise you'll find grey doors where you don't want them
	print()
	for _,plmset in ipairs(self.plmsets) do
		local bytesToWrite = #plmset.plms * ffi.sizeof'plm_t' + 2	-- +2 for null term
		local addr, endaddr = plmWriteRanges:get(bytesToWrite)
		plmset.addr = addr 

		-- write
		for _,plm in ipairs(plmset.plms) do
			ffi.cast('plm_t*', rom + addr)[0] = plm
			addr = addr + ffi.sizeof'plm_t'
		end
		-- write term
		ffi.cast('uint16_t*', rom+addr)[0] = 0
		addr = addr + ffi.sizeof'uint16_t'
		assert(addr == endaddr)

		local newofs = bit.band(0xffff, plmset.addr)
		for _,rs in ipairs(plmset.roomStates) do
			if newofs ~= rs.ptr.plm then
				--print('updating roomstate plm from '..('%04x'):format(rs.ptr.plm)..' to '..('%04x'):format(newofs))
				rs.ptr.plm = newofs
			end
		end
	end
	plmWriteRanges:print()
	--]]
end

function SMMap:mapWriteMDBs()
	local rom = self.rom
	-- writing back mdb_t
	-- if you move a mdb_t
	-- then don't forget to reassign all mdb.dooraddr.door_t.dest_mdb
	local mdbWriteRanges = WriteRange('mdb', {
		{0x791f8, 0x7b769},	-- mdbs of regions 0-2
		-- then comes bg_t's and door codes and plm_t's
		{0x7c98e, 0x7e0fc},	-- mdbs of regions 3-6
		-- then comes db_t's and door codes 
		{0x7e82c, 0x7e85a},	-- single mdb of region 7
		-- then comes door code
	})
end

function SMMap:mapWriteRooms()
	local rom = self.rom
	-- [[ write back compressed data
	local roomWriteRanges = WriteRange('room', {
		--[=[ there are some bytes outside compressed regions but between a few roomdatas
		-- the metroid rom map says these are a part of the room data
		-- this includes those breaks
		{0x2142bb, 0x235d76},
		{0x235ee0, 0x244da8},
		{0x24559c, 0x272502},
		{0x272823, 0x27322d},
		--]=]
		-- [=[ and this doesn't -- one giant contiguous region
		{0x2142bb, 0x277fff},
		--]=]
	})
	-- ... reduces to 56% of the original compressed data
	-- but goes slow
	local totalOriginalCompressedSize = 0
	local totalRecompressedSize = 0
	print()
	for _,room in ipairs(self.rooms) do
		local data = room:getData()
		local recompressed = lz.compress(data)
	--	print('recompressed size: '..ffi.sizeof(recompressed)..' vs original compressed size '..room.compressedSize)
	-- this doesn't matter
	--	assert(ffi.sizeof(recompressed) <= room.compressedSize, "recompressed to a larger size than the original.  recompressed "..ffi.sizeof(recompressed).." vs original "..room.compressedSize)
		totalOriginalCompressedSize = totalOriginalCompressedSize + room.compressedSize
		totalRecompressedSize = totalRecompressedSize + ffi.sizeof(recompressed)
		
		data = recompressed
		room.compressedSize = ffi.sizeof(recompressed)
		--[=[ now write back to the original location at addr
		ffi.copy(rom + room.addr, data, ffi.sizeof(data))
		--]=]
		-- [=[ write back at a contiguous location
		-- (don't forget to update all roomstate_t's roomBank:roomAddr's to point to this
		-- TODO this currently messes up the scroll change in wrecked ship, when you go to the left to get the missile in the spike room
		local fromaddr, toaddr = roomWriteRanges:get(ffi.sizeof(data))

		-- do the write
		ffi.copy(rom + fromaddr, data, ffi.sizeof(data))
		-- update room addr
	--	print('updating room address '
	--		..('%02x/%02x'):format(room.mdbs[1].ptr.region, room.mdbs[1].ptr.index)
	--		..' from '..('$%06x'):format(room.addr)..' to '..('$%06x'):format(fromaddr))
		room.addr = fromaddr
		-- update any roomstate_t's that point to this data
		for _,rs in ipairs(room.roomStates) do
			rs.ptr.roomBank = bit.rshift(room.addr, 15) + 0x80 
			rs.ptr.roomAddr = bit.band(room.addr, 0x7fff) + 0x8000
		end
		--]=]

	--[=[ verify that compression works by decompressing and re-compressing
		local data2, compressedSize2 = lz.decompress(rom, room.addr, 0x10000)
		assert(compressedSize == compressedSize2)
		assert(ffi.sizeof(data) == ffi.sizeof(data2))
		for i=0,ffi.sizeof(data)-1 do
			assert(data[i] == data2[i])
		end
	--]=]
	end
	print()
	print('rooms recompressed from '..totalOriginalCompressedSize..' to '..totalRecompressedSize..
		', saving '..(totalOriginalCompressedSize - totalRecompressedSize)..' bytes '
		..'(new data is '..math.floor(totalRecompressedSize/totalOriginalCompressedSize*100)..'% of original size)')

	-- output memory ranges
	roomWriteRanges:print()
	--]]
end

function SMMap:mapWriteEnemyPops()
	local rom = self.rom
	--[[ get rid of duplicate enemy pops
	-- this currently crashes the game
	-- notice that re-writing the enemy pops is working fine
	-- but removing the duplicates crashes as soon as the first room with monsters is encountered 
	for i=1,#self.enemyPopSets-1 do
		local pi = self.enemyPopSets[i]
		for j=#self.enemyPopSets,i+1,-1 do
			local pj = self.enemyPopSets[j]
			if #pi.enemyPops == #pj.enemyPops 
			and pi.enemiesToKill == pj.enemiesToKill 
			then
				local differ
				for k=1,#pi.enemyPops do
					if pi.enemyPops[k] ~= pj.enemyPops[k] then
						differ = true
						break
					end
				end
				if not differ then
					print('enemyPops '..('$%06x'):format(pi.addr)..' and '..('$%06x'):format(pj.addr)..' are matching')
					for _,rs in ipairs(pj.roomStates) do
						rs.ptr.enemyPop = bit.band(0xffff, pi.addr)
						rs.enemyPopSet = pi
					end
					self.enemyPopSets:remove(j)
				end
			end
		end
	end
	--]]

	-- [[ update enemy pop
	--[=[
	with writing back plms removing onn-grey non-eye doors
	and writing back room data, removing all breakable blocks and crumble blocks
	and writing back enemy pop ranges
	I did a playthrough and found the following bugs:
	* a few grey doors - esp kill quota rooms - would not be solid
	* one grey door was phantoon ... and walking outside mid-battle would show garbage tiles in the next room.
		note that the room was normal before and after the battle.
	* scroll glitch in the crab broke tube room in maridia
	--]=]
	local enemyPopWriteRanges = WriteRange('enemy pop sets', {
		-- original pop goes up to $10ebd0, but the super metroid ROM map says the end of the bank is free
		{0x108000, 0x10ffff},
	})
	for _,enemyPopSet in ipairs(self.enemyPopSets) do
		local addr, endaddr = enemyPopWriteRanges:get(3 + #enemyPopSet.enemyPops * ffi.sizeof'enemyPop_t')
		enemyPopSet.addr = addr
		for i,enemyPop in ipairs(enemyPopSet.enemyPops) do
			ffi.cast('enemyPop_t*', rom + addr)[0] = enemyPop
			addr = addr + ffi.sizeof'enemyPop_t'
		end
		ffi.cast('uint16_t*', rom + addr)[0] = 0xffff
		addr = addr + 2
		rom[addr] = enemyPopSet.enemiesToKill
		addr = addr + 1

		assert(addr == endaddr)
		local newofs = bit.band(0xffff, enemyPopSet.addr)
		for _,rs in ipairs(enemyPopSet.roomStates) do
			if newofs ~= rs.ptr.enemyPop then
				print('updating roomstate enemyPop addr from '..('%04x'):format(rs.ptr.enemyPop)..' to '..('%04x'):format(newofs))
				rs.ptr.enemyPop = newofs
			end
		end
	end
	enemyPopWriteRanges:print()
	--]]
end
	
function SMMap:mapWriteEnemySets()
	local rom = self.rom
	--[[ update enemy set
	-- I'm sure this will fail.  there's lots of mystery padding here.
	local enemySetWriteRanges = WriteRange('enemy set sets', {
		{0x1a0000, 0x1a12c5},
		-- next comes a debug routine, listed as $9809-$981e
		-- then next comes a routine at $9961 ...
	})
	for _,enemySetSet in ipairs(self.enemySetSets) do
		local addr, endaddr = enemySetWriteRanges:get(#enemySetSet.enemySets * ffi.sizeof'enemySet_t')
		enemySetSet.addr = addr
		for i,enemySet in ipairs(enemySetSet.enemySets) do
			ffi.cast('enemySet_t*', rom + addr)[0] = enemySet
			addr = addr + ffi.sizeof'enemySet_t'
		end
		-- TODO tail ... which I'm not saving yet, and I don't know how long it should be

		assert(addr == endaddr)
		local newofs = bit.band(0x7fff, enemySetSet.addr) + 0x8000
		for _,rs in ipairs(enemySetSet.roomStates) do
			if newofs ~= rs.ptr.enemySet then
				print('updating roomstate enemySet addr from '..('%04x'):format(rs.ptr.enemySet)..' to '..('%04x'):format(newofs))
				rs.ptr.enemySet = newofs
			end
		end
	end
	enemySetWriteRanges:print()
	--]]
end

-- write back changes to the ROM
-- right now my structures are mixed between ptrs and by-value copied objects
-- so TODO eventually have all ROM writing in this routine
function SMMap:mapWrite()
	self:mapWritePLMs()	
	self:mapWriteMDBs()	-- not yet
	self:mapWriteRooms()
	self:mapWriteEnemyPops()	-- buggy
	self:mapWriteEnemySets()	-- not yet
end

return SMMap
