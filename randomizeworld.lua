local table = require 'ext.table'
local ffi = require 'ffi'

do return end

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

local doorForSide = {
	-- 4x3 door upwards
	up = {
		{0x009c63, 0x009c62, 0x009862, 0x009863},
		{0x000c43, 0x000c42, 0x000842, 0x000843},
		{0x43cc1d, 0xff5c1c, 0xfe581c, 0xfd581d},
	},

	-- 4x3 door downwards
	down = {
		{0x42c41d, 0xff541c, 0xfe501c, 0xfd501d},
		{0x000443, 0x000442, 0x000042, 0x000043},
		{0x009463, 0x009462, 0x009062, 0x009063},	-- <- put the door index in ch3 here
	},

	-- 2x4 door to the left
	left = {
		{0x009440, 0x41c40c},
		{0x009460, 0xffd42c},
		{0x009c60, 0xfedc2c},
		{0x009c40, 0xfddc0c},
	},

	-- 2x4 door to the right
	right = {
		{0x40c00c, 0x009040},
		{0xffd02c, 0x009060},
		{0xfed82c, 0x009860},
		{0xfdd80c, 0x009840},
	},
}

local function placeDoorBlocks(roomBlockData, ulx, uly, dir, doorIndex)
	local ch12 = ffi.cast('uint16_t*', roomBlockData:getBlocks12())
	local ch3 = roomBlockData:getBlocks3()
	local tiles = assert(doorForSide[dir])
	for j,row in ipairs(tiles) do
		for i,value in ipairs(row) do
			local x = ulx + i-1
			local y = uly + j-1
			local index = x + roomBlockData.width * y
			if x >= 0 and x < roomBlockData.width
			and y >= 0 and y < roomBlockData.height
			then
				ch12[index] = bit.band(0xffff, value)
				if bit.band(0xf, bit.rshift(value, 12)) == 9 then
					ch3[index] = doorIndex
				else
					ch3[index] = bit.band(0xff, bit.rshift(value, 16))
				end
			end
		end
	end
end

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
local room000 
do
	room000 = assert(sm:mapFindRoom(0, 0))
	local door = sm:mapAddDoor()
	door.srcRooms:insert(room000)
	door:obj().direction = door.directions.down
	door:obj().capX = 6						-- block 6?
	door:obj().capY = 2						-- ?
	door:obj().screenX = 0		-- screenX and screenY are target screens?
	door:obj().screenY = 0
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
			end
		end
		placeDoorBlocks(roomBlockData, 6 + 16 * rx, 13 + 16 * ry, 'down', doorIndex)
		-- TODO at the bottom, have a door block that transitions into our new room
		roomBlockData:refreshDoors()
	end
end
do
	local door = sm:mapAddDoor()
	door.srcRooms:insert(newroom)
	door:obj().direction = bit.bor(
		door.directions.up --, door.directions.closeBehind
	)
	-- TODO how to set this up so scrolling works on the other side
	door:obj().capX = 6
	door:obj().capY = 0xd
	door:obj().screenX = 0
	door:obj().screenY = 2
	door:obj().distToSpawnSamus = 0x8000	--0x01c0
	assert(door:setDestRoom(room000))
	local doorIndex = #newroom.doors
	newroom.doors:insert(door)
	placeDoorBlocks(newroom.roomStates[1].roomBlockData, 6, 0, 'up', doorIndex)
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
