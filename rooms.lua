-- https://github.com/tewtal/smlib especially SMLib/ROMHandler.cs
-- metroidconstruction.com/SMMM
-- https://github.com/dansgithubuser/dansSuperMetroidLibrary/blob/master/sm.hpp
-- http://forum.metroidconstruction.com/index.php?topic=2476.0
-- http://www.metroidconstruction.com/SMMM/plm_disassembly.txt

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

local fx1_t = struct'fx1_t'{
	{select = 'uint16_t'},
	{surfaceStart = 'uint16_t'},
	{surfaceNew = 'uint16_t'},
	{surfaceDelay = 'uint8_t'},
	{layer3type = 'uint8_t'},
	{a = 'uint8_t'},
	{b = 'uint8_t'},
	{c = 'uint8_t'},
	{paletteFX = 'uint8_t'},
	{animateTile = 'uint8_t'},
	{blend = 'uint8_t'},
}

local bg_t = struct'bg_t'{
	{header = 'uint16_t'},
	{addr = 'uint16_t'},
	{bank = 'uint8_t'},
	-- then 14 bytes of unknown
	{unknown1 = 'uint16_t'},
	{unknown2 = 'uint16_t'},
	{unknown3 = 'uint16_t'},
	{unknown4 = 'uint16_t'},
	{unknown5 = 'uint16_t'},
	{unknown6 = 'uint16_t'},
	{unknown7 = 'uint16_t'},
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


local doorPLMTypes = table{
	-- normal exit
	exit_right = 0xb63b,
	exit_left = 0xb63f,
	exit_down = 0xb643,
	exit_up = 0xb647,
	-- gates
	normal_open_gate = 0xc826,
	normal_close_gate = 0xc82a,
	flipped_open_gate = 0xc82e,
	flipped_close_gate = 0xc832,
	shot_gate_top = 0xc836,
	-- grey
	door_grey_right = 0xc842,
	door_grey_left = 0xc848,
	door_grey_down = 0xc84e,
	door_grey_up = 0xc854,
	-- orange
	door_orange_right = 0xc85a,
	door_orange_left = 0xc860,
	door_orange_down = 0xc866,
	door_orange_up = 0xc86c,
	-- green
	door_green_right = 0xc872,
	door_green_left = 0xc878,
	door_green_down = 0xc87e,
	door_green_up = 0xc884,
	-- red
	door_red_right = 0xc88a,
	door_red_left = 0xc890,
	door_red_down = 0xc896,
	door_red_up = 0xc89c,
	-- blue
	-- where are the regular blue doors?
	door_blue_right_opening = 0xc8A2,
	door_blue_left_opening = 0xc8a8,
	door_blue_down_opening = 0xc8aE,
	door_blue_up_opening = 0xc8b4,
	door_blue_right_closing = 0xc8BA,
	door_blue_left_closing = 0xc8bE,
	door_blue_down_closing = 0xc8c2,
	door_blue_up_closing = 0xc8c6,
}
local doorPLMNameForValue = doorPLMTypes:map(function(v,k) return k,v end)

local RoomState = class()
function RoomState:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.plms = self.plms or table()
	self.scrollMods = self.scrollMods or table()
	self.enemyPops = self.enemyPops or table()
	self.enemySets = self.enemySets or table()
	self.fx1s = self.fx1s or table()
	self.bgs = self.bgs or table()
end

local mdbs = table()

local totalOriginalCompressedSize = 0
local totalRecompressedSize = 0


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
					local addr = topc(0x8e, rs.addr)
					rs.ptr = ffi.cast('roomstate_t*', rom + addr)
					insertUniqueMemoryRange(addr, ffi.sizeof'roomstate_t', 'roomstate_t', m)
				end
			end

			for roomStateIndex,roomState in ipairs(m.roomStates) do
				-- shouldn't all roomState.ptr's exist by now?
				--assert(roomState.ptr, "found a roomstate without a ptr")
				if not roomState.ptr then
					print('  !! found roomState without a pointer '..('%04x'):format(roomState.addr))
				else
					if roomState.ptr[0].scroll > 0x0001 and roomState.scroll ~= 0x8000 then
						local addr = topc(scrollBank, roomState.ptr[0].scroll)
						roomState.scrollDataPtr = rom + addr 
						-- sized mdb width x height
						insertUniqueMemoryRange(addr, m.ptr[0].width * m.ptr[0].height, 'scrolldata', m)
					end

print(' roomstate '..('%04x'):format(roomState.addr))
					if roomState.ptr[0].plm ~= 0 then
						local startaddr = topc(plmBank, roomState.ptr[0].plm)
						data = rom + startaddr
						while true do
							local ptr = ffi.cast('plm_t*', data)
							if ptr[0].cmd == 0 then 
								data = data + 2
								break 
							end
							--inserting the struct by-value
							roomState.plms:insert(ptr[0])
							data = data + ffi.sizeof'plm_t'
						end
						local len = data-rom-startaddr
						insertUniqueMemoryRange(startaddr, len, 'plm_t', m)
						-- look at plm range from topc(plmBank,roomState.ptr[0].plm) to plmPtr-rom
				
						-- randomize ... remove only for now
						-- removing turns a door blue
						--[[
						for i=#roomState.plms,1,-1 do
							local plm = roomState.plms[i]
							local plmName = doorPLMNameForValue[plm.cmd]
							if plmName then
								local color, side = plmName:match'^door_(%w+)_(%w+)'
								if side then
									roomState.plms:remove(i)
								end
							end						
						end
						--]]
						
						-- now write back ...
						local ptr = ffi.cast('plm_t*', rom + topc(plmBank, roomState.ptr[0].plm))
						for _,plm in ipairs(roomState.plms) do
							ptr[0] = plm
							ptr = ptr + 1
						end
						ffi.cast('uint16_t*', ptr)[0] = 0
				
						-- and print
						for _,plm in ipairs(roomState.plms) do
							io.write('  plm: '..plm)
							local plmName = doorPLMNameForValue[plm.cmd]
							if plmName then
								io.write(' '..plmName)
							end
							print()
						end
					end
					
					for _,plm in ipairs(roomState.plms) do
						if plm.cmd == 0xb703 then
							local startaddr = 0x70000 + plm.args
							data = rom + startaddr
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
							local len = data-rom-startaddr
							insertUniqueMemoryRange(startaddr, len, 'plm cmd', m)
	
							if ok then
								local scrollMod = {}
								scrollMod.addr = plm.args
								scrollMod.data = tmp
								roomState.scrollMods:insert(scrollMod)
							end
						end
					end
		
					-- TODO these enemyAddr's aren't lining up with any legitimate enemies ...
					local startaddr = topc(0xa1, roomState.ptr[0].enemyPop)
					data = rom + startaddr 
					while true do
						local ptr = ffi.cast('enemyPop_t*', data)
						if ptr[0].enemyAddr == 0xffff then
							-- include term and enemies-to-kill
							data = data + 2
							roomState.enemiesToKill = read'uint8_t'
							break
						end
						-- [[
						print('  enemyPop: '
							..((enemyForAddr[ptr[0].enemyAddr] or {}).name or '')
							..': '..ptr[0])
						--]]
						roomState.enemyPops:insert(ptr[0])
						data = data + ffi.sizeof'enemyPop_t'
					end
					local len = data-rom-startaddr
					insertUniqueMemoryRange(startaddr, len, 'enemyPop_t', m)
			
					local startaddr = topc(0xb4, roomState.ptr[0].enemySet)
					data = rom + startaddr 
					while true do
						local ptr = ffi.cast('enemySet_t*', data)
						if ptr[0].enemyAddr == 0xffff then 
-- looks like there is consistently 10 bytes of data trailing enemySet_t, starting with 0xffff
local tmp = ffi.cast('uint16_t*', data)
print('enemySet_t term:'..range(0,4):map(function(i) return ('%04x'):format(tmp[i]) end):concat' ')
							-- include terminator
							data = data + 2*5
							break 
						end
				
						--[[
						local enemy = enemyForAddr[ptr[0].enemyAddr]
						if enemy then
							print('  enemySet: '..enemy.name..': '..ptr[0])
						end
						--]]
						-- [[
						print('  enemySet: '
							..((enemyForAddr[ptr[0].enemyAddr] or {}).name or '')
							..': '..ptr[0])
						--]]

						roomState.enemySets:insert(ptr[0])
						data = data + ffi.sizeof'enemySet_t'
					end
					local len = data-rom-startaddr
					insertUniqueMemoryRange(startaddr, len, 'enemySet_t', m)
					--print('  #enemySets = '..#roomState.enemySets)
				
					local startaddr = topc(0x83, roomState.ptr[0].fx1)
					data = rom + startaddr
					local retry
					while true do
						local ptr = ffi.cast('fx1_t*', data)
						if ptr[0].select == 0xffff then
							-- do I really need to insert a last 'fx1' that has nothing but an 0xffff select?	
							-- include terminator
							data = data + 2
							break
						end
						if ptr[0].select == 0
						-- TODO only run this after all ddbs have been loaded?
						or m.ddbs:find(nil, function(d) return d.pointer == ptr[0].select end)
						then
							roomState.fx1s:insert(ptr[0])
							data = data + ffi.sizeof'fx1_t'
						else
							if not retry then
								retry = true
								startaddr = topc(0x83, roomState.ptr[0].fx1) + 0x10
								data = rom + startaddr
							else
								data = nil
								break
							end
						end
					end
					if data then
						local len = data-rom-startaddr
						insertUniqueMemoryRange(startaddr, len, 'fx1_t', m)
					end
				
					if roomState.ptr[0].bgDataPtr > 0x8000 then
						local startaddr = topc(0x8f, roomState.ptr[0].bgDataPtr)
						data = rom + startaddr
						while true do
							local ptr = ffi.cast('bg_t*', data)
							if ptr.header ~= 0x04 then
print('bg_t term: '..range(0,7):map(function(i) return ('%02x'):format(data[i]) end):concat' ')
								data = data + 8
								break
							end
							roomState.bgs:insert{bg=ptr[0]}
							data = data + ffi.sizeof'bg_t'
						end
						local len = data-rom-startaddr
						insertUniqueMemoryRange(startaddr, len, 'bg_t', m)
					
						for _,bg in ipairs(roomState.bgs) do
							local addr = topc(bg.bg.bank, bg.bg.addr)
							local decompressed, compressedSize = lz.decompress(addr, 0x10000)
							bg.data = decompressed
							insertUniqueMemoryRange(addr, compressedSize, 'bg data', m)
						end
					end

--[[ TODO decompress is failing here
					if roomState.ptr[0].layerHandling > 0x8000 then
						local addr = topc(0x8f, roomState.ptr[0].layerHandling)
						local decompressed, compressedSize = lz.decompress(addr, 0x1000)
						roomState.layerHandlingCode = decompressed
						insertUniqueMemoryRange(addr, compressedSize, 'layer handling code', m)
					end
--]]
				end
			
				-- TODO still - bg, layerhandling
				
				if roomState.ptr 
				-- only write the first instance of the room
				and roomStateIndex == 1
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
					
					local function printblock(data, width)
						for i=1,#data do
							io.write((('%02x'):format(tonumber(data[i])):gsub('0','.')))
							if i % width == 0 then print() end 
						end
						print()
					end
					local ofs = 0
					local id = data:sub(ofs+1,ofs + 2) ofs=ofs+2
					local w = m.ptr[0].width * 16
					local h = m.ptr[0].height * 16
					local solids = data:sub(ofs+1, ofs + 2*w*h) ofs=ofs+2*w*h
					local tiletypes = data:sub(ofs+1, ofs + w*h) ofs=ofs+w*h
					printblock(id, 2) 
					printblock(solids, 2*w) 
					printblock(tiletypes, w)
					assert(ofs <= #data, "didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..#data)
					print('data used for tiles: '..ofs..'. data remaining: '..(#data - ofs))
					
					drawRoom(m.ptr[0], solids, tiletypes)
--[[ write back compressed data ... reduces to 57% of the original compressed data

-- now to change the doors around ... or something
-- and then re-compress and re-write

					-- remove all doors
					for j=0,h-1-3 do
						for i=0,w-1 do
							-- blue door to the left
							if tiletypes[1 + i + w * j] == 0x41 then
							-- blue door to the right
							elseif tiletypes[1 + i + w * j] == 0x41 then
							end
						end
					end
				

					local recompressed = lz.compress(data)
					print('recompressed size: '..#recompressed..' vs original compressed size '..compressedSize)
					assert(#recompressed <= compressedSize, "recompressed to a larger size than the original.  recompressed "..#recompressed.." vs original "..compressedSize)
totalOriginalCompressedSize = totalOriginalCompressedSize + compressedSize
					compressedSize = #recompressed
totalRecompressedSize = totalRecompressedSize + compressedSize
					-- now write back to the original location at addr
					for i,v in ipairs(recompressed) do
						rom[addr+i-1] = ffi.cast('uint8_t', v)
					end
--]]					
				
					-- notice, this will exclude differing m.index/m.region that point to the same memory locations
					insertUniqueMemoryRange(addr, compressedSize, 'room tiles', m)
				end
			end
		
			local startaddr = topc(0x8e, m.ptr[0].doors)
			data = rom + startaddr 
			--data = rom + 0x70000 + m.ptr[0].doors
			local doorAddr = read'uint16_t'
			while doorAddr > 0x8000 do
				m.ddbs:insert{
					addr = doorAddr,
				}
				doorAddr = read'uint16_t'
			end
			-- exclude terminator (?)
			data = data - 2
			local len = data-rom - startaddr
			insertUniqueMemoryRange(startaddr, len, 'dooraddrs', m)
			
			for _,ddb in ipairs(m.ddbs) do
				local startaddr = topc(0x83, ddb.addr)
				data = rom + startaddr 
				ddb.ptr = ffi.cast('door_t*', data)
				if ddb.ptr[0].code > 0x8000 then
					local codeaddr = topc(0x8f, ddb.ptr[0].code)
					ddb.doorCodePtr = rom + codeaddr 
					-- the next 0x1000 bytes have the door asm code
					insertUniqueMemoryRange(codeaddr, 0x1000, 'door code', m)
				end
				print(' doors: '
					..('$83:%04x'):format(ddb.addr)
					..' '..ddb.ptr[0])
				insertUniqueMemoryRange(startaddr, ffi.sizeof'door_t', 'door', m)
			end
		
			mdbs:insert(m)
		end
	end
end


end, function(err)
	io.stderr:write(err..'\n'..debug.traceback())
end)

mapimg:save'map.png'

print()
print('overall recompressed from '..totalOriginalCompressedSize..' to '..totalRecompressedSize..
	', saving '..(totalOriginalCompressedSize - totalRecompressedSize)..' bytes '
	..'(new data is '..math.floor(totalRecompressedSize/totalOriginalCompressedSize*100)..'% of original size)')
