--[[
Randomizing rooms, in conjunction with randomizing items, gives us room for a completely new approach at randomization.

For example ... hidden items.  We don't have to put them where they used to be.  Now we can put them anywhere
by replacing the old block they were at with a solid block, and moving them to any other location on the map (which is accessible by the player ... flood fill from the door_t entrance locations to find this out? 

I could take it a step further and randomly bore holes into the ground to hide morph-dependent items.

I can use the xx9xyy tiles to determine exit destinations, to determine connectivity of rooms.
From there I'll have to insert subnodes within rooms, separated by blockades of arbitrary type (crumble, speed boost, etc).
And from there I can use this graph to determine enter/exit accessibility automatically (right now it is manually entered for each item).
Looks like hidden items can just be set over any solid block to replace it with an item.
Looks like chozo items likewise can be set in any empty tile to be a solid, shootable egg.



--]]

local ffi = require 'ffi'
local config = require 'config'

local rom = sm.rom

--[[
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
				local plmname = assert(plm:getName(), "expected door plm to have a valid name "..plm)
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
					local plm = sm.PLM()
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


--[[ do some modifications
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

--[[ make the first Ceres door go to Zebes
-- screws up graphics ... permanently ...
local _,startRoom = assert(sm.mdbs:find(nil, function(m) return m.obj.region == 0 and m.obj.index == 0 end))
local _,ceres = assert(sm.mdbs:find(nil, function(m) return m.obj.region == 6 and m.obj.index == 0 end))
local doorptr = ceres.doors[1].ptr
doorptr.dest_mdb = startRoom.addr
doorptr.screenX = 3
doorptr.screenY = 3
--]]


--[[ make the first room have every item in the game
local _,startRoom = assert(sm.mdbs:find(nil, function(m) return m.obj.region == 0 and m.obj.index == 0 end))
--start room's states 2,3,4 all have plm==0x8000, which is null, so give it a new one
local newPLMSet = sm:newPLMSet{
	-- make a PLM of each item in the game
	plms = sm.plmCmdValueForName:map(function(cmd,name,t)
		if name:match'^item_' 
		and not name:match'_hidden$'
		and not name:match'_chozo$'
		then
			local width = 7
			return sm.PLM{
				cmd = cmd,
				x = 42 + #t % width,
				y = 74 + math.floor(#t / width),
			}, #t+1
		end
	end),
}
startRoom.roomStates[2]:setPLMSet(newPLMSet)
startRoom.roomStates[3]:setPLMSet(newPLMSet)
startRoom.roomStates[4]:setPLMSet(newPLMSet)
--]] -- write will match up the addrs




--[[ remove all scrollmods and make constant all scrolldata
-- as soon as you walk into the old mother brain room, this causes the screen to permanently glitch where it draws things
-- remove all scrollmod plms
for _,plmset in ipairs(sm.plmsets) do
	for _,plm in ipairs(plms) do
		if plmset.plms[i].cmd == sm.plmCmdValueForName.scrollmod then
			plmset.plms:remove(i)
		end
	end
end
-- change all scroll values to 01
for _,m in ipairs(sm.mdbs) do
	for _,rs in ipairs(m.roomStates) do
		rs.obj.scroll = 1
	end
end
--]]
