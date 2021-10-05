local table = require 'ext.table'
local ffi = require 'ffi'

--[=[
sm.rooms = table()
sm.roomblocks = table()

--[[ eh maybe keep these
sm.bgs = table()
sm.bgTilemaps = table()
--]]

sm.fx1sets = table()
sm.doors = table()
sm.plmsets = table()
sm.enemySpawnSets = table()
sm.enemyGFXSets = table()

--[[ keep
sm.tileSets = table()
sm.tileSetPalettes = table()
sm.tileSetGrahpicsTileSets = table()
sm.tileSetTilemaps = table()
--]]
--]=]


-- not sure about this routine just yet...
--local room = sm:mapNewRoom{sm=self}

-- instead how about just replacing the first room
local newroom
do
	newroom = sm:mapNewRoom{
		region = 0,	-- crateria
		
		x = 17,	-- region.width/2
		y = 3,	-- region.height/2
		width = 1,
		height = 1,
	}
	print('added new index '..('%02x'):format(newroom:obj().index))
	local rs = newroom.roomStates[1]

	-- I'm not rearranging bg's yet
	-- how do I get the BG to work?
	local rs00c = sm:mapFindRoom(0, 0x0c).roomStates[1]
	-- assign this here since i'm not re-encoding bgs yet
	rs:obj().bgPageOffset = rs00c:obj().bgPageOffset
	for _,bg in ipairs(rs00c.bgs) do
		bg.roomStates:insert(rs)
		rs.bgs:insert(bg)
	end
	rs:obj().layer2scrollXY = rs00c:obj().layer2scrollXY 
	rs:obj().musicControl = rs00c:obj().musicControl
	rs:setFX1Set(rs00c.fx1set)

	local roomBlockData = rs.roomBlockData
	-- TODO make a wholly new roomBlockData for this
	-- in fact make a wholly new Room for it tooo
	local ch12 = ffi.cast('uint16_t*', roomBlockData:getBlocks12())
	local ch3 = roomBlockData:getBlocks3()
	-- TODO build getLayer2Blocks() if it's not there
	for x=0,15 do
		for y=0,15 do
			-- lower 3 nibbles are the tilemap index 
			-- highest nibble is the tile type
			local index = x + 16 * y
			if x <= 0 or x >= 15
			or y <= 2 or y >= 13
			then
				ch12[index] = 0x805f	-- 8 = solid, 5f = tile
				ch3[index] = 0
			else
				ch12[index] = 0xff	-- empty
				ch3[index] = 0
			end
		end
	end
end
-- TODO insert a lift / entry point for loadStation / game starting point

-- testing -- attach an entry to room 0 for now ...
do
	local room000 = assert(sm:mapFindRoom(0, 0))
	local door = sm:mapAddDoor()
	door.srcRooms:insert(room000)
	door:obj().direction = door.directions.down
	door:obj().capX = 6						-- block 6?
	door:obj().capY = 2						-- ?
	-- screenX and screenY are target screens?
	door:obj().distToSpawnSamus = 0x8000	-- seems its always this
	assert(door:setDestRoom(newroom))
	local doorIndex = #room000.doors	-- 0-based index
	room000.doors:insert(door)
	local roomBlockDatas = table()
	for _,rs in ipairs(room000.roomStates) do
		roomBlockDatas:insertUnique(rs.roomBlockData)
	end
	for _,roomBlockData in ipairs(roomBlockDatas) do
		local ch12 = ffi.cast('uint16_t*', roomBlockData:getBlocks12())
		local ch3 = roomBlockData:getBlocks3()
		-- make an exit downward to our new room
		-- from mapblock {0,2} downward
		local rx = 0	-- map block coordinate
		local ry = 2
		for j=11,15 do
			for i=6,9 do
				local x = i + 16 * rx
				local y = j + 16 * ry
				local index = x + roomBlockData.width * y
				ch12[index] = 0x0132		-- empty w/ background
				ch3[index] = 0
				if j == 15 then
					ch12[index] = bit.bor(bit.band(ch12[index], 0x0fff), 0x9000)	-- add flag for door
					ch3[index] = doorIndex
				end
			end
		end
		-- TODO at the bottom, have a door block that transitions into our new room
		roomBlockData:refreshDoors()
	end
end


for _,region in ipairs(sm.regions) do
	--[[
	TODO store region map info
	also store rooms per [x][y]
	hmm, go by the overhead map?
	or go by the region tilemap as well?
	
	but the problem is, the room is defined 
	--]]
end
