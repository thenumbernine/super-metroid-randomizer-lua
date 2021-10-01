local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local math = require 'ext.math'
local config = require 'config'
local Blob = require 'blob'

local pc = require 'pc'
local topc = pc.to
local frompc = pc.from


--[[
bitflags coinciding with neighbors:
  2 
1   0
  3
--]]
local mapGfxTiles = {
	empty 	= 0x001f,	-- there are a few empty's, but this is the one that was initially used.  maybe ti coincidees with the transparent overlay since the map is placed over the pause screen background.
	[0x00]	= 0x001b,	-- 0000 no walls
	[0x01]	= 0x0027,	-- 0001 right
	[0x02]	= 0x4027,	-- 0010 left
	[0x03]	= 0x0023,	-- 0011 left & right
	[0x04]	= 0x0026,	-- 0100 top
	[0x05]	= 0x4025,	-- 0101 top & right
	[0x06]	= 0x0025,	-- 0110 top & left
	[0x07]	= 0x0024,	-- 0111 top left right
	[0x08]	= 0x8026,	-- 1000 bottom
	[0x09]	= 0xc025,	-- 1001 bottom right
	[0x0a]	= 0x8025,	-- 1010 bottom left
	[0x0b]	= 0x8024,	-- 1011 bottom left right
	[0x0c]	= 0x0022,	-- 1100 bottom top
	[0x0d]	= 0x4021,	-- 1101 bottom top right
	[0x0e]	= 0x0021,	-- 1110 bottom top left
	[0x0f]	= 0x0020,	-- 1111 bottom top left right
	lift_7	= 0x004f,	-- 0111 top left right
	lift_8	= 0x005f,	-- 1000 bottom 
	lift_d	= 0x0010,	-- 1101 bottom top right
--	use an empty tile: 88, 98, 9e, 9f, ae, af, cc, cd are available  
	item_0	= 0x0088,	-- 0000 no walls -- NOTICE THIS ISN'T HERE TO BEGIN WITH - so you have to add it to th epause screen tiles in an empt location.
	item_1	= 0x4077,	-- 0001 right
	item_2	= 0x0077,	-- 0010 left
	item_3	= 0x0098,	-- 0011	left right - NOTICE THIS ISN'T HERE TO BEGIN WITH
	item_4	= 0x0076,	-- 0100 top
	item_5	= 0x408e,	-- 0101 top right
	item_6	= 0x008e,	-- 0110 top left
	item_7	= 0x006e,	-- 0111 bottom left right
	item_8	= 0x8076,	-- 1000 bottom
	item_9	= 0xc08e,	-- 1001 bottom right
	item_a	= 0x808e,	-- 1010 bottom left
	item_b	= 0x806e,	-- 1011 top left right
	item_c	= 0x005e,	-- 1100 bottom top
	item_d	= 0x408f,	-- 1101 bottom top right
	item_e	= 0x008f,	-- 1110 bottom top left
	item_f	= 0x006f,	-- 1111 bottom top left right
	tubehorz = 0x006d,
	tubevert = 0x00ce,
	save 	= 0x004d,
	downarrow = 0x0011,
	save_station = 0x004d,	-- or 0x028d
	
	--[[ I don't think these work on the map pause screen ...
	map_station = 0x028e,
	energy_refill_station = 0x028c,
	missile_refill_station = 0x028b,
	boss = 0x028a,
	ship_left = 0x028f,	-- flip horz for ship_right ... but no need, the ship seems to be overlayd
	--]]
	-- [[ do the 0x01xx block work? ... I'm having trouble with anything here ...
	map_station = 0x003c,	-- letter 'M'
	energy_refill_station = 0x0034,	-- letter 'E'
	missile_refill_station = 0x0041,	-- letter 'R'
	boss = 0x0031,
	--]]
}


local Region = class()

-- all overworld maps are 64 x 32
Region.width = 64
Region.height = 32

function Region:init(args)
	self.index = assert(args.index)	-- 0-based
	self.rooms = table()
	-- 1-based:
	self.roomsForTiles = {}	--range(self.width * self.height):mapi(function() return table() end)
end


local RegionTilemap = class(Blob)
RegionTilemap.count = Region.width * Region.height
RegionTilemap.type = 'tilemapElem_t'


local SMRegions = {}

SMRegions.maxRegions = 8

function SMRegions:regionsInit()
	-- pointers to the region tilemaps are in code here:
	-- this maps from region# to region tilemap address
	-- patrickjohnston says "region 7 uses region 0" but I haven't played the debug region yet
	self.regionTilemapAddr24s = Blob{sm=self, addr=topc(0x82, 0x964a), count=7, type='addr24_t'}

	--[[
	Lua table is 1-based
	
tilemap pointers when using fixed offsets
loading region 0 map from 1a8000 b5:8000
loading region 1 map from 1a9000 b5:9000
loading region 2 map from 1aa000 b5:a000
loading region 3 map from 1ab000 b5:b000
loading region 4 map from 1ac000 b5:c000
loading region 5 map from 1ad000 b5:d000
loading region 6 map from 1ae000 b5:e000
loading region 7 map from 1af000 b5:f000

tilemap pointers when using table offset
loading region 0 map from 1a9000 b5:9000
loading region 1 map from 1a8000 b5:8000
loading region 2 map from 1aa000 b5:a000
loading region 3 map from 1ab000 b5:b000
loading region 4 map from 1ac000 b5:c000
loading region 5 map from 1ad000 b5:d000
loading region 6 map from 1ae000 b5:e000
loading region 7 map from 1a9000 b5:9000

	--]]
	self.regions = range(0,self.maxRegions-1):mapi(function(index)
		local region = Region{index=index}
		

		-- region bottom half 32x32 is moved to the right of the top half
		--local addr = topc(0xb5, 0x8000 + 0x1000 * index)
		
		-- space is there for the tilemap region 7, but the pointer table doesn't reach it.
		-- somewhere in comments it says that region 7 just uses region 0's map
		local addr = index == 7 
			and topc(0xb5, 0xf000)
			or self.regionTilemapAddr24s.v[index % self.regionTilemapAddr24s.count]:topc()
		
		--print('loading region '..index..' map from '..('%06x'):format(addr)..' '..('%02x:%04x'):format(frompc(addr)))
		region.tilemap = RegionTilemap{
			sm = self,
			addr = addr,
		}
		return region
	end)
end

--[[
gets the index into the tilemap for the x,y in map blocks
the tilemap stores the left 32x32 first, then the right 32x32 next
both are stored in row-major order
--]]
local function regionTilemapIndex(x,y)
	assert(x >= 0 and x < 64)
	assert(y >= 0 and y < 31)	-- looks like y+1 means that the top row isn't used?
	-- why is the y shifted down one?
	return bit.band(x, 0x1f) + 32 * (y+1 + 32 * bit.rshift(x, 5))
end


local vec2i = require 'vec-ffi.vec2i'

--[[
build associations between regions and rooms
TODO should I do this in mapInit as the rooms are built?
--]]
function SMRegions:regionsBindRooms()
	local function roomsAtXY(region, x, y, write)
		local index = 1 + x + region.width * y
		local t = region.roomsForTiles[index]
		if write then
			if not t then
				t = table()
				region.roomsForTiles[index] = t
			end
		else
			if t and #t == 0 then
				region.roomsForTiles[index] = nil
			end
		end
		return t
	end

	-- determine rooms at each block in the region's world map
	for _,room in ipairs(self.rooms) do
		local regionIndex = room:obj().region
		local region = select(2, self.regions:find(nil, function(region) return region.index == regionIndex end))
		if not region then
			error("couldn't find region "..regionIndex)
		end
		room.regionMapBlockPos = table()
		region.rooms:insert(room)
		for j=0,room:obj().height-1 do
			for i=0,room:obj().width-1 do
				local x = room:obj().x + i
				local y = room:obj().y + j
				assert(x >= 0 and x < region.width)
				assert(y >= 0 and y < region.height)

				-- insert in all mapblocks, or only those that are accessible, or only those also on the overworld?
				-- seems to e too exclusive:
				--[[
				local tilemap = assert(region.tilemap)
				local tilemapIndex = ffi.cast('uint16_t*', tilemap.v)[regionTilemapIndex(x,y)]
				if bit.band(0x3ff, tilemapIndex) ~= 0x01f then
				--]]
				-- [[
				do
				--]]
					roomsAtXY(region, x, y, true):insert(room)
					-- the problem is, this will also include neighboring rooms that overlap this room's rectangle
					room.regionMapBlockPos:insert(vec2i(x,y))
				end
			end
		end
	end
	
	local sides = table{vec2i(1,0), vec2i(-1,0), vec2i(0,-1), vec2i(0,1)}

	-- determine edges of rooms
	for _,region in ipairs(self.regions) do
		for _,room in ipairs(region.rooms) do
			for _,pos in ipairs(room.regionMapBlockPos) do
				for _,side in ipairs(sides) do
					local pos2 = pos + side
					if pos2.x >= 0 and pos2.x < region.width
					and pos2.y >= 0 and pos2.y < region.height
					then
						if not roomsAtXY(region, pos2.x, pos2.y) then
							-- we found a valid transition edge
							room.emptyEdges = room.emptyEdges or table()
							room.emptyEdges:insert{from=vec2i(pos:unpack()), to=vec2i(pos2:unpack())}
						end
					end
				end
			end
		end
		
		-- sort each roomsForTiles by room size, smallest first
		for i=1,Region.width * Region.height do
			local ms = region.roomsForTiles[i]
			if ms then 
				ms:sort(function(a,b)
					return a:obj().width * a:obj().height < b:obj().width * b:obj().height
				end)
			end
		end
	end

-- [==[
	-- TODO make this a config flag
	-- rebuild the region tilemap based on the map
	if config.rebuildRegionWorldMap then
		local freeLocations = table{
			0x88,
			0x98, 0x9e, 0x9f,
			0xae, 0xaf,
			0xcc, 0xcd,
			-- and then 0x1xx and 0x2xx stuff...
		}
		mapGfxTiles.item_0 = freeLocations[1]
		mapGfxTiles.item_3 = freeLocations[2]

		local function hiloswizzle(d, size)
			d = ffi.cast('uint8_t*', d)
			for i=0,size-1 do
				d[i] = bit.bor(
					bit.rshift(d[i], 4),
					bit.lshift(d[i], 4)
				)
			end
		end
		local function fix(t)
			local d = require 'util'.hexStrToByteArray(table.concat(t))
			hiloswizzle(d, 32)
			return d
		end

		self:graphicsWrite8x8x4bpp(self.pauseScreenTiles, self.graphicsTileSizeInBytes * mapGfxTiles.item_0, fix{
			'11111111',
			'11111111',
			'11111111',
			'11122111',
			'11122111',
			'11111111',
			'11111111',
			'11111111',
		})
		self:graphicsWrite8x8x4bpp(self.pauseScreenTiles, self.graphicsTileSizeInBytes * mapGfxTiles.item_3, fix{
			'21111112',
			'21111112',
			'21111112',
			'21122112',
			'21122112',
			'21111112',
			'21111112',
			'21111112',
		})


		for _,region in ipairs(self.regions) do
			-- [=[ using roomsAtTile
			for y=0,Region.height-2 do	-- why -1? because the top row doesn't map to the overworld map
				for x=0,Region.width-1 do
					
					local ms = roomsAtXY(region, x, y)
					if not ms then
						ffi.cast('uint16_t*', region.tilemap.v)[regionTilemapIndex(x,y)] = mapGfxTiles.empty
					else
						--[[
						options (in order of precedence):
							ship
							save_station
							map_station
							energy_refill_station
							missile_refill_station
							boss
							lift
							item_*
						--]]
						local found
						for _,m in ipairs(ms) do
							for _,rs in ipairs(m.roomStates) do
								if not found then
									for _,plm in ipairs(rs.plmset.plms) do
										if bit.rshift(plm.x, 4) + m:obj().x == x
										and bit.rshift(plm.y, 4) + m:obj().y == y
										then
											local name = self.plmCmdNameForValue[plm.cmd]
											if name then
												if name:sub(1,5) == 'item_'
												or name:sub(1,5) == 'boss_'
												or name == 'save_station' 
												or name == 'map_station'			-- these are overlays anyways
												or name == 'energy_refill_station'
												or name == 'missile_refill_station'
												or name == 'lift'
												-- TODO ship
												-- TODO bosses
												then
													found = name
													-- the only plm for bosses afaik is the boss_chozo_statue plm
													if found:sub(1,5) == 'boss_' then
														found = 'boss'
													end
												end
											end
										end
										if found then break end
									end
								end
								if not found then
									for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do
										local i = bit.rshift(enemySpawn.x, 8)
										local j = bit.rshift(enemySpawn.y, 8)
										-- some bosses move from off screen, so clamp pos onto the map
										i = math.clamp(i, 0, m:obj().width-1)
										j = math.clamp(j, 0, m:obj().height-1)
										if i + m:obj().x == x
										and j + m:obj().y == y
										then
											local enemy = self.enemyForPageOffset[enemySpawn.enemyPageOffset]
											if enemy then
												local name = enemy.name
												if name == 'Ceres Ridley'
												-- Grey Torizo - is that the first one wiwth bomb item?  and it must be spawned by the plm?
												or name == 'Spore Spawn'
												or name == 'Kraid (body)'	-- starts off screen?
												or name == 'Crocomire'
												or name == 'Phantoon (body)'
												or name == 'Botwoon'
												or name == 'Draygon (body)'	-- starts off screen?
												or name == 'Ridley'
												or name == 'Gold Torizo'
												or name == 'Mother Brain'
												then
													found = 'boss'
												elseif name == 'Elevator' then
													found = 'lift'
												end
											end
										end
										if found then break end
									end
								end
								if found then break end
							end
							if found then break end
						end


						local m = ms[1]
						--[[
						ffi.cast('uint16_t*', region.tilemap.v)[regionTilemapIndex(x,y)] = mapGfxTiles[0xf]
						--]]
						-- [[
						local sideflags = 0
						for i,side in ipairs(sides) do
							local pos2 = vec2i(x,y) + side
							local ms2 = roomsAtXY(region, pos2.x, pos2.y)
							if not (ms2 and ms2:find(m)) then
								sideflags = bit.bor(sideflags, bit.lshift(1, i-1))
							end
						end
						local graphicsTileIndex
						
						if found then
							if found:sub(1,5) == 'item_' then
								graphicsTileIndex = mapGfxTiles['item_'..('%x'):format(sideflags)]
									-- no item or that particular item_ is missing 
									-- TODO insert item_0 and item_3 graphics
									or mapGfxTiles.item_f
							elseif found == 'lift' then
								-- TODO determine if the lift is going up or down usign the room(state?).doors
								graphicsTileIndex = mapGfxTiles['lift_'..('%x'):format(sideflags)]
									or mapGfxTiles.lift_7

							else
								graphicsTileIndex = mapGfxTiles[found]
							end
						end
						if not found then
							graphicsTileIndex = mapGfxTiles[sideflags]
						end
						if graphicsTileIndex then
							ffi.cast('uint16_t*', region.tilemap.v)[regionTilemapIndex(x,y)] = graphicsTileIndex
						else
							ffi.cast('uint16_t*', region.tilemap.v)[regionTilemapIndex(x,y)] = mapGfxTiles[0]
						end
						--]]
					end
					
					--[[
					colorIndexHi values:
					everything in crateria seems to have bits 14 and 15 set, 12 and 13 0
					, so everything is $xCxx
					non-used tiles are all $0Cxx
					flipped are all 4Cxx or 8Cxx
					--]]
					region.tilemap.v[regionTilemapIndex(x,y)].colorIndexHi = 3
				end
			end
			--]=]
			--[=[ using the rooms themselves ... sort by size
			for _,room in ipairs(table(region.rooms):sort(function(a,b)
				return a:obj().width * a:obj().height > b:obj().width * b:obj().height
			end)) do

				local itemsAtPos = {}
				for _,rs in ipairs(room.roomStates) do
					for _,plm in ipairs(rs.plmset.plms) do
						local name = self.plmCmdNameForValue[plm.cmd]
						if name and name:sub(1,5) == 'item_' then
							-- find the map pos
							local i = bit.rshift(plm.x, 4)
							local j = bit.rshift(plm.y, 4)
							if i >= 0 and i < room:obj().width
							and j >= 0 and j < room:obj().height
							then
								itemsAtPos[i] = itemsAtPos[i] or {}
								itemsAtPos[i][j] = true
							else
								print('!!! WARNING !!! oob item')
							end
						end
					end
				end


				for j=0,room:obj().height-1 do
					for i=0,room:obj().width-1 do
						local x = room:obj().x + i
						local y = room:obj().y + j
						local sideflags = 0
						for k,side in ipairs(sides) do
							local contains = side.x + i >= 0 and side.x + i < room:obj().width
										and side.y + j >= 0 and side.y + j < room:obj().height
							if not contains then
								sideflags = bit.bor(sideflags, bit.lshift(1, k-1))
							end
						end
						
						local graphicsTileIndex 
						if itemsAtPos[i] and itemsAtPos[i][j] then
							graphicsTileIndex = mapGfxTiles['item_'..('%x'):format(sideflags)]
						-- no item or that particular item_ is missing 
						-- TODO insert item_0 and item_3 graphics
								or mapGfxTiles.item_f
						else
							graphicsTileIndex = mapGfxTiles[sideflags]
						end
						
						ffi.cast('uint16_t*', region.tilemap.v)[regionTilemapIndex(x,y)] = graphicsTileIndex
						region.tilemap.v[regionTilemapIndex(x,y)].colorIndexHi = 3
					end
				end
			end
			--]=]
		end
	end
--]==]
end

function SMRegions:regionsWriteMaps()
	for _,region in ipairs(self.regions) do
		region.tilemap:writeToROM()
	end
end


function SMRegions:regionsBuildMemoryMap(mem)
	self.regionTilemapAddr24s:addMem(mem, 'regionTilemapAddr24s')

	for _,region in ipairs(self.regions) do
		region.tilemap:addMem(mem, 'region '..region.index..' tilemap')
	end
end

function SMRegions:regionsPrint()
	-- shared in common with SMMap ... TODO make its own function?
	local function printblock(data, size, width, col)
		data = ffi.cast('uint8_t*', data)
		for i=0,size-1 do
			if col and i % col == 0 then io.write' ' end
			io.write((('%02x'):format(tonumber(data[i])):gsub('0','.')))
			if i % width == width-1 then print() end 
		end
		print()
	end
	
	for i,region in ipairs(self.regions) do
		print()
		print('region '..region.index..' map:')
		printblock(region.tilemap.v, region.tilemap:sizeof(), 2*32, 2)	--only write 32 cols, since the map is saved with the lhs on top of the rhs
	end
end


return SMRegions
