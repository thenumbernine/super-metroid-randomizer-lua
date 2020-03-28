local ffi = require 'ffi'
local config = require 'config'

local rom = sm.rom
	
-- [[ remove all doors, just leave exits
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
local oldNumDoors = 0
local oldDoors = table()	-- table of all door locations
for _,room in ipairs(sm.rooms) do
	local w,h = room.width, room.height
	for _,door in ipairs(room.doors) do
		-- the doors that point to this door probably also need a flag set for 'don't spawn a door'
		-- lets see, the door going to the tube to the right of the start ... is all zeros
		-- in contrast, the other doors, some have 04 set on the direction, others have 01 on capX, some have 06 on capY, some have 04 on screenX 
		-- [=[
		for _,rs in ipairs(room.roomStates) do
			local doorIsSpecial = false
			assert(rs.plmset)
			for i=#rs.plmset.plms,1,-1 do
				local plm = rs.plmset.plms[i]
				if plm.x == door.x and plm.y == door.y then
					local plmname = assert(plm:getName(), "expected door plm to have a valid name "..plm)
					assert(plmname:match'^door_')
					if plmname:match'^door_grey_' 
					or plmname:match'^door_eye_' 
					then
						doorIsSpecial = true
					else
						rs.plmset.plms:remove(i)
						oldNumDoors = oldNumDoors + 1 
					end
				end
			end
--			local m = rs.m
--			local _,door2 = m.doors:find(nil, function(door2) return door2.index == door.index+1 end) -- TODO change name
--			door2.ptr.direction = bit.band(door2.ptr.direction, 3)
			if not doorIsSpecial then
				oldDoors:insert{room=room, rs=rs, door=door}
			end
		end
		--]=]
		-- found and removed all non-grey non-eye door plms
		-- now to remove the tiles too
		--[=[	
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
		--]=]	
	end
end

-- remove all tourian and ceres doors
oldDoors = oldDoors:filter(function(od)
	return od.rs.m.obj.region < 5
end)

print('old # non-special non-blue doors: '..oldNumDoors)
print('old # non-special doors: '..#oldDoors)
-- re-add new doors
local newNumDoors = 0
local numDoorsToMake = config.numColoredDoors or oldNumDoors
for i=0,numDoorsToMake-1 do
	if #oldDoors == 0 then break end
	local j = math.random(#oldDoors)
	local od = oldDoors:remove(j)
	local room, rs, door = od.room, od.rs, od.door
	-- TODO make sure we only do this once per plmset?
	local color = math.random(3)	-- red, green, orange, rest are blue options
	do --if color <= 3 then	-- skip blue doors completely
		color = ({'red', 'green', 'orange'})[color]
		local dir = ({'right', 'left', 'down', 'up'})[door.dir+1]
		local plmname = 'door_'..color..'_'..dir
		local plm = sm.PLM{
			cmd = assert(sm.plmCmdValueForName[plmname], "failed to find plm cmd named "..plmname),
			x = door.x,
			y = door.y,
			args = 0,
		}
		rs.plmset.plms:insert(plm)
		newNumDoors = newNumDoors + 1
		
		local region = rs.m.obj.region
		local index = rs.m.obj.index
		print('making new '..color..' door at '..door.x..', '..door.y..' region/room: '..('%02x/%02x'):format(region, index))
	end
end
print('new # non-special doors: '..newNumDoors)
if newNumDoors > oldNumDoors then
	print"!!! WARNING !!! you are making more new doors than old.  The door opened flags might overflow."
end
--]]
