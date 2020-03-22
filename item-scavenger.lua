local ffi = require 'ffi'
local config = require 'config'

local rom = sm.rom

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
		
			-- TODO -- if the name was _chozo or _hidden then replace the block with a shootable block
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
		print('room '..('%06x'):format(room.addr)..' has locs:')
		for _,loc in ipairs(locsPerRoom[room.addr]) do
			print('', table.unpack(loc))
			poss:insert(loc)
		end
	end	
	local pos = pickRandom(poss)
	local x,y,room = table.unpack(pos)
	assert(room.mdbs, "found a room without any mdbs: "..(function()
		local s = ''
		for k,v in pairs(room) do
			s = s .. tostring(k) .. ' = ' .. tostring(v) .. '\n'
		end
		return s
	end)())
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
			name = name .. '_hidden'
		end
		local cmd = assert(sm.plmCmdValueForName[name], "failed to find "..tostring(name))

		local pos = pickRandom(allLocs)
		local x,y,room = table.unpack(pos)
		local m = pickRandom(room.mdbs:filter(function(m)
			return allMDBSet[m]
		end))

		for _,plmset in ipairs(getAllMDBPLMs(m)) do
			placeInPLMSet(plmset, pos, cmd, m)
		end
	end
end
--]]

--[[ make sure morph ball is in the start room 
local _,startRoom = assert(allMDBs:find(nil, function(m) return m.ptr.region == 0 and m.ptr.index == 0 end))
-- they al have the same plm set btw.... you only need to do this once
for _,rs in ipairs(startRoom.roomStates) do
	rs.plmset.plms:insert(
		ffi.new('plm_t', {
			cmd = sm.plmCmdValueForName.item_morph,
			x = 42,
			y = 74, 
		})
	)
end
--]]

