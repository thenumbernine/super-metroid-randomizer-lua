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

local function placeInRoom(m, rs, room, cmd)
	-- TODO !issolid doesn't mean isempty...
	local function tileType(x,y)
		local bi = 3 * (x + room.width * y)
		--local a = room.blocks[0 + bi]
		local b = room.blocks[1 + bi]
		--local c = room.blocks[2 + bi]
		return bit.band(0xf, bit.rshift(b, 4))
		-- TODO consider block type based on copy left / copy up
		-- TODO TODO don't pick blocks that are copied for replacing with items
		--or bit.band(b, 0xf0) == 0x50	-- copy left
		--or bit.band(b, 0xf0) == 0xd0	-- copy above
	end
	local function issolid(x,y) return tileType(x,y) == 8 end
	local function isempty(x,y) return tileType(x,y) == 0 end

	-- TODO pick a location that is solid and next to empty
	local x,y
	local offsetDir
	local found
	for tries=1,100 do
		x = math.random(2, room.width - 3)	-- avoid edges
		y = math.random(2, room.height - 3)
		if issolid(x,y) then
			for i,offset in ipairs{
				{1,0},
				{-1,0},
				{0,1},
				{0,-1},
			} do
				if isempty(x+offset[1], y+offset[2]) then 
					offsetDir = i
					found = true
					break 
				end
			end
			if found then break end
		end
	end
	if not found then
		print("ERROR - couldn't find placement for item "..sm.plmCmdNameForValue[cmd])
	end
		
	local name = sm.plmCmdNameForValue[cmd]
	print('placing in room '
		..('%02x/%02x'):format(m.ptr.region, m.ptr.index)
		..' at '..x..', '..y
		..' offset '..offsetDir
		..' item '..name)
	rs.plmset.plms:insert(
		ffi.new('plm_t', {
			cmd = cmd,
			x = x,
			y = y,
		})
	)
end

--[[
MAKE SURE TO PUT AT LEAST ONE MISSILE IN THE START (to wake up zebes)
rooms to put a missile tank in:
01/1e = morph room ... but there is a risk of it going past the power bomb walls
01/0f = next room over
01/18 = missile room
01/10 = next room ... but there is a risk of it going in the top
--]]
local firstMissileMDBs = sm.mdbs:filter(function(m)
	return m.ptr.region == 1
	and (
		m.ptr.index == 0xf
		or m.ptr.index == 0x18
	)
end)
do
	local m = pickRandom(firstMissileMDBs)
	for _,rs in ipairs(m.roomStates) do
		placeInRoom(m, rs, rs.room, sm.plmCmdValueForName.item_missile)
	end
end
-- TODO maybe make sure there's something to destroy bomb blocks ... maybe ...

-- [[ now re-add them in random locations ... making sure that they are accessible as you add them?
-- how to randomly place them...
for rep=1,1 do
	for _,cmd in ipairs(removedItemCmds) do
		-- reveal all items for now
		local name = sm.plmCmdNameForValue[cmd]
		name = name:gsub('_chozo', ''):gsub('_hidden', '')	
		local cmd = assert(sm.plmCmdValueForName[name], "failed to find "..tostring(name))
		
		local m = pickRandom(sm.mdbs)
		-- now which room state do we apply it to? first? all?
		for _,rs in ipairs(m.roomStates) do
			placeInRoom(m, rs, rs.room, cmd)
		end
	end
end
--]]

--[[ make sure morph ball is in the start room 
local _,startRoom = assert(sm.mdbs:find(nil, function(m) return m.ptr.region == 0 and m.ptr.index == 0 end))
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

