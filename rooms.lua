local ffi = require 'ffi'
local lz = require 'lz'
local class = require 'ext.class'

local rom = sm.rom

local WriteRangeClass = class()

function WriteRangeClass:init(ranges)
	self.ranges = ranges
	for _,range in ipairs(self.ranges) do
		range.sofar = range[1]
	end
end

function WriteRangeClass:get(len)
	local range = select(2, table.find(self.ranges, nil, function(range)
		return range.sofar + len <= range[2]+1 
	end))
	assert(range, "couldn't find anywhere to write "..self.name)
	local fromaddr = range.sofar
	range.sofar = range.sofar + len
	return fromaddr, range.sofar
end

function WriteRangeClass:print()
	print()
	print(self.name..' write usage:')
	for _,range in ipairs(self.ranges) do
		print('range '
			..('%04x'):format(range[1])..'..'..('%04x'):format(range[2])
			..'  '..('%04x'):format(range.sofar)..' used = '
			..('%.1f'):format(100*(range.sofar-range[1])/(range[2]-range[1]+1))..'% of '
			..('%04x'):format(range[2]-range[1]+1)..' bytes')
	end
end

local function WriteRange(name)
	return function(ranges)
		local range = WriteRangeClass(ranges)
		range.name = name
		return range
	end
end

-- [[
--[=[
randomizing all doors ...
1) enumerate all door regions
2) find plms associated with each door region
3) for doors that have no plm associated, make a new one
4) last make sure to give doors unique ids 
--]=]
local newDoorCount = 0
for _,m in ipairs(sm.mdbs) do
	for _,rs in ipairs(m.roomStates) do
		local room = rs.room
		for _,door in ipairs(room.doors) do
			-- TODO store this in room load
			local plmindex, plm = rs.plmset.plms:find(nil, function(plm)
				return plm.x == door.x and plm.y == door.y
			end)
		
			-- if there already exists a plm...
			local saveThisDoor
			if plm then
				local plmname = assert(sm.plmCmdNameForValue[plm.cmd], "expected door plm to have a valid name "..plm)
				assert(plmname:match'^door_')
				-- don't touch special doors
				if plmname:match'^door_grey_' 
				or plmname:match'^door_eye_' 
				then
newDoorCount = newDoorCount + 1				
					saveThisDoor = true
				else 
					-- then this plm is for this door ...	
					-- so remove it?
					rs.plmset.plms:remove(plmindex)
				end
			end
		
			--[=[ now roll for this door
			if not saveThisDoor 
			and newDoorCount < 0xf5
			then
				local color = math.random(9)	-- red, green, orange, rest are blue options
				if color <= 3 then	-- skip blue doors completely
					color = ({'red', 'green', 'orange'})[color]
					local dir = ({'right', 'left', 'down', 'up'})[door.dir+1]
					local plm = ffi.new'plm_t'
					local plmname = 'door_'..color..'_'..dir
					plm.cmd = assert(sm.plmCmdValueForName[plmname], "failed to find plm cmd named "..plmname)
					plm.x = door.x
					plm.y = door.y
					plm.args = 0
					rs.plmset.plms:insert(plm)
newDoorCount = newDoorCount + 1				
				end	
			end
			--]=]
		end
	end
end
print('created '..newDoorCount..' new doors')
--]]

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
for _,plmset in ipairs(sm.plmsets) do
	local eyeparts
	local eyedoor
	for _,plm in ipairs(plmset.plms) do
		local name = sm.plmCmdNameForValue[plm.cmd]
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
			--print(name .. ' '..('.'):rep(maxnamelen - #name) .. ' '.. ('%04x'):format(tonumber(plm.args)))
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
if doorid >= 0xff then error("got too many doors: "..doorid) end
--]]

-- [[ optimizing plms ... 
-- if a plmset is empty then clear all rooms that point to it, and remove it from the plmset master list
for _,plmset in ipairs(sm.plmsets) do
	if #plmset.plms == 0 then
		for j=#plmset.roomStates,1,-1 do
			local rs = plmset.roomStates[j]
			rs.ptr.plm = 0
			rs.plmset = nil
			plmset.roomStates[j] = nil
		end
	end
end
-- [=[ remove empty plmsets
for i=#sm.plmsets,1,-1 do
	local plmset = sm.plmsets[i]
	if #plmset.plms == 0 then
		sm.plmsets:remove(i)
	end
end
--]=]
-- get rid of any duplicate plmsets ... there are none by default
for i=1,#sm.plmsets-1 do
	local pi = sm.plmsets[i]
	for j=i+1,#sm.plmsets do
		local pj = sm.plmsets[j]
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
local plmWriteRanges = WriteRange'plm'{
 	{0x78000, 0x79193},	
 	-- then comes 100 bytes of layer handling code, then mdb's
	{0x7c215, 0x7c8c6},
 	-- next comes 199 bytes of layer handling code, which is L12 data, and then more mdb's
	{0x7e87f, 0x7e880},	-- a single plm_t 2-byte terminator ...
	-- then comes a lot of unknown data 
	{0x7e99B, 0x7ffff},	-- this is listed as 'free data' in the metroid rom map
				-- however $7ff00 is where the door code of room 01/0e points to... which is the door_t on the right side of the blue brinstar morph ball room
}

-- TODO any code that points to a PLM needs to be updated as well
-- like whatever changes doors around from blue to grey, etc
-- otherwise you'll find grey doors where you don't want them
print()
for _,plmset in ipairs(sm.plmsets) do
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

	for _,rs in ipairs(plmset.roomStates) do
		local newofs = bit.band(0xffff, plmset.addr)
		if newofs ~= rs.ptr.plm then
			--print('updating roomstate plm from '..('%04x'):format(rs.ptr.plm)..' to '..('%04x'):format(newofs))
			rs.ptr.plm = newofs
		end
	end
end
plmWriteRanges:print()
--]]



-- writing back mdb_t
-- if you move a mdb_t
-- then don't forget to reassign all mdb.dooraddr.door_t.dest_mdb
local mdbWriteRanges = WriteRange'mdb'{
	{0x791f8, 0x7b769},	-- mdbs of regions 0-2
	-- then comes bg_t's and door codes and plm_t's
	{0x7c98e, 0x7e0fc},	-- mdbs of regions 3-6
	-- then comes db_t's and door codes 
	{0x7e82c, 0x7e85a},	-- single mdb of region 7
	-- then comes door code
}


-- [[ do some modifications
--[=[ hmm, todo, don't write over the doors ...
look out for 41-ff-fe-fd in horizontal or vertical order
then, beside it will be the door ID #... don't change that ...
it could be in the middle of the map too
... it'd be nice if all the door locations were stored in a list somewhere
but I see the door_t's ... that seems to be pointed *to* by the door bts data, not vice versa 

change blocks around, skipping any ID #'s near the door regions
I probably need to skip elevator shafts too, I bet ...

channel A = low byte of blocks, B = high byte of blocks, C = byte of BTS

block types:
bit 0 = 2-wide
bit 1 = 2-high
bit 2:3 = 0 = shot, 1 = bomb, 2 = super missile, 3 = power bomb
looks like this might be a combination with plms...
because 0-7 can be bomb or shot
and 0-3 can also be lifts

maybe it's the high byte of the block data?
93 correlates with empty left-right exit
90 90 98 98 = right door
94 94 9c 9c = left door
90 correlates with lift exit
I'm thinking 08 means flip up-down and 04 means flip left-right
but then .. 90 is exit?

low byte is the gfx I'm betting
high byte:
low nibble:
04 = flip up/down
08 = flip left/right:
high nibble:
50 = crumble
80 = solid
90 = exit (see channel C for door index)
B=b1, C=05 = crumble, no respawn
B=b1, C=0f = speed
c0 = shootable / powerbomb, no respawn
d0 = another bombable?
f0 = bombable, no respawn
--]=]
for _,room in ipairs(sm.rooms) do
	local w,h = room.width, room.height

	for j=0,h-1 do
		for i=0,w-1 do
			-- make sure we're not 1 block away from any door regions on any side
			local neardoor
			for _,door in ipairs(room.doors) do
				if i >= door.x - 1 and i <= door.x + door.w
				-- technically you only need the +1 extra if it is a horizontal door, not a vertical
				and j >= door.y - 2 and j <= door.y + door.h + 1
				then
					neardoor = true
					break
				end
			end
			if not neardoor then
				local a = room.blocks[1+ 0+ 3*(i + w * j)]
				local b = room.blocks[1+ 1+ 3*(i + w * j)]
				local c = room.blocks[1+ 2+ 3*(i + w * j)]
				-- notice that doors and platforms and IDs for doors and platforms can be just about anything
				if false
				or (bit.band(b, 0xf0) == 0xf0)	-- bombable
				or (bit.band(b, 0xf0) == 0xb0)	-- crumble 
				or (bit.band(b, 0xf0) == 0xc0)	-- shootable / powerbombable / super missile / speed booster?
				
				-- repeat tiles ...
				or (
					(
						bit.band(b, 0xf0) == 0xf0 
						or bit.band(b, 0xf0) == 0xd0
						or bit.band(b, 0xf0) == 0x50
					) 
					and c == 0xff
				)	-- repeat ... up, left, or up/left tile (based on b's bits?)
				-- but only if the neighbor tiles are what we're looking for?

				--or (bit.band(b, 0x50) == 0x50 and c == 5)	-- fall through
				--or (c >= 4 and c <= 7) 
				--or c == 8 -- super missile
				--or c == 9 -- power bomb .. if high byte high nibble is c
				--or c == 0xf	-- speed block
				then
					room.blocks[1+ 0+ 3*(i + w * j)] = 0xff
					room.blocks[1+ 1+ 3*(i + w * j)] = 0
					room.blocks[1+ 2+ 3*(i + w * j)] = 0
					
					--c = 0 -- means bombable/shootable, respawning
					--c = 4	-- means bombable/shootable, no respawning, or it means fallthrough block
					--c = 0xc
					
					-- btw, how come there are ch3==0 bombable blocks? (escaping alcatraz)
					--room.blocks[1+ 2+ 3*(i + w * j)] = c
					
--					b = bit.bor(bit.band(b, 0x0f), 0xc0)
--					room.blocks[1+ 1+ 3*(i + w * j)] = b
				end
			end
		end
	end
end
--]]
--[[ remove all doors, just leave exits
--[=[ ok some important notes from doing this
the doors themselves don't go away.  even with the plm gone, there are still physical things blocking me.
removing the 4x ff fe fd just remove the copy codes of the shootable block type
  and so in their place is now just a single regular shootable block
so what tells the door to exist?  is it the 16-bit block data? should that be ff00 as well?
if not this then it seems like there is some extra data I'm missing that tells doors where they should exist
... not the plm
... not the 40-43 ch3 data
... not the door_t, I think, unless somewhere in there is x,y locations of where to put doors
	or possibly which room / which side to put doors?
--]=]
for _,room in ipairs(sm.rooms) do
	local w,h = room.width, room.height
	for _,door in ipairs(room.doors) do
		local i,j = door.x, door.y
		for k=0,3 do
			if door.dir == 0 or door.dir == 1 then	-- left/right
				room.blocks[1+ 2+ 3*((i+k) + w * j)] = 0
			elseif door.dir == 2 or door.dir == 3 then	-- up/down
				room.blocks[1+ 2+ 3*(i + w * (j+k))] = 0
			else
				error'here'
			end
		end
	end
end
--]]


-- [[ write back compressed data
local roomWriteRanges = WriteRange'room'{
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
}
-- ... reduces to 56% of the original compressed data
-- but goes slow
local totalOriginalCompressedSize = 0
local totalRecompressedSize = 0
print()
for _,room in ipairs(sm.rooms) do
	local data = room:getData()
	local recompressed = lz.compress(data)
	print('recompressed size: '..#recompressed..' vs original compressed size '..room.compressedSize)
	assert(#recompressed <= room.compressedSize, "recompressed to a larger size than the original.  recompressed "..#recompressed.." vs original "..room.compressedSize)
totalOriginalCompressedSize = totalOriginalCompressedSize + room.compressedSize
totalRecompressedSize = totalRecompressedSize + #recompressed
	data = recompressed
	room.compressedSize = #recompressed
	--[=[ now write back to the original location at addr
	for i,v in ipairs(data) do
		rom[room.addr+i-1] = v
	end
	--]=]
	-- [=[ write back at a contiguous location
	-- (don't forget to update all roomstate_t's roomBank:roomAddr's to point to this
	-- TODO this currently messes up the scroll change in wrecked ship, when you go to the left to get the missile in the spike room
	local fromaddr, toaddr = roomWriteRanges:get(#data)

	-- do the write
	for i,v in ipairs(data) do
		rom[fromaddr+i-1] = v
	end
	-- update room addr
	print('updating room address '
		..('%02x/%02x'):format(room.mdbs[1].ptr.region, room.mdbs[1].ptr.index)
		..' from '..('$%06x'):format(room.addr)..' to '..('$%06x'):format(fromaddr))
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
	assert(#data == #data2)
	for i=1,#data do
		assert(data[i] == data2[i])
	end
--]=]
end
print()
print('overall recompressed from '..totalOriginalCompressedSize..' to '..totalRecompressedSize..
	', saving '..(totalOriginalCompressedSize - totalRecompressedSize)..' bytes '
	..'(new data is '..math.floor(totalRecompressedSize/totalOriginalCompressedSize*100)..'% of original size)')

-- output memory ranges
roomWriteRanges:print()
--]]
