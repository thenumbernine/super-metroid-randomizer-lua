-- https://github.com/tewtal/smlib especially SMLib/ROMHandler.cs
-- metroidconstruction.com/SMMM
-- https://github.com/dansgithubuser/dansSuperMetroidLibrary/blob/master/sm.hpp
-- http://forum.metroidconstruction.com/index.php?topic=2476.0

local ffi = require 'ffi'
local struct = require 'struct'
local lz = require 'lz'

-- check where the PLM bank is
local plmBank = rom[0x204ac]

local scrollBank = 0x8f

local image = require 'image'
local tilesize = 4
local tilesPerRoom = 16
local roomsize = tilesPerRoom * tilesize
local mapimg = image(roomsize*68, roomsize*58, 3, 'unsigned char')

local colormap = range(254)
--colormap = shuffle(colormap)
colormap[0] = 0
colormap[255] = 255
-- data is sized 32*m.width x 16*m.width
local ofsPerRegion = {
	{3,0},	-- crateria
	{0,18},	-- brinstar
	{31,38},	-- norfair
	{37,-10},	-- wrecked ship
	{28,18},	-- maridia
	{0,0},	-- tourian
	{-5,25},	-- ceres
	{7,47},	-- testing
}

local function drawRoom(m, solids, tiletypes)
	local ofsx, ofsy = table.unpack(ofsPerRegion[m.region+1])
	
	-- special case for crateria
	if m.region == 0	-- crateria
	and m.x > 45 
	then
		ofsx = ofsx + 7
	end
	
	local xofs = roomsize * (ofsx - 4)
	local yofs = roomsize * (ofsy + 1)
	for j=0,m.height-1 do
		for i=0,m.width-1 do
			for ti=0,tilesPerRoom-1 do
				for tj=0,tilesPerRoom-1 do
					local dx = ti + tilesPerRoom * i
					local dy = tj + tilesPerRoom * j
					local di = dx + tilesPerRoom * m.width * dy
					-- solids is 1-based
					local d1 = solids[1 + 0 + 2 * di] or 0
					local d2 = solids[1 + 1 + 2 * di] or 0
					local d3 = tiletypes[1 + di] or 0
				
					if d1 == 0xff 
					--and (d2 == 0x00 or d2 == 0x83)
					then
					else
						for pi=0,tilesize-1 do
							for pj=0,tilesize-1 do
								local y = yofs + pj + tilesize * (tj + tilesPerRoom * (m.y + j))
								local x = xofs + pi + tilesize * (ti + tilesPerRoom * (m.x + i))
				--for y=(m.y + j)* roomsize + yofs, (m.y + m.height) * roomsize - 1 + yofs do
				--	for x=m.x * roomsize + xofs, (m.x + m.width) * roomsize - 1 + xofs do
								if x >= 0 and x < mapimg.width
								and y >= 0 and y < mapimg.height 
								then
									mapimg.buffer[0+3*(x+mapimg.width*y)] = colormap[tonumber(d1)]
									mapimg.buffer[1+3*(x+mapimg.width*y)] = colormap[tonumber(d2)]
									mapimg.buffer[2+3*(x+mapimg.width*y)] = colormap[tonumber(d3)]
								end
							end
						end
					end
				end
			end
		end
	end
end

-- defined in section 6
local mdb_t = struct'mdb_t'{
	{index = 'uint8_t'},		-- 0
	{region = 'uint8_t'},		-- 1
	{x = 'uint8_t'},			-- 2
	{y = 'uint8_t'},			-- 3
	{width = 'uint8_t'},		-- 4
	{height = 'uint8_t'},		-- 5
	{upScroller = 'uint8_t'},	-- 6
	{downScroller = 'uint8_t'},	-- 7
	{gfxFlags = 'uint8_t'},		-- 8
	{doors = 'uint16_t'},		-- 9 offset at bank  ... 9f?
}

local roomstate_t = struct'roomstate_t'{
	{roomAddr = 'uint16_t'},
	{roomBank = 'uint8_t'},
	{gfxSet = 'uint8_t'},
	{musicTrack = 'uint8_t'},
	{musicControl = 'uint8_t'},
	{fx1 = 'uint16_t'},
	{enemyPop = 'uint16_t'},
	{enemySet = 'uint16_t'},
	{layer2scrollData = 'uint16_t'},
	{scroll = 'uint16_t'},
	{unused = 'uint16_t'},
	{fx2 = 'uint16_t'},	--aka 'main asm ptr'
	{plm = 'uint16_t'},
	{bgDataPtr = 'uint16_t'},
	{layerHandling = 'uint16_t'},
}

local plm_t = struct'plm_t'{
	{cmd = 'uint16_t'},
	{x = 'uint8_t'},
	{y = 'uint8_t'},
	{args = 'uint16_t'},
}

local enemyPop_t = struct'enemyPop_t'{
	{enemyAddr = 'uint16_t'},	-- matches enemies[].addr
	{x = 'uint16_t'},
	{y = 'uint16_t'},
	{initGFX = 'uint16_t'},	-- 'tilemaps'
	{prop1 = 'uint16_t'},	-- 'special'
	{prop2 = 'uint16_t'},	-- 'graphics'
	{roomArg1 = 'uint16_t'},-- 'speed 1'
	{roomArg2 = 'uint16_t'},-- 'speed 2'
}

local enemySet_t = struct'enemySet_t'{
	{enemyAddr = 'uint16_t'},	-- matches enemies[].addr
	{palette = 'uint16_t'},
}

-- section 12 of metroidconstruction.com/SMMM
local door_t = struct'door_t'{
	{roomID = 'uint16_t'},				-- 0
	
--[[
0x40 = change regions
0x80 = elevator
--]]
	{flags = 'uint8_t'},				-- 2

--[[
0 = right
1 = left
2 = down
3 = up
| 0x04 flag = door closes behind samus
--]]
	{direction = 'uint8_t'},			-- 3
	
	{capX = 'uint8_t'},					-- 4
	{capY = 'uint8_t'},					-- 5
	{screenX = 'uint8_t'},				-- 6
	{screenY = 'uint8_t'},				-- 7
	{distToSpawnSamus = 'uint16_t'},	-- 9
	{code = 'uint16_t'},				-- A
}


local RoomState = class()
function RoomState:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.plms = self.plms or table()
	self.scrollMods = self.scrollMods or table()
	self.enemyPops = self.enemyPops or table()
	self.enemySets = self.enemySets or table()
end

local mdbs = table()
local roomMemoryRanges = table()


xpcall(function()


for x=0x8000,0xffff do
	local data = rom + topc(0x8e, x)
	local function read(ctype)
		local result = ffi.cast(ctype..'*', data)
		data = data + ffi.sizeof(ctype)
		return result[0]
	end
	local m = {
		roomStates = table(),
		ddbs = table(),
	}
	m.ptr = ffi.cast('mdb_t*', data)
	if (
		(data[12] == 0xE5 or data[12] == 0xE6) 
		and m.ptr[0].region < 8 
		and (m.ptr[0].width ~= 0 and m.ptr[0].width < 20) 
		and (m.ptr[0].height ~= 0 and m.ptr[0].height < 20)
		and m.ptr[0].upScroller ~= 0 
		and m.ptr[0].downScroller ~= 0 
		and m.ptr[0].gfxFlags < 0x10 
		and m.ptr[0].doors > 0x7F00
	) then
		print()
		print(
			('0x%06x '):format(data - rom)
			..'mdb '..m.ptr[0])
		data = data + 11

		-- events
		local testCode
		while true do
			-- this overlaps with m.ptr[0].doors
			testCode = read'uint16_t'
			if testCode == 0xe5e6 then break end
			if testCode == 0xffff then break end

			local testValue = 0
			local testValueDoor = 0
			if testCode == 0xE612
			or testCode == 0xE629
			then
				testValue = read'uint8_t'
			elseif testCode == 0xE5EB then
				testValueDoor = read'uint16_t'
			end

			local roomStateAddr = read'uint16_t'
			-- if this room's addr is 0xe5e6 then it won't get a pointer later
			-- and will never have one
			--assert(roomStateAddr ~= 0xe5e6, "found a room addr with 0xe5e6")

			local rs = RoomState{
				testCode = testCode,
				testValue = testValue,
				testValueDoor = testValueDoor,
				addr = assert(roomStateAddr),
			}
			m.roomStates:insert(rs)
			-- [[
			io.write(' adding room after mdb_t:')
			for _,k in ipairs{'addr','testCode','testValue','testValueDoor'} do
				io.write(' ',k,'=',('%04x'):format(rs[k]))
			end
			print()
			if rs.ptr then print('  '..rs.ptr[0]) end
			--]]
		end

		if testCode ~= 0xffff then
			local roomState = ffi.cast('roomstate_t*', data)
			data = data + ffi.sizeof'roomstate_t'
			
			-- why does the loading code insert two kinds of structs into this array?
			-- looks like the rooms added 5 lines up are excluded in the next loop
			-- should these be two separate loops and arrays?  they're two separate structures after all
			local rs = RoomState{
				testCode = 0xe5e6,
				testValue = 0,
				testValueDoor = 0,
				addr = 0xe5e6,
				ptr = roomState,
			}
			m.roomStates:insert(rs)
			-- [[			
			io.write(' adding room at 0xe5e6:')
			for _,k in ipairs{'addr','testCode','testValue','testValueDoor'} do
				io.write(' ',k,'=',('%04x'):format(rs[k]))
			end
			print()
			if rs.ptr then print('  '..rs.ptr[0]) end
			--]]

			for _,rs in ipairs(m.roomStates) do
				assert(rs.addr)
				if rs.addr ~= 0xe5e6 then
					rs.ptr = ffi.cast('roomstate_t*', rom + topc(0x8e, rs.addr))
				end
			end
		
			for roomStateIndex,roomState in ipairs(m.roomStates) do
				-- shouldn't all roomState.ptr's exist by now?
				--assert(roomState.ptr, "found a roomstate without a ptr")
				if not roomState.ptr then
					print('  !! found roomState without a pointer '..('%04x'):format(roomState.addr))
				else
					if roomState.ptr[0].scroll > 0x0001 and roomState.scroll ~= 0x8000 then
						roomState.scrollDataPtr = rom + topc(scrollBank, roomState.ptr[0].scroll)
						-- sized mdb width x height
					end
					if roomState.ptr[0].plm ~= 0 then
						local plmPtr = ffi.cast('plm_t*', rom + topc(plmBank, roomState.ptr[0].plm))
						while true do
							if plmPtr[0].cmd == 0 then break end
							roomState.plms:insert(plmPtr)
							plmPtr = plmPtr + 1
						end
					end
					for _,plmPtr in ipairs(roomState.plms) do
						if plmPtr[0].cmd == 0xb703 then
							data = rom + 0x70000 + plmPtr[0].args
						
							local ok = false
							local i = 1
							local tmp = table()
							while true do
								local screen = read'uint8_t'
								if screen == 0x80 then
									tmp[i] = 0x80
									ok = true
									break
								end

								local scroll = read'uint8_t'
								if scroll > 0x02 then
									ok = false
									break
								end
								tmp[i] = screen
								tmp[i+1] = scroll
								i = i + 2
							end
	
							if ok then
								local scrollMod = {}
								scrollMod.addr = plmPtr[0].args
								scrollMod.data = tmp
								roomState.scrollMods:insert(scrollMod)
							end
						end
					end
		
					-- TODO these enemyAddr's aren't lining up with any legitimate enemies ...
					data = rom + topc(0xa1, roomState.ptr[0].enemyPop)
					while true do
						local ptr = ffi.cast('enemyPop_t*', data)
						if ptr[0].enemyAddr == 0xffff then
							roomState.enemiesToKill = read'uint8_t'
							break
						end
						--[[
						print('  enemyPop '
							..(enemyForAddr[ptr[0].enemyAddr] or {}).name
							..': '..ptr[0])
						--]]
						roomState.enemyPops:insert(ptr)
						data = data + ffi.sizeof'enemyPop_t'
					end
				
					data = rom + topc(0xb4, roomState.ptr[0].enemySet)
					while true do
						local ptr = ffi.cast('enemySet_t*', data)
						if ptr[0].enemyAddr == 0xffff then break end
				
						--[[
						local enemy = enemyForAddr[ptr[0].enemyAddr]
						if enemy then
							print('  enemySet: '..enemy.name..': '..ptr[0])
						end
						--]]
						--[[
						print('  enemySet '
							..(enemyForAddr[ptr[0].enemyAddr] or {}).name
							..': '..ptr[0])
						--]]

						roomState.enemySets:insert(ptr)
						data = data + ffi.sizeof'enemySet_t'
					end
					--print('  #enemySets = '..#roomState.enemySets)
				end
			
				-- TODO still - fx1, bg, layerhandling
				
				if roomState.ptr 
and roomStateIndex == 1
--and #mdbs == 9	-- 9 has extra data after the room blocks, and when I recompress the whole thing, for some reason it only compresses the room blocks
				then
					local roomaddr = roomState.ptr[0].roomAddr
					local roomaddrstr = ('0x%02x'):format(roomState.ptr[0].roomBank)
						..('%04x'):format(roomState.ptr[0].roomAddr)
print('roomaddr '..roomaddrstr)
					local addr = topc(roomState.ptr[0].roomBank, roomaddr)
					-- then we decompress the next 0x10000 bytes ...
print('decompressing address '..('0x%06x'):format(addr))
					local data, compressedSize = lz.decompress(addr, 0x10000)

print('decompressed from '..compressedSize..' to '..#data)
					
					roomMemoryRanges:insert{addr, compressedSize, m}
					local function printblock(data, width)
						for i=1,#data do
							io.write((('%02x'):format(tonumber(data[i])):gsub('0','.')))
							if i % width == 0 then print() end 
						end
						print()
					end
					local ofs = 0
					local id = data:sub(ofs+1,ofs + 2) ofs=ofs+2
					local w = m.ptr[0].width * 32
					local h = m.ptr[0].height * 16
					local solids = data:sub(ofs+1, ofs + w*h) ofs=ofs+w*h
					local w2 = m.ptr[0].width * 16
					local tiletypes = data:sub(ofs+1, ofs + w2*h) ofs=ofs+w2*h
					printblock(id, 2) 
					printblock(solids, w) 
					printblock(tiletypes, w2)
					assert(ofs <= #data, "didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..#data)
					print('data used for tiles: '..ofs..'. data remaining: '..(#data - ofs))
					
					drawRoom(m.ptr[0], solids, tiletypes)

-- now to change the doors around ... or something
-- and then re-compress and re-write

-- [=[
if doneonce then
	for i=1,#data do
		assert(lastdata[i] == data[i], "found an error in the decompression at offset "..i
			..': '..data[i]..' should be '..lastdata[i])
	end
	assert(#lastdata == #data, "decompressions have different lengths: original "..#lastdata.." vs recompressed "..#data)
end
--]=]

if not doneonce then 
lastdata = data
	local recompressed = lz.compress(data)
	print('recompressed size: '..#recompressed..' vs original compressed size '..compressedSize)
	assert(#recompressed <= compressedSize, "recompressed to a larger size than the original.  recompressed "..#recompressed.." vs original "..compressedSize)
	print('recompressed data: '..recompressed:map(function(i) return ('%02x'):format(tonumber(i)) end):concat' ')
	compressedSize = #recompressed
	-- now write back to the original location at addr
	for i,v in ipairs(recompressed) do
		rom[addr+i-1] = ffi.cast('uint8_t', v)
	end
end
--]=]

--]]
				end
			end
			
			data = rom + 0x70000 + m.ptr[0].doors
			local doorAddr = read'uint16_t'
			while doorAddr > 0x8000 do
				m.ddbs:insert{
					addr = doorAddr,
				}
				doorAddr = read'uint16_t'
			end

			for _,ddb in ipairs(m.ddbs) do
				data = rom + topc(0x83, ddb.addr)
				ddb.ptr = ffi.cast('door_t*', data)
				if ddb.ptr[0].code > 0x8000 then
					ddb.doorCodePtr = rom + topc(0x8f, ddb.ptr[0].code)
					-- the next 0x1000 bytes have the door asm code
				end
				print(' doors: '..ddb.ptr[0])
			end
		
			mdbs:insert(m)
		end
	end
end


end, function(err)
	io.stderr:write(err..'\n'..debug.traceback())
end)

mapimg:save'map.png'

roomMemoryRanges:sort(function(a,b)
	return a[1] < b[1]
end)
print()
io.write('room memory ranges:')
for i,range in ipairs(roomMemoryRanges) do
	if i>1 then
		local prevRange = roomMemoryRanges[i-1]
		io.write(' ... '..(range[1]-(prevRange[1]+prevRange[2]))..' bytes of padding ...')
	end
	print()
	local m = range[3]	
	io.write( m.ptr[0].region ..'/'..m.ptr[0].index ..': '..
		('$%06x'):format(range[1])..'-'..('$%06x'):format(range[1]+range[2]-1) )
end
print()

