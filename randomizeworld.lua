--[=[ first, zero everything

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

local room = sm:mapNewRoom{sm=self}
--]=]

-- instead how about just add add some random rooms to random places ... for now

for _,region in ipairs(sm.regions) do
	--[[
	TODO store region map info
	also store rooms per [x][y]
	hmm, go by the overhead map?
	or go by the region tilemap as well?
	
	but the problem is, the room is defined 
	--]]
end
