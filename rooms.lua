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

--[[
-- plm randomization:
-- randomize ... remove only for now
-- removing turns a door blue
-- TODO when combined with modifying tiles, this is screwing up door transitions
for _,plmset in ipairs(sm.plmsets) do
	--[=[ remove all door plms
	for i=#plmset.plms,1,-1 do
		local plm = plmset.plms[i]
		local plmName = sm.plmCmdNameForValue[plm.cmd]
		if plmName then
			local color, side = plmName:match'^door_(%w+)_(%w+)'
			if side then
				plmset.plms:remove(i)
			end
		end						
	end
	--]=]
	--[=[ change all doors to red
	for _,plm in ipairs(plmset.plms) do
		local name = sm.plmCmdNameForValue[plm.cmd]
		if name then
			local color, side = name:match'^door_(%w+)_(%w+)'
			if side then
				plm.cmd = assert(sm.plmCmdValueForName['door_red_'..side])
			end
		end
	end
	--]=]
	
	-- get rid of region-room 1-16's plm's
	local m = plmset.roomStates[1].m
	if m.region == 1 and m.index == 0x10 then
		for _,rs in ipairs(m.roomStates) do
			rs.ptr.plm = 0
			assert(rs.plmset == plmset)
			rs.plmset = nil
			plmset.roomStates:removeObject(rs)
		end
	end

	-- if we erased all plms then we should clear all flags in all referencing rooms
	if #plmset.plms == 0 then
		for _,rs in ipairs(plmset.roomStates) do
			rs.ptr.plm = 0
			rs.plmset = nil
		end
	end
end
--]]



-- [[ optimizing plms ... 
-- if the roomstate points to an empty plmset then it can be cleared
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

-- get rid of any duplicates 
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
-- then don't forget to reassign all mdb.dooraddr.door_t.destmdb
local mdbWriteRanges = WriteRange'mdb'{
	{0x791f8, 0x7b769},	-- mdbs of regions 0-2
	-- then comes bg_t's and door codes and plm_t's
	{0x7c98e, 0x7e0fc},	-- mdbs of regions 3-6
	-- then comes db_t's and door codes 
	{0x7e82c, 0x7e85a},	-- single mdb of region 7
	-- then comes door code
}


--[[ do some modifications
-- hmm, todo, don't write over the doors ...
-- look out for 41-ff-fe-fd in horizontal or vertical order
-- then, beside it will be the door ID #... don't change that ...
-- it could be in the middle of the map too
-- ... it'd be nice if all the door locations were stored in a list somewhere
-- but I see the door_t's ... that seems to be pointed *to* by the door bts data, not vice versa 
for _,room in ipairs(sm.rooms) do
	local w,h = room.width, room.height

-- [=[ change blocks around, skipping any ID #'s near the door regions
-- I probably need to skip elevator shafts too, I bet ...
	for j=0,h-1 do
		for i=0,w-1 do
			-- make sure we're not 1 block away from any door regions on any side
			local neardoor
			for _,doorRegion in ipairs(room.doorRegions) do
				if i >= doorRegion.x - 1 and i <= doorRegion.x + doorRegion.w
				-- technically you only need the +1 extra if it is a horizontal door, not a vertical
				and j >= doorRegion.y - 2 and j <= doorRegion.y + doorRegion.h + 1
				then
					neardoor = true
					break
				end
			end
			if not neardoor then
				local v = room.bts[1+ i + w * j]
		
--[==[
bit 0 = 2-wide
bit 1 = 2-high
bit 2:3 = 0 = shot, 1 = bomb, 2 = super missile, 3 = power bomb
looks like this might be a combination with plms...
because 0-7 can be bomb or shot
and 0-3 can also be lifts
--]==]
			
				if false
				--or (v >= 0 and v <= 3) -- bomb ... ? and also doors, and platforms, and IDs for doors and platforms
				or (v >= 4 and v <= 7) -- bomb in most rooms, shoot in 1/16 ...
				or v == 8 -- super missile
				or v == 9 -- power bomb
				then
					--v = 0 -- means bombable/shootable, respawning
					--v = 4	-- means bombable/shootable, no respawning, or it means fallthrough block
					--v = 0xc
					
					-- btw, how come there are bts==0 bombable blocks? (escaping alcatraz)
					room.bts[1+ i + w * j] = v
				end
			end
		end
	end
--]=]
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
		..('%02x'):format(room.mdbs[1].ptr.region)
			..'/'..('%02x'):format(room.mdbs[1].ptr.index)
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
