local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local Blob = require 'blob'

local RoomBlocks = class(Blob)

RoomBlocks.blocksPerRoom = 16

-- for Blob ctor: read always compressed
RoomBlocks.compressed = true

function RoomBlocks:init(args)
	assert(args.compressed == nil)
	assert(args.type == nil)
	
	RoomBlocks.super.init(self, args)
	
	local dataSize = ffi.sizeof(self.data)
	local m = args.m

	-- list of unique rooms that have roomstates that use this roomBlockData
	-- don't add/remove to this list, instead use :refreshRooms()
	self.rooms = table()
	
	self.roomStates = table()

	local ofs = 0
	
	self.offsetToCh3 = ffi.cast('uint16_t*', self.data)[0]

	-- offsetToCh3 is the offset to channel 3 of the blocks
	-- and is usually = 2*w*h, sometimes >2*w*h
	--  in that case ... what's in the padding?

	local w = m.obj.width * self.blocksPerRoom
	local h = m.obj.height * self.blocksPerRoom
	
	assert(self.offsetToCh3 >= 2*w*h, "found an offset to bts/channel3 that doesn't pass the ch1 and 2 room blocks")

	-- this is just 16 * room's (width, height)
	self.width = w
	self.height = h

--print('offset to ch3', self.offsetToCh3)
--print('numblocks', ffi.sizeof(self.data) - 2)
--print('decompressed / numblocks', (ffi.sizeof(self.data) - 2) / (w * h))
--print('offset to ch 3 / numblocks', self.offsetToCh3 / (w * h))
--print('decompressed / offset to ch 3', (ffi.sizeof(self.data) - 2) / self.offsetToCh3)
	-- decompressed / numblocks is only ever 3 or 5
	-- what determines which?
	if (ffi.sizeof(self.data) - 2) / (w * h) < 3 then
		print("WARNING - room has not enough blocks to fill the room")
		return
	end

	-- TODO what happens when self.offsetToCh3 is > 2*w*h
	ofs = ofs + 2 + self.offsetToCh3 / 2 * 3
	-- channel 3 ... referred to as 'bts' = 'behind the scenes' in some docs.  I'm just going to interleave everything.
	if ofs > dataSize then
		error("didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..dataSize)
	end
	-- if there's still more to read...
	if ofs < dataSize then
		if dataSize - ofs < 2 * w * h then
			print("WARNING - didn't get enough tile data from decompression for layer 2 data. expected room data size "..ofs.." <= data we got "..dataSize)
		else
			self.hasLayer2Blocks = true
		end
	end


	-- keep track of doors
	
	-- ok, this correlates with the door plms, so it is useful
	--  but it isn't general to all exits
	self.doors = table()	-- x,y,w,h
	-- so that's where this comes in.  it is general to all exits.
	-- 	key is the exit, value is a list of all positions of each exit xx9xyy block
	self.blocksForExit = table()
	local blocks12 = self:getBlocks12()
	local blocks3 = self:getBlocks3()
	for j=0,h-1 do	-- ids of horizontal regions (up/down doors) are 2 blocks from the 4xfffefd pattern
		for i=0,w-1 do
			local index = i + w * j
			local a = blocks12[0 + 2 * index]
			local b = blocks12[1 + 2 * index]
			local c = blocks3[index]

-- [[
-- look for 0x9x in ch2 of of self.blocks
			if bit.band(b, 0xf0) == 0x90 then
				local exitIndex = c
				self.blocksForExit[exitIndex] = self.blocksForExit[exitIndex] or table()
				self.blocksForExit[exitIndex]:insert{i,j}
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
				and blocks3[(i+1) + w * j] == 0xff 
				and blocks3[(i+2) + w * j] == 0xfe 
				and blocks3[(i+3) + w * j] == 0xfd 
				then
					-- if c == 0x42 then it's down, if c == 0x43 then it's up 
					local doorIndex = c == 0x42 
						and blocks3[i + w * (j+2)]
						or blocks3[i + w * (j-2)]
					self.doors:insert{
						x = i,
						y = j,
						w = 4,
						h = 1,
						dir = bit.band(3, c),
						index = doorIndex,
					}
				elseif j < h-3	-- TODO assert this
				and (c == 0x40 or c == 0x41)
				and blocks3[i + w * (j+1)] == 0xff 
				and blocks3[i + w * (j+2)] == 0xfe 
				and blocks3[i + w * (j+3)] == 0xfd 
				then
					-- if c == 0x41 then it's left, if c == 0x40 then it's right
					local doorIndex = c == 0x40 
						and blocks3[(i+1) + w * j]
						or blocks3[(i-1) + w * j]
					self.doors:insert{
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
end

function RoomBlocks:refreshRooms()
	self.rooms = table()
	for _,rs in ipairs(self.roomStates) do
		self.rooms:insertUnique(assert(rs.room))
	end
end

--[[ for the room tile data:
looks like this is channel 2:
lower nibble channel 2 bits:
bit 0
bit 1 = foreground (not background)
bit 2 = flip up/down
bit 3 = flip left/right

upper-nibble channel 2 values:
0 = empty
1 = slope
2 = spikes
	channel 3 lo:
		0000b = 0 = 1x1 spike solid
		0010b = 2 = 1x1 spike non-solid 
3 = push
	channel 3 lo:
		0000b = 0 = down force x1 (maridia quicksand top of two secrets)
		0001b = 1 = down force x2 (maridia quicksand in bottom of two secret rooms)
		0010b = 2 = down force x3 (maridia quicksand)
		0011b = 3 = down force x4 - can't jump up from (maridia sand downward shafts)
		0101b = 5 = down force x.5 - (maridia sand falling from ceiling)
		1000b = 8 = right
		1001b = 9 = left
4 =
5 = copy what's to the left
6 =
7 =
8 = solid
9 = door
a = spikes / invis blocks
	channel 3:
		0000b = 0 = spikes solid 
		0011b = 3 = spikes non-solid destroyed by walking chozo statue
		1110b = e = invis blocks
		1111b = f = spikes non-solid destroyed by walking chozo statue
				  = also solid sand blocks destroyed by that thing in maridia
b = crumble / speed
	channel 3 lo:
		0000b = 0 = 1x1 crumble regen
		0001b = 1 = 2x1 crumble regen
		0010b = 2 = 1x2 crumble regen
		0011b = 3 = 2x2 crumble regen
		
		0100b = 4 = 1x1 crumble noregen
		0101b = 5 = 2x1 crumble noregen
		0110b = 6 = 1x1 crumble noregen
		0111b = 7 = 2x2 crumble noregen
		
		1110b = e = 1x1 speed regen
		1111b = f = 1x1 speed noregen
c = break by beam / supermissile / powerbomb
	channel 3 lo:
		0000b = 0 = 1x1 beam regen
		0001b = 1 = 1x2 beam regen
		0010b = 2 = 2x1 beam regen
		0011b = 3 = 2x2 beam regen
		
		0100b = 4 = 1x1 beam noregen
		0101b = 5 = 2x1 beam noregen
		0110b = 6 = 1x2 beam noregen
		0111b = 7 = 2x2 beam noregen
		
		1001b = 9 = 1x1 power bomb noregen
		1010b = a = 1x1 super missile regen
		1011b = b = 1x1 super missile noregen
d = copy what's above 
e = grappling
	channel 3 bit 1:
		0000b = 0 = 1x1 grappling
		0001b = 1 = 1x1 grappling breaking regen
		0010b = 2 = 1x1 grappling breaking noregen
f = bombable 
	channel 3 lo:
		0000b = 0 = 1x1 bomb regen
		0001b = 1 = 2x1 bomb regen
		0010b = 2 = 1x2 bomb regen
		0011b = 3 = 2x2 bomb regen
		
		0100b = 4 = 1x1 bomb noregen
		0101b = 5 = 2x1 bomb noregen
		0110b = 6 = 1x2 bomb noregen
		0111b = 7 = 2x2 bomb noregen
--]]

-- this is ch2hi
RoomBlocks.tileTypes = {
	empty 				= 0x0,
	slope				= 0x1,
	spikes				= 0x2,
	push				= 0x3,
	copy_left 	 	 	= 0x5,
	solid 				= 0x8,
	door				= 0x9,
	spikes_or_invis		= 0xa,
	crumble_or_speed	= 0xb,
	breakable 			= 0xc,
	copy_up 			= 0xd,
	grappling			= 0xe,
	bombable			= 0xf,
}
-- this is ch2hi:ch3lo
RoomBlocks.extTileTypes = {
	spike_solid_1x1			= 0x20,
	spike_notsolid_1x1		= 0x22,
	push_quicksand1			= 0x30,
	push_quicksand2			= 0x31,
	push_quicksand3			= 0x32,
	push_quicksand4			= 0x33,
	push_quicksand1_2		= 0x35,
	push_conveyor_right		= 0x38,
	push_conveyor_left		= 0x39,
	spike_solid2_1x1		= 0xa0,
	spike_solid3_1x1		= 0xa1,	-- used in the hallway to kraid
	spike_notsolid2_1x1		= 0xa3,
	invisble_solid			= 0xae,
	spike_notsolid3_1x1		= 0xaf,
	crumble_1x1_regen		= 0xb0,
	crumble_2x1_regen		= 0xb1,
	crumble_1x2_regen		= 0xb2,
	crumble_2x2_regen		= 0xb3,
	crumble_1x1				= 0xb4,
	crumble_2x1				= 0xb5,
	crumble_1x2				= 0xb6,
	crumble_2x2				= 0xb7,
	speed_regen				= 0xbe,
	speed					= 0xbf,
	beam_1x1_regen			= 0xc0,
	beam_2x1_regen			= 0xc1,
	beam_1x2_regen			= 0xc2,
	beam_2x2_regen			= 0xc3,
	beam_1x1				= 0xc4,
	beam_2x1				= 0xc5,
	beam_1x2				= 0xc6,
	beam_2x2				= 0xc7,
	--powerbomb_1x1_regen	= 0xc8,
	powerbomb_1x1			= 0xc9,
	supermissile_1x1_regen	= 0xca,
	supermissile_1x1		= 0xcb,
	beam_door				= 0xcf,
	grappling				= 0xe0,
	grappling_break_regen 	= 0xe1,
	grappling_break			= 0xe2,
	grappling2				= 0xe3,		-- \_ these two alternate in the roof of the room before the wave room
	grappling3				= 0xef,		-- /
	bombable_1x1_regen		= 0xf0,
	bombable_2x1_regen		= 0xf1,
	bombable_1x2_regen		= 0xf2,
	bombable_2x2_regen		= 0xf3,
	bombable_1x1			= 0xf4,
	bombable_2x1			= 0xf5,
	bombable_1x2			= 0xf6,
	bombable_2x2			= 0xf7,
}
RoomBlocks.extTileTypeNameForValue = setmetatable(table.map(RoomBlocks.extTileTypes, function(v,k) return k,v end), nil)

RoomBlocks.oobType = RoomBlocks.tileTypes.solid -- consider the outside to be solid

function RoomBlocks:getBlocks12()
	return self.data + 2
end
function RoomBlocks:getBlocks3()
	return self.data + 2 + self.offsetToCh3
end
function RoomBlocks:getLayer2Blocks()
	if self.hasLayer2Blocks then
		return self.data + 2 + self.offsetToCh3 / 2 * 3
	end
end

function RoomBlocks:getTileData(x,y)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = x + self.width * y
	local ch1 = self:getBlocks12()[0 + 2 * bi]
	local ch2 = self:getBlocks12()[1 + 2 * bi]
	local ch3 = self:getBlocks3()[bi]
	return ch1, ch2, ch3
end

function RoomBlocks:setTileData(x,y,ch1,ch2,ch3)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = x + self.width * y
	self:getBlocks12()[0 + 2 * bi] = ch1
	self:getBlocks12()[1 + 2 * bi] = ch2
	self:getBlocks3()[bi] = ch3
end


-- for position x,y, returns the real x,y that the tile type is determined by
function RoomBlocks:getCopySource(x,y)
	while true do
		if x < 0 or x >= self.width
		or y < 0 or y >= self.height
		then 
			return x,y
		end
	
		local ch1, ch2, ch3 = self:getTileData(x,y)
		local ch2hi = bit.band(0xf, bit.rshift(ch2, 4))
		-- TODO the next channel states how far to copy
		-- so we really have to scan the whole map (up front)
		-- and then make a list keyed by the copy-source position, listing all blocks which do copy that copy-source position
		if ch2hi == self.tileTypes.copy_up then
			y = y - 1
		elseif ch2hi == self.tileTypes.copy_left then
			x = x - 1
		else
			return x,y
		end
	end
	error'here'
end

-- returns true if this is a 'is copy up / left' tile
function RoomBlocks:isCopy(x,y)
	-- don't use getTileType because this uses the copy_*
	local _, ch2 = self:getTileData(x,y)
	local ch2hi = bit.band(0xf, bit.rshift(ch2, 4))
	return ch2hi == self.tileTypes.copy_left 
		or ch2hi == self.tileTypes.copy_up
end

-- returns true if this is targetted by a 'copy up / left' tile
function RoomBlocks:isCopied(x,y)
	local copiedRight = false
	local copiedUp = false
	if x < self.width-1 then
		local _, ch2R = self:getTileData(x+1,y)
		local ch2Rhi = bit.band(0xf, bit.rshift(ch2R, 4))
		copiedRight = ch2Rhi == self.tileTypes.copy_left
	end
	if y < self.height-1 then
		local _, ch2U = self:getTileData(x,y+1)
		local ch2Uhi = bit.band(0xf, bit.rshift(ch2U, 4))
		copiedUp = ch2Uhi == self.tileTypes.copy_up
	end
	return copiedRight and copiedUp, copiedRight, copiedUp
end

-- run this from a copied tile
-- returns a quick span right then a quick span down of all copies 
function RoomBlocks:getAllCopyLocs(x,y)
	local locs = table{x,y}
	local checked = table{x,y}
	while #checked > 0 do
		local ch = checked:remove()
		local _, ch2R = self:getTileData(x+1,y)
error'finish me - but you might have to redo all copies'
	end
end

-- if a block is a copy or is copied then replace it and all copies with its copy source
function RoomBlocks:splitCopies(x,y)
print'finish me plz'
do return end
	if self:isCopy(x,y) or self:isCopied(x,y) then
		local sx,sy = self:getCopySource(x,y)
		local _, ett = self:getTileType(sx,sy)
		for _,pos in ipairs(self:getAllCopyLocs(sx,sy)) do
			self:setTileType(pos[1], pos[2], ett)
		end
	end
end



--[[
returns the tile type (ch2 hi) and the extended tile type (ch2 hi:ch3 lo)
considers copies
--]]
function RoomBlocks:getTileType(x,y)
	x,y = self:getCopySource(x,y)
	if x < 0 or x >= self.width
	or y < 0 or y >= self.height
	then 
		return self.oobType
	end
	assert(not self:isCopy(x,y))
	local ch1, ch2, ch3 = self:getTileData(x,y)
	local ch2hi = bit.band(0xf0, ch2)
	local ch3lo = bit.band(0x0f, ch3)
	local ett = bit.bor(ch3lo, ch2hi)
	return bit.rshift(ch2hi, 4), ett
end

function RoomBlocks:getExtTileType(x,y)
	return select(2, self:getTileType(x,y))
end

-- set the 'ett' 
function RoomBlocks:setExtTileType(x,y,ett)
	assert(x >= 0 and x < self.width)
	assert(y >= 0 and y < self.height)
	local bi = x + self.width * y
	local b = self:getBlocks12()[1 + 2 * bi]
	local c = self:getBlocks3()[bi]

	-- TODO if it is a copy tile then break whatever it is copying from
	local ch3lo = bit.band(0x0f, ett)
	local ch2hi = bit.band(0xf0, ett)
--print('setting '..x..', '..y..' ett '..('%x (%x, %x)'):format(ett, bit.rshift(ch2hi, 4), ch3lo))
	local a,b,c = self:getTileData(x,y)
--print(' data was '..('%02x %02x %02x'):format(a,b,c))	
	b = bit.bor(bit.band(b, 0x0f), ch2hi)
	c = bit.bor(bit.band(c, 0xf0), ch3lo)
--print(' data now '..('%02x %02x %02x'):format(a,b,c))	

	self:getBlocks12()[1 + 2 * bi] = b
	self:getBlocks3()[bi] = c
end

-- notice this asks 'is is the 'solid' type?'
-- it does not ask 'is it a solid collidable block?'
function RoomBlocks:isSolid(x,y) 
	return self:getTileType(x,y) == self.tileTypes.solid
end

function RoomBlocks:isAccessible(x,y) 
	local tt, ett = self:getTileType(x,y)
	return tt == self.tileTypes.empty 
		or tt == self.tileTypes.crumble_or_speed
		or tt == self.tileTypes.breakable
		or ett == self.extTileTypes.grappling_break
		or ett == self.extTileTypes.grappling_break_regen
		or tt == self.tileTypes.bombable
end

--[[
TODO there's a small # of borders inaccessible
how to determine them?
1) flood fill per-room, starting at all doors
2) just manually excise them
they are:
landing room, left side of the room
first missile ever, under the floor
vertical of just about all the lifts in the game
top left of maridia's big room in the top left of the map
the next room over, the crab room, has lots of internal borders
the next room over from that, the hermit crab room, has lots of internal borders
the speed room before the mocktroids has a few internal borders
--]]
function RoomBlocks:isBorder(x,y, incl, excl)
	incl = incl or self.isSolid
	excl = excl or self.isAccessible
	
	--if x == 0 or y == 0 or x == self.width-1 or y == self.height-1 then return false end
	if incl(self,x,y) then
		for i,offset in ipairs{
			{1,0},
			{-1,0},
			{0,1},
			{0,-1},
		} do
			if excl(self,x+offset[1], y+offset[2]) then 
				return true
			end
		end
	end
	return false
end

function RoomBlocks:isBorderAndNotCopy(x,y)
	return self:isBorder(x,y) 
		and not self:isCopy(x,y) 
		and not self:isCopied(x,y)
end

return RoomBlocks
