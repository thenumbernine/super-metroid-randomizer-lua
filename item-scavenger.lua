local ffi = require 'ffi'
local config = require 'config'

local rom = sm.rom

local dirs = table{{1,0},{0,1},{-1,0},{0,-1}}

-- *) make sure the player has bombs or springball first.  I'm manually adding them at the bottom of this file.
-- *) don't do this below the waterline if the player doesn't have gravity.  otherwise they still might be impossible to reach ... unless you take special care, i.e. only burrow up/down, no further than jump height, etc.
local function burrowIntoWall(pos, breakType)
	if not config.randomizeItemsScavengerHuntProps.burrowItems then return pos end

	local x,y,room = table.unpack(pos)
	
	local plmpos
	local startx, starty = x, y

	local function posstr(x,y) return '['..x..', '..y..']' end	

	-- keep track of the screen pos's that we touch
	-- then for the PLM, set all the secret screens to the new scroll data 
	local touchedSIs = table()
	local function touchScreen(x,y)
		local sx = math.floor(x/16)
		local sy = math.floor(y/16)
		touchedSIs[sx + room.width/16 * sy] = true
	end

	-- TODO pick your break type.  TODO base it on what items you have so far.
	breakType = breakType or pickRandom{
		room.extTileTypes.beam_1x1,
		room.extTileTypes.bombable_1x1,
		room.extTileTypes.powerbomb_1x1,
		room.extTileTypes.supermissile_1x1,
	}	
	local origBreakType = breakType
	room:splitCopies(x,y)
	room:setExtTileType(x,y,breakType)
	touchScreen(x,y)

	--local len = math.floor(math.sqrt(math.random(100*100)))
	local len = math.random(config.randomizeItemsScavengerHuntProps.burrowLength)
--print('boring break type '..room.extTileTypeNameForValue[breakType]..' len '..len..' into wall '..posstr(x,y))
	
	-- after the first one, set them to something easier ... empty maybe?
	-- or TODO make sure the player has room to stand up
	breakType = room.tileTypes.empty

	local burrowMethod = pickRandom{'worm', 'spider'}

	local all = table{{x,y}}
	local options = table{{x,y}}
	for i=1,len do
		if #options == 0 then break end
--print('searching '..posstr(x,y))		
		local x,y
		if burrowMethod == 'worm' then
			-- does one long path:
			x,y = table.unpack(options:remove(math.random(#options)))
		elseif burrowMethod == 'spider' then
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
					-- ok right here, we are placing a new block
					-- if it is the first block that is not the start position 
					-- then we want to insert here a PLM b703
					-- actually ... why can't we do it on the first block anyways?  will that ruin the shootable block type?
					-- I'll try doing that first
					if x == startx and y == starty 
					and not plmpos
					then
						assert(not (nx == x and ny == y))
						plmpos = {nx, ny}
					end

					x,y = nx,ny
					-- don't clear the entrance
					if room:getExtTileType(x,y) ~= origBreakType then
						room:setExtTileType(x,y,breakType)
					end
					touchScreen(x,y)
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
	return newpos, touchedSIs:keys(), plmpos
end

-- [[ remove all previous items from the game
local removedItemCmds = table()
for _,plmset in ipairs(sm.plmsets) do
	for i=#plmset.plms,1,-1 do
		local name = plmset.plms[i]:getName()
		if name 
		and name:match'^item_' 
		and not name:match'^item_morph'	-- don't remove morph ball... or else
		and not (
			-- if we are burrowing items then don't burrow bombs
			config.randomizeItemsScavengerHuntProps.burrowItems  
			and name:match'^item_bomb'	-- hmm, now that we have this burrowing items ...  
		) then
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
	if m.obj.region == 6 then return false end

	-- remove tourian?
	if m.obj.region == 5 then return false end

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
			-- TODO CHECK PLMS.  THOSE FACES IN BLUE BRINSTAR WILL SPAWN OVER ITEMS.
				allLocs:insert{x,y,room}
				locsPerRoom[room.addr]:insert{x,y,room}
			end
		end
	end
end

local function placeInPLMSet(args)	--m, plmset, pos, cmd, args)	-- m is only for debug printing
	local m = args.mdb
	local plmset = args.plmset
	local pos = args.pos
	local cmd = args.cmd
	local plmarg = args.args or 0
	local x,y = table.unpack(pos)	
	local plm = sm.PLM{
		cmd = cmd,
		x = x,
		y = y,
		args = plmarg,
		scrollmod = args.scrollmod
	}
	print('placing in room '
		..('%02x/%02x'):format(m.obj.region, m.obj.index)
		..' plm '..plm)
	plmset.plms:insert(plm)
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
local firstMissileMDBs = table{
	sm:mapFindMDB(1, 0x0f),
	sm:mapFindMDB(1, 0x18),
}

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
--	pos = burrowIntoWall(pos, room.extTileTypes.beam_1x1)
	local m = pickRandom(room.mdbs:filter(function(m) 
		return firstMissileMDBs:find(m)
	end))
	for _,plmset in ipairs(getAllMDBPLMs(m)) do
		placeInPLMSet{mdb=m, plmset=plmset, pos=pos, cmd=sm.plmCmdValueForName.item_missile}
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
		if config.randomizeItemsScavengerHuntProps.hideItems then
			name = name .. '_hidden'
		end
		local cmd = assert(sm.plmCmdValueForName[name], "failed to find "..tostring(name))

		local enterpos = pickRandom(allLocs)
		local room = enterpos[3]
		local itempos, touchedSIs, plmpos = burrowIntoWall(enterpos)	-- now burrow a hole in the room and place the item at the end of it
		local scrollmodData 
		if #touchedSIs > 0 then
			scrollmodData = table()
			for _,si in ipairs(touchedSIs) do
				scrollmodData:insert(si)
				scrollmodData:insert(2)
			end
			scrollmodData:insert(0x80)
		end
		local m = pickRandom(room.mdbs:filter(function(m)
			return allMDBSet[m]
		end))
		for _,plmset in ipairs(getAllMDBPLMs(m)) do
			placeInPLMSet{mdb=m, plmset=plmset, pos=itempos, cmd=cmd}
			-- if the item was burrowed at all into the wall 
			if not (enterpos[1]==itempos[1] and enterpos[2]==itempos[2]) 
			-- and if there are any screens we want to change the scrollmod of
			and scrollmodData 
			then
				assert(plmpos)
				
				-- just add the scroll plm anyways.  we'll squeeze in the new scrollmod data somewhere
				placeInPLMSet{
					mdb = m, 
					plmset = plmset, 
					pos = plmpos, 
					cmd = sm.plmCmdValueForName.scrollmod, 	-- 'Normal Scroll PLM (DONE)'
					scrollmod = scrollmodData,
				}
			end
			-- ah but now you also have to add to the plm scrollmod list of the mdb ...
		end
	end
end
--]]

-- [[ debugging: put bombs by morph

do
	local m = sm:mapFindMDB(1, 0x0e)
	for _,plmset in ipairs(getAllMDBPLMs(m)) do
		placeInPLMSet{mdb=m, plmset=plmset, pos={64-1, 48-4}, cmd=sm.plmCmdValueForName.item_bomb_hidden}
		placeInPLMSet{mdb=m, plmset=plmset, pos={64-2, 48-4}, cmd=sm.plmCmdValueForName.item_xray_hidden}
	end
end
--]]
