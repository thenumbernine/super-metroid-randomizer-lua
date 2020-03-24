local ffi = require 'ffi'
local config = require 'config'

local rom = sm.rom

local dirs = table{{1,0},{0,1},{-1,0},{0,-1}}

-- TODO make sure the player has bombs or springball first
local function boreIntoWall(pos)
	local function posstr(x,y) return '['..x..', '..y..']' end	
	
	local x,y,room = table.unpack(pos)
	-- TODO pick your break type.  TODO base it on what items you have so far.
	local breakType = pickRandom{
		room.extTileTypes.beam_1x1,
		room.extTileTypes.bombable_1x1,
		room.extTileTypes.powerbomb_1x1,
		room.extTileTypes.supermissile_1x1,
	}	
	room:splitCopies(x,y)
	room:setExtTileType(x,y,breakType)
	
	--local len = math.floor(math.sqrt(math.random(100*100)))
	local len = math.random(100)
--print('boring break type '..room.extTileTypeNameForValue[breakType]..' len '..len..' into wall '..posstr(x,y))
	
	-- after the first one, set them to something easier ... empty maybe?
	-- or TODO make sure the player has room to stand up
	breakType = room.tileTypes.empty

	local method = pickRandom{'worm', 'spider'}

	local all = table{{x,y}}
	local options = table{{x,y}}
	for i=1,len do
		if #options == 0 then break end
--print('searching '..posstr(x,y))		
		local x,y
		if method == 'worm' then
			-- does one long path:
			x,y = table.unpack(options:remove(math.random(#options)))
		elseif method == 'spider' then
			-- does fractures of paths
			x,y = table.unpack(pickRandom(options))
		end
		local found
		for _,dir in ipairs(dirs:shuffle()) do
			local nx, ny = x + dir[1], y + dir[2]
--print('examining '..posstr(nx,ny))		
			-- don't include the border
			if nx >= 1 and nx < room.width-1 
			and ny >= 1 and ny < room.height-1
			then
				-- if the new place is blocked on 3 out of 4 sides then it is good
				local solidSides = 0
				for _,odir in ipairs(dirs) do
					if room:isSolid(nx+odir[1], ny+odir[2]) then 
						solidSides = solidSides + 1 
					end
				end
				assert(solidSides < 4)	-- shouldn't have 4 if we just came from a 1
				if solidSides == 3 then
					x,y = nx,ny
					room:setExtTileType(x,y,breakType)
					all:insert{x,y}
					options:insert{x,y}
					found=true
--print('boring in wall '..posstr(x,y))
					break
				end
			end
		end
		if not found then
--print('...exhausted all dirs')		
		end
	end

	local newpos = all:last()
	newpos[3] = room
	return newpos
end

-- [[ remove all previous items from the game
local removedItemCmds = table()
for _,plmset in ipairs(sm.plmsets) do
	for i=#plmset.plms,1,-1 do
		local name = sm.plmCmdNameForValue[plmset.plms[i].cmd]
		if name 
		and name:match'^item_' 
		and name ~= 'item_morph'	-- don't remove morph ball... or else
		then
			plmset.plms:remove(i)
	
			local base,suffix = name:match'(.*)_chozo$'
			if suffix then name = base end
			
			local base,suffix = name:match'(.*)_hidden$'
			if suffix then name = base end
	
			-- collect all base names
			removedItemCmds:insert(sm.plmCmdValueForName[name])
		end
	end
end
--]]


-- remove the debug mdbs
local allMDBs = sm.mdbs:filter(function(m)
	-- remove crateria?
	if m.ptr.region == 6 then return false end

	-- remove tourian?
	if m.ptr.region == 5 then return false end

	-- TODO remove intro room?  or at least remove their plmsets until after you wake zebes?
	-- TODO also remove escape plmsets
	-- TODO also remove plmsets from pre-wake wrecked ship

	return true
end)
-- TODO use m.ptr instead?
local allMDBSet = allMDBs:mapi(function(m) return true, m end)

local function getRoomsForMDBs(mdbs)
	local rooms = table()
	for _,m in ipairs(mdbs) do
		for i,rs in ipairs(m.roomStates) do
			assert(rs.room)
			rooms[rs.room.addr] = rs.room
		end
	end
	return rooms:values()
end

local allRooms = getRoomsForMDBs(allMDBs)

local allLocs = table()
local locsPerRoom = table()
for _,room in ipairs(allRooms) do
	locsPerRoom[room.addr] = table()
	for y=0,room.height-1 do
		for x=0,room.width-1 do
			if room:isBorderAndNotCopy(x,y) then
				allLocs:insert{x,y,room}
				locsPerRoom[room.addr]:insert{x,y,room}
			end
		end
	end
end

local function placeInPLMSet(plmset, pos, cmd, m)	-- m is only for debug printing
	local x,y = table.unpack(pos)	
	local name = sm.plmCmdNameForValue[cmd]
	local roomid = ('%02x/%02x'):format(m.ptr.region, m.ptr.index)
		
	print('placing in room '
		..roomid
		..' at '..x..', '..y
		..' item '..name)
	plmset.plms:insert(
		ffi.new('plm_t', {
			cmd = cmd,
			x = x,
			y = y,
		})
	)
end

local function getAllMDBPLMs(m)
	local plmsets = table()
	for _,rs in ipairs(m.roomStates) do
		plmsets[rs.plmset] = true
	end
	plmsets = plmsets:keys()
	return plmsets
end

--[[
MAKE SURE TO PUT AT LEAST ONE MISSILE IN THE START (to wake up zebes)
rooms to put a missile tank in:
01/1e = morph room ... but there is a risk of it going past the power bomb walls
01/0f = next room over
01/18 = missile room
01/10 = next room ... but there is a risk of it going in the top
--]]
local firstMissileMDBs = allMDBs:filter(function(m)
	return m.ptr.region == 1
	and (
		m.ptr.index == 0xf
		or m.ptr.index == 0x18
	)
end)

do
	local rooms = getRoomsForMDBs(firstMissileMDBs)
--	local poss = table():append(rooms:mapi(function(room) 
--		return assert(locsPerRoom[room.addr], "failed to find locs for room "..('%06x'):format(room.addr))
--	end):unpack())
	local poss = table()
	for _,room in ipairs(rooms) do
--print('room '..('%06x'):format(room.addr)..' has locs:')
		for _,loc in ipairs(locsPerRoom[room.addr]) do
--print('', table.unpack(loc))
			poss:insert(loc)
		end
	end	
	local pos = pickRandom(poss)
	local room = pos[3]
	assert(room.mdbs, "found a room without any mdbs")
	pos = boreIntoWall(pos)	-- now bore a hole in the room and place the item at the end of it
	local m = pickRandom(room.mdbs:filter(function(m) 
		return firstMissileMDBs:find(m)
	end))
	for _,plmset in ipairs(getAllMDBPLMs(m)) do
		placeInPLMSet(plmset, pos, sm.plmCmdValueForName.item_missile, m)
	end
	-- TODO and remove the location from the list of being picked again?
end
-- TODO maybe make sure you get early something to destroy bomb blocks ... maybe ...


-- [[ now re-add them in random locations ... making sure that they are accessible as you add them?
-- how to randomly place them...
for rep=1,1 do
	for _,cmd in ipairs(removedItemCmds) do
		-- reveal all items for now
		local name = sm.plmCmdNameForValue[cmd]
		name = name:gsub('_chozo', ''):gsub('_hidden', '')	
		if config.randomizeItemsScavengerHuntHidden then
			name = name .. '_chozo'
		end
		local cmd = assert(sm.plmCmdValueForName[name], "failed to find "..tostring(name))

		local pos = pickRandom(allLocs)
		local room = pos[3]
		pos = boreIntoWall(pos)	-- now bore a hole in the room and place the item at the end of it
		local m = pickRandom(room.mdbs:filter(function(m)
			return allMDBSet[m]
		end))
		for _,plmset in ipairs(getAllMDBPLMs(m)) do
			placeInPLMSet(plmset, pos, cmd, m)
		end
	end
end
--]]
