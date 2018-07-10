local ffi = require 'ffi'

local rom = sm.rom

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

ch3:
01 = tile to the right too
02 = tile below too
04 = no respawn
05 = crumble
08 = super missile
09 = power bomb
0f = speed
--]=]
for _,room in ipairs(sm.rooms) do
	local w,h = room.width, room.height

	for j=0,h-1 do
		for i=0,w-1 do
			-- make sure we're not in any door regions, because those have to be shootable/whatever
			local door = room.doors:find(nil, function(door)
				return i >= door.x and i <= door.x + door.w
				and j >= door.y and j <= door.y + door.h
			end)
			if not door then
				local a = room.blocks[0 + 3 * (i + w * j)]
				local b = room.blocks[1 + 3 * (i + w * j)]
				local c = room.blocks[2 + 3 * (i + w * j)]
--I'm still missing the bomable block in the loewr red room brinstar
				-- notice that doors and platforms and IDs for doors and platforms can be just about anything
				if 
-- [=[
				false
				--or bit.band(b, 0xf0) == 0x10	-- slope?
				or bit.band(b, 0xf0) == 0x80	-- solid
				or bit.band(b, 0xf0) == 0xb0	-- crumble 
				or bit.band(b, 0xf0) == 0xc0	-- shootable / powerbombable / super missile / speed booster?
				or bit.band(b, 0xf0) == 0xf0	-- bombable
				
				or bit.band(b, 0xf0) == 0x50	-- repeat? 
				or bit.band(b, 0xf0) == 0xd0	-- repeat? 
--]=]
				--or (bit.band(b, 0x50) == 0x50 and c == 5)	-- fall through
				--or (c >= 4 and c <= 7) 
				--or c == 8 -- super missile
				--or c == 9 -- power bomb .. if high byte high nibble is c
				--or c == 0xf	-- speed block
				then
					--[=[ remove
					room.blocks[0 + 3 * (i + w * j)] = 0xff
					room.blocks[1 + 3 * (i + w * j)] = 0
					room.blocks[2 + 3 * (i + w * j)] = 0
					--]=]
					-- [=[ turn to destructable blocks
					--room.blocks[0 + 3 * (i + w * j)] = 0
					room.blocks[1 + 3 * (i + w * j)] = bit.bor(
						0xc0, 	-- shootable
						--0xf0,	-- bombable
						bit.band(b, 0x0f))
					-- ch3 4's bit means 'no respawn' ?
					room.blocks[2 + 3 * (i + w * j)] = 4
					--]=]
					
					--c = 0 -- means bombable/shootable, respawning
					--c = 4	-- means bombable/shootable, no respawning, or it means fallthrough block
					--c = 0xc
					
					-- btw, how come there are ch3==0 bombable blocks? (escaping alcatraz)
					--room.blocks[2 + 3 * (i + w * j)] = c
					
--					b = bit.bor(bit.band(b, 0x0f), 0xc0)
--					room.blocks[1 + 3 * (i + w * j)] = b
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
		-- the doors that point to this door probably also need a flag set for 'don't spawn a door'
		-- lets see, the door going to the tube to the right of the start ... is all zeros
		-- in contrast, the other doors, some have 04 set on the direction, others have 01 on capX, some have 06 on capY, some have 04 on screenX 
		-- [=[
		local doorIsSpecial = true
		for _,rs in ipairs(room.roomStates) do
			assert(rs.plmset)
			for i=#rs.plmset.plms,1,-1 do
				local plm = rs.plmset.plms[i]
				if plm.x == door.x and plm.y == door.y then
					local plmname = assert(sm.plmCmdNameForValue[plm.cmd], "expected door plm to have a valid name "..plm)
					assert(plmname:match'^door_')
					if plmname:match'^door_grey_' 
					or plmname:match'^door_eye_' 
					then
						doorIsSpecial = true
					else
						rs.plmset.plms:remove(i)
					end
				end
			end
--			local m = rs.m
--			local _,door2 = m.doors:find(nil, function(door2) return door2.index == door.index+1 end) -- TODO change name
--			door2.ptr.direction = bit.band(door2.ptr.direction, 3)
		end
		--]=]
		-- found and removed all non-grey non-eye door plms
		-- now to remove the tiles too
		if not doorIsSpecial then	
			local i,j = door.x, door.y
			for k=0,3 do
				if door.dir == 2 or door.dir == 3 then	-- left/right
					assert(i+k >= 0 and i+k < w, "oob door at "..tolua(door).." mdb "..room.roomStates[1].m.ptr[0])
					assert(j >= 0 and j < h)
					room.blocks[0 + 3 * ((i+k) + w * j)] = 0xff
					room.blocks[1 + 3 * ((i+k) + w * j)] = 0
					room.blocks[2 + 3 * ((i+k) + w * j)] = 0
				elseif door.dir == 0 or door.dir == 1 then	-- up/down
					assert(i >= 0 and i < w)
					assert(j+k >= 0 and j+k < h)
					room.blocks[0 + 3 * (i + w * (j+k))] = 0xff
					room.blocks[1 + 3 * (i + w * (j+k))] = 0
					room.blocks[2 + 3 * (i + w * (j+k))] = 0
				else
					error'here'
				end
			end
		end
	end
end
--]]

--[[ make the first Ceres door go to Zebes
-- screws up graphics ... permanently ...
local _,startRoom = assert(sm.mdbs:find(nil, function(m) return m.ptr.region == 0 and m.ptr.index == 0 end))
local _,ceres = assert(sm.mdbs:find(nil, function(m) return m.ptr.region == 6 and m.ptr.index == 0 end))
local doorptr = ceres.doors[1].ptr
doorptr.dest_mdb = startRoom.addr
doorptr.screenX = 3
doorptr.screenY = 3
--]]


-- [[ make the first room have every item in the game
local _,startRoom = assert(sm.mdbs:find(nil, function(m) return m.ptr.region == 0 and m.ptr.index == 0 end))
--start room's states 2,3,4 all have plm==0x8000, which is null, so give it a new one
local newPLMSet = sm:newPLMSet{
	-- make a PLM of each item in the game
	plms = sm.plmCmdValueForName:map(function(cmd,name,t)
		if name:match'^item_' 
		and not name:match'_hidden$'
		and not name:match'_chozo$'
		then
			local width = 7
			return ffi.new('plm_t', {
				cmd = cmd,
				x = 42 + #t % width,
				y = 74 + math.floor(#t / width),
			}), #t+1
		end
	end),
}
startRoom.roomStates[2]:setPLMSet(newPLMSet)
startRoom.roomStates[3]:setPLMSet(newPLMSet)
startRoom.roomStates[4]:setPLMSet(newPLMSet)
--]] -- write will match up the addrs

-- write back changes
sm:mapWrite()
