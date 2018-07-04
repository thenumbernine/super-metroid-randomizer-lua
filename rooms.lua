-- https://github.com/tewtal/smlib especially SMLib/ROMHandler.cs
-- metroidconstruction.com/SMMM
-- https://github.com/dansgithubuser/dansSuperMetroidLibrary/blob/master/sm.hpp
-- http://forum.metroidconstruction.com/index.php?topic=2476.0
-- http://www.metroidconstruction.com/SMMM/plm_disassembly.txt

-- TODO separate reading from writing from printing from modifying

local ffi = require 'ffi'
local struct = require 'struct'
local lz = require 'lz'

-- check where the PLM bank is
local plmBank = rom[0x204ac]
local scrollBank = 0x8f

local image = require 'image'
local blockSizeInPixels = 4
local blocksPerRoom = 16
local roomSizeInPixels = blocksPerRoom * blockSizeInPixels
local mapimg = image(roomSizeInPixels*68, roomSizeInPixels*58, 3, 'unsigned char')

local colormap = range(254)
--colormap = shuffle(colormap)
colormap[0] = 0
colormap[255] = 255
-- data is sized 32*m.width x 16*m.width
local ofsPerRegion = {
	function(m) 
		-- special case for crateria
		if m.region == 0	-- crateria
		and m.x > 45 
		then
			return 10,0
		end
		return 3,0
	end,	-- crateria
	function(m) return 0,18 end,	-- brinstar
	function(m) return 31,38 end,	-- norfair
	function(m) return 37,-10 end,	-- wrecked ship
	function(m) return 28,18 end,	-- maridia
	function(m) return 0,0 end,	-- tourian
	function(m) return -5,25 end,	-- ceres
	function(m) return 7,47 end,	-- testing
}

local function drawRoom(m, solids, bts)
	local ofsx, ofsy = ofsPerRegion[m.region+1](m)
	local xofs = roomSizeInPixels * (ofsx - 4)
	local yofs = roomSizeInPixels * (ofsy + 1)
	for j=0,m.height-1 do
		for i=0,m.width-1 do
			for ti=0,blocksPerRoom-1 do
				for tj=0,blocksPerRoom-1 do
					local dx = ti + blocksPerRoom * i
					local dy = tj + blocksPerRoom * j
					local di = dx + blocksPerRoom * m.width * dy
					-- solids is 1-based
					local d1 = solids[1 + 0 + 2 * di] or 0
					local d2 = solids[1 + 1 + 2 * di] or 0
					local d3 = bts[1 + di] or 0
				
					if d1 == 0xff 
					--and (d2 == 0x00 or d2 == 0x83)
					then
					else
						for pi=0,blockSizeInPixels-1 do
							for pj=0,blockSizeInPixels-1 do
								local y = yofs + pj + blockSizeInPixels * (tj + blocksPerRoom * (m.y + j))
								local x = xofs + pi + blockSizeInPixels * (ti + blocksPerRoom * (m.x + i))
				--for y=(m.y + j)* roomSizeInPixels + yofs, (m.y + m.height) * roomSizeInPixels - 1 + yofs do
				--	for x=m.x * roomSizeInPixels + xofs, (m.x + m.width) * roomSizeInPixels - 1 + xofs do
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
local mdb_t = struct'mdb_t'{	-- aka mdb_header_t
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

-- this is how the mdb_format.txt describes it, but it looks like the structure might be a bit more conditional...
local stateselect_t = struct'stateselect_t'{
	{testcode = 'uint16_t'},	-- ptr to test code in bank $8f
	{testvalue = 'uint8_t'},
	{roomstate = 'uint16_t'},	-- ptr to alternative roomstate in bank $8f
}

local stateselect2_t = struct'stateselect2_t'{
	{testcode = 'uint16_t'},
	{roomstate = 'uint16_t'},
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
	{layer2scrollData = 'uint16_t'},	-- TODO
	{scroll = 'uint16_t'},
	{unused = 'uint16_t'},
	{fx2 = 'uint16_t'},					-- TODO - aka 'main asm ptr'
	{plm = 'uint16_t'},
	{bgdata = 'uint16_t'},
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
	-- skip the next 14 bytes
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
	self.enemyPops = self.enemyPops or table()
	self.enemySets = self.enemySets or table()
	self.fx1s = self.fx1s or table()
	self.bgs = self.bgs or table()
	self.rooms = self.rooms or table()
end

-- table of all unique plm regions
local plmsets = table()
local function addPLMSet(addr, m)	-- m is only used for insertUniqueMemoryRange.  you have to add to plmset.mdbs externally
	local startaddr = addr
	local _,plmset = plmsets:find(nil, function(plmset) return plmset.addr == addr end)
	if plmset then return plmset end

	local startaddr = addr

	local plms = table()
	while true do
		local ptr = ffi.cast('plm_t*', rom+addr)
		if ptr[0].cmd == 0 then 
			-- include plm term
			addr = addr + 2
			break 
		end
		--inserting the struct by-value
		plms:insert(ptr[0])
		addr = addr + ffi.sizeof'plm_t'
	end
	local len = addr-startaddr

	-- nil plmset for no plms
	--if #plms == 0 then return end

	local plmset = {
		addr = startaddr,
		scrollMods = table(),
		plms = plms,
		mdbs = table(),
		roomStates = table(),
	}
	plmsets:insert(plmset)


-- this shows the orig rom memory
insertUniqueMemoryRange(startaddr, len, 'plm_t', m)

	-- now interpret the plms...
	for _,plm in ipairs(plmset.plms) do
		if plm.cmd == 0xb703 then
			local startaddr = 0x70000 + plm.args
			local addr = startaddr
			local ok = false
			local i = 1
			local tmp = table()
			while true do
				local screen = rom[addr] addr=addr+1
				if screen == 0x80 then
					tmp[i] = 0x80
					ok = true
					break
				end

				local scroll = rom[addr] addr=addr+1
				if scroll > 0x02 then
					ok = false
					break
				end
				tmp[i] = screen
				tmp[i+1] = scroll
				i = i + 2
			end
			local len = addr-startaddr
			insertUniqueMemoryRange(startaddr, len, 'plm cmd')
	
			if ok then
				local scrollMod = {}
				scrollMod.addr = plm.args
				scrollMod.data = tmp
				plmset.scrollMods:insert(scrollMod)
			end
		end
	end

	return plmset
end


-- table of all unique bgs.
-- each entry has .addr and .ptr = (bg_t*)(rom+.addr)
-- doesn't create duplicates -- returns a previous copy if it exists
local bgs = table()
local function addBG(addr)
	local _,bg = bgs:find(nil, function(bg) return bg.addr == addr end)
	if bg then return bg end
	bg = {
		addr = addr,
		ptr = ffi.cast('bg_t*', rom + addr),
		-- list of all m's that use this bg
		mdbs = table(),
	}
	bgs:insert(bg)
	return bg
end


local fx1s = table()
local function addFX1(addr)
	local _,fx1 = fx1s:find(nil, function(fx1) return fx1.addr == addr end)
	if fx1 then return fx1 end
	fx1 = {
		addr = addr,
		ptr = ffi.cast('fx1_t*', rom + addr),
		mdbs = table(),
	}
	fx1s:insert(fx1)
	return fx1
end

local Room = class()
function Room:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	self.mdbs = table()
end
function Room:getData()
	return table():append(
		self.head,
		self.solids,
		self.bts,
		self.tail
	)
end

local rooms = table()
-- see how well our recompression works (I'm getting 57% of the original compressed size)
local totalOriginalCompressedSize = 0
local totalRecompressedSize = 0
local function addRoom(addr, m)
	local _,room = rooms:find(nil, function(room) 
		return room.addr == addr 
	end)
	if room then 
		-- rooms can come from separate mdb_t's
		-- which means they can have separate widths & heights
		-- so here, assert that their width & height matches
		assert(16 * room.m.ptr[0].width == room.width, "expected room width "..room.width.." but got "..m.ptr[0].width)
		assert(16 * room.m.ptr[0].height == room.height, "expected room height "..room.height.." but got "..m.ptr[0].height)
		room.mdbs:insert(m)
		return room 
	end
					
	local roomaddrstr = ('$%06x'):format(addr)
--print('roomaddr '..roomaddrstr)
	
	-- then we decompress the next 0x10000 bytes ...
--print('decompressing address '..('0x%06x'):format(addr))
	local data, compressedSize = lz.decompress(addr, 0x10000)

--print('decompressed from '..compressedSize..' to '..#data)
	
	local ofs = 0
	local head = data:sub(ofs+1,ofs + 2) ofs=ofs+2
	local w = m.ptr[0].width * 16
	local h = m.ptr[0].height * 16
	local solids = data:sub(ofs+1, ofs + 2*w*h) ofs=ofs+2*w*h
	-- bts = 'behind the scenes'
	local bts = data:sub(ofs+1, ofs + w*h) ofs=ofs+w*h
	local tail = data:sub(ofs+1)
	assert(ofs <= #data, "didn't get enough tile data from decompression. expected room data size "..ofs.." <= data we got "..#data)
--print('data used for tiles: '..ofs..'. data remaining: '..(#data - ofs))
	
	-- insert this range to see what the old data took up
	insertUniqueMemoryRange(addr, compressedSize, 'room', m)

	local room = Room{
		addr = addr,
		m = m,
		-- this is just 16*(w,h)
		width = w,
		height = h,
		mdbs = table{m},
		-- rule of thumb: do not exceed this
		origCompressedSize = compressedSize,
		-- decompressed data (in order):
		head = head,	-- first 2 bytes of data
		solids = solids,
		bts = bts,
		tail = tail,	-- last bytes after bts
	}
	rooms:insert(room)
	return room
end



local mdbs = table()
xpcall(function()


--[[
from $078000 to $079193 is plm_t data
the first mdb_t is at $0791f8
from there it is a dense structure of ...
mdb_t
stateselect's (in reverse order)
roomstate_t's (in forward order)
dooraddrs
... then comes extra stuff, sometimes:
scrolldata (which is in one place wedged into nowhere)
plm cmd
--]]
for x=0x8000,0xffff do
	local data = rom + topc(0x8e, x)
	local function read(ctype)
		local result = ffi.cast(ctype..'*', data)
		data = data + ffi.sizeof(ctype)
		return result[0]
	end

	local mptr = ffi.cast('mdb_t*', data)
	if (
		(data[12] == 0xE5 or data[12] == 0xE6) 
		and mptr[0].region < 8 
		and (mptr[0].width ~= 0 and mptr[0].width < 20) 
		and (mptr[0].height ~= 0 and mptr[0].height < 20)
		and mptr[0].upScroller ~= 0 
		and mptr[0].downScroller ~= 0 
		and mptr[0].gfxFlags < 0x10 
		and mptr[0].doors > 0x7F00
	) then
		local m = {
			roomStates = table(),
			ddbs = table(),
			ptr = mptr,
		}	
		mdbs:insert(m)
		insertUniqueMemoryRange(data-rom, ffi.sizeof'mdb_t', 'mdb_t', m)
		data = data + ffi.sizeof'mdb_t'

		-- events
		while true do
			local startaddr = data - rom
			local testcode = ffi.cast('uint16_t*',data)[0]
			
			if testcode == 0xe5e6 then 
				insertUniqueMemoryRange(data-rom, 2, 'stateselect', m)	-- term
				data = data + 2
				break 
			end
		
			local ctype
			local selectptr
			if testcode == 0xE612
			or testcode == 0xE629
			then
				ctype = 'stateselect_t'
			elseif testcode == 0xE5EB then
				-- this is never reached
				error'here' 
				-- I'm not using this just yet
				-- struct {
				-- 	uint16_t testcode;
				-- 	uint16_t testvaluedoor;
				--	uint16_t roomstate;
				-- }
			else
				ctype = 'stateselect2_t'
			end
			local rs = RoomState{
				select = ffi.cast(ctype..'*', data),
				select_ctype = ctype,	-- using for debug print only
			}
			m.roomStates:insert(rs)
			
			data = data + ffi.sizeof(ctype)
			insertUniqueMemoryRange(startaddr, ffi.sizeof(ctype), 'stateselect', m)
		end

		do
			-- after the last stateselect is the first roomstate_t
			local rsptr = ffi.cast('roomstate_t*', data)
			insertUniqueMemoryRange(data-rom, ffi.sizeof'roomstate_t', 'roomstate_t', m)
			data = data + ffi.sizeof'roomstate_t'
			
			local rs = RoomState{
				-- no select means a terminator
				ptr = rsptr,
			}
			m.roomStates:insert(rs)

			for _,rs in ipairs(m.roomStates) do
				assert(rs.select or rs.ptr)
				if rs.select then
					assert(not rs.ptr)
					local addr = topc(0x8e, rs.select[0].roomstate)
					rs.ptr = ffi.cast('roomstate_t*', rom + addr)
					insertUniqueMemoryRange(addr, ffi.sizeof'roomstate_t', 'roomstate_t', m)
				end

				assert(rs.ptr)
			end

			-- I wonder if I can assert that all the roomstate_t's are in contiguous memory after the stateselect's ... 
			-- they sure aren't sequential
			-- they might be reverse-sequential
			-- sure enough, YES.  roomstates are contiguous and reverse-sequential from stateselect's
			--[[
			for i=1,#m.roomStates-1 do
				assert(m.roomStates[i+1].ptr + 1 == m.roomStates[i].ptr)
			end
			--]]

			for _,rs in ipairs(m.roomStates) do
				-- shouldn't all rs.ptr's exist by now?
				--assert(rs.ptr, "found a roomstate without a ptr")
				if not rs.ptr then
					error('found roomState without a pointer')
				else
					if rs.ptr[0].scroll > 0x0001 and rs.ptr[0].scroll ~= 0x8000 then
						local addr = topc(scrollBank, rs.ptr[0].scroll)
						local scrollDataPtr = rom + addr 
						local scrollDataSize = m.ptr[0].width * m.ptr[0].height
						rs.scrollData = range(scrollDataSize):map(function(i)
							return scrollDataPtr[i-1]
						end)
						-- sized mdb width x height
						insertUniqueMemoryRange(addr, scrollDataSize, 'scrolldata', m)
					end
					
					if rs.ptr[0].plm ~= 0 then
						local addr = topc(plmBank, rs.ptr[0].plm)
						local plmset = addPLMSet(addr, m)
						if plmset and #plmset.plms > 0 then
							rs.plmset = plmset
							plmset.mdbs:insert(m)
							plmset.roomStates:insert(rs)
						else
							rs.ptr[0].plm = 0
						end
					end
					
					-- TODO these enemyAddr's aren't lining up with any legitimate enemies ...
					local startaddr = topc(0xa1, rs.ptr[0].enemyPop)
					data = rom + startaddr 
					while true do
						local ptr = ffi.cast('enemyPop_t*', data)
						if ptr[0].enemyAddr == 0xffff then
							-- include term and enemies-to-kill
							data = data + 2
							rs.enemiesToKill = read'uint8_t'
							break
						end
						rs.enemyPops:insert(ptr[0])
						data = data + ffi.sizeof'enemyPop_t'
					end
					local len = data-rom-startaddr
					insertUniqueMemoryRange(startaddr, len, 'enemyPop_t', m)
			
					local startaddr = topc(0xb4, rs.ptr[0].enemySet)
					data = rom + startaddr 
					while true do
						local ptr = ffi.cast('enemySet_t*', data)
						if ptr[0].enemyAddr == 0xffff then 
-- looks like there is consistently 10 bytes of data trailing enemySet_t, starting with 0xffff
--print('   enemySet_t term: '..range(0,9):map(function(i) return ('%02x'):format(data[i]) end):concat' ')
							-- include terminator
							data = data + 10
							break 
						end
				
						rs.enemySets:insert(ptr[0])
						data = data + ffi.sizeof'enemySet_t'
					end
					local len = data-rom-startaddr
					insertUniqueMemoryRange(startaddr, len, 'enemySet_t', m)
				
					local startaddr = topc(0x83, rs.ptr[0].fx1)
					local addr = startaddr
					local retry
					while true do
						local cmd = ffi.cast('uint16_t*', rom+addr)[0]
						if cmd == 0xffff then
							-- do I really need to insert a last 'fx1' that has nothing but an 0xffff select?
							-- include terminator bytes in block length:
							addr = addr + 2
							break
						end
						if cmd == 0
						-- TODO this condition was in smlib, but m.ddbs won't be complete until after all ddbs have been loaded
						or m.ddbs:find(nil, function(d) return d.pointer == cmd end)
						then
							local fx1 = addFX1(addr)
							fx1.mdbs:insert(m)
							rs.fx1s:insert(fx1)
							addr = addr + ffi.sizeof'fx1_t'
						else
							-- try again 0x10 bytes ahead
							if not retry then
								retry = true
								startaddr = topc(0x83, rs.ptr[0].fx1) + 0x10
								addr = startaddr
							else
								addr = nil
								break
							end
						end
					end
					if addr then
						local len = addr - startaddr
						insertUniqueMemoryRange(startaddr, len, 'fx1_t', m)
					end
				
					if rs.ptr[0].bgdata > 0x8000 then
						local startaddr = topc(0x8f, rs.ptr[0].bgdata)
						local addr = startaddr
						while true do
							local ptr = ffi.cast('bg_t*', rom+addr)
							
-- this is a bad test of validity
-- this says so: http://metroidconstruction.com/SMMM/ready-made_backgrounds.txt
-- in fact, I never read more than 1 bg, and sometimes I read 0
--[[
							if ptr.header ~= 0x04 then
								addr = addr + 8
								break
							end
--]]
							-- so bgs[i].addr is the address where bgs[i].ptr was found
							-- and bgs[i].ptr[0].bank,addr points to where bgs[i].data was found
							-- a little confusing
							local bg = addBG(addr)
							bg.mdbs:insert(m)
							rs.bgs:insert(bg)
							addr = addr + ffi.sizeof'bg_t'
						
addr=addr+8
do break end
						end
						insertUniqueMemoryRange(startaddr, addr-startaddr, 'bg_t', m)
					end

--[[ TODO decompress is failing here
-- 0x8f is also used for door code and for plm, soo....
					if rs.ptr[0].layerHandling > 0x8000 then
						local addr = topc(0x8f, rs.ptr[0].layerHandling)
						local decompressed, compressedSize = lz.decompress(addr, 0x1000)
						rs.layerHandlingCode = decompressed
						insertUniqueMemoryRange(addr, compressedSize, 'layer handling code', m)
					end
--]]
				end
				
				if rs.ptr then
					local addr = topc(rs.ptr[0].roomBank, rs.ptr[0].roomAddr)
					rs.rooms:insert(addRoom(addr, m))
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
			-- exclude terminator
			data = data - 2
--print('   dooraddr term: '..range(0,1):map(function(i) return ('%02x'):format(data[i]) end):concat' ')			
			local len = data-rom - startaddr
			-- either +0, +39 or +44
			insertUniqueMemoryRange(startaddr, len, 'dooraddrs', m)
			
			for _,ddb in ipairs(m.ddbs) do
				local startaddr = topc(0x83, ddb.addr)
				data = rom + startaddr 
				ddb.ptr = ffi.cast('door_t*', data)
				if ddb.ptr[0].code > 0x8000 then
					local codeaddr = topc(0x8f, ddb.ptr[0].code)
					ddb.doorCodePtr = rom + codeaddr 
					-- the next 0x1000 bytes have the door asm code
					insertUniqueMemoryRange(codeaddr, 0x10, 'door code', m)
				end
				insertUniqueMemoryRange(startaddr, ffi.sizeof'door_t', 'door', m)
			end
		end
	end
end


end, function(err)
	io.stderr:write(err..'\n'..debug.traceback())
end)


-- [[ asserting underlying structure of the mdb_t...
-- verify that after each mdb_t, the stateselect / roomstate_t / dooraddrs are packed together

-- before the first mdb_t is 174 plm_t's, 
-- then 100 bytes of something
assert(mdbs)
for j,m in ipairs(mdbs) do
	local d = ffi.cast('uint8_t*',m.ptr)
	local mdbaddr = d - rom
	d = d + ffi.sizeof'mdb_t'
	-- if there's only 1 roomState then it is a term, and
	for i=1,#m.roomStates-1 do
		assert(d == ffi.cast('uint8_t*', m.roomStates[i].select))
		d = d + ffi.sizeof(m.roomStates[i].select_ctype)
	end
	-- last stateselect should always be 2 byte term
	d = d + 2
	-- next should always match the last room
	for i=#m.roomStates,1,-1 do
		assert(d == ffi.cast('uint8_t*', m.roomStates[i].ptr))
		d = d + ffi.sizeof'roomstate_t'
	end
	-- for a single room there is an extra 26 bytes of padding between the roomstate_t's and the dooraddrs
	-- and that room is $07ad1b, the speed booster room
	-- the memory map at http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
	-- says it is just part of the speed booster room
	if mdbaddr == 0x07ad1b then
print('speed booster room extra trailing data: '..range(26):map(function(i) return (' %02x'):format(d[i-1]) end):concat())
		d = d + 26
	end
	local dooraddr = topc(0x8e, m.ptr[0].doors)
	assert(d == rom + dooraddr)
	d = d + 2 * #m.ddbs
	
	-- now expect all scrolldatas of all rooms of this mdb_t
	-- the # of unique scrolldatas is either 0 or 1
	local scrolls = m.roomStates:map(function(rs)
		return true, rs.ptr[0].scroll
	end):keys():filter(function(scroll)
		return scroll > 1 and scroll ~= 0x8000
	end):sort()
	assert(#scrolls <= 1)
	for _,scroll in ipairs(scrolls) do
		local addr = topc(scrollBank, scroll)
		assert(d == rom + addr)
		d = d + m.ptr[0].width * m.ptr[0].height
	end

	-- see if the next mdb_t is immediately after
	-- sometimes a few plm_t's are found next ...
	--[=[
	if j+1 <= #mdbs then
		local m2 = ffi.cast('uint8_t*', mdbs[j+1].ptr)
		if d ~= m2 then
			print('non-contiguous mdb_t before '..('$%06x'):format(m2-rom))	
		end
	end
	--]=]
end
--]]

-- plm randomization:
-- randomize ... remove only for now
-- removing turns a door blue
-- TODO when combined with modifying tiles, this is screwing up door transitions
-- [[
for _,plmset in ipairs(plmsets) do
	--[=[ remove all door plms
	for i=#plmset.plms,1,-1 do
		local plm = plmset.plms[i]
		local plmName = doorPLMNameForValue[plm.cmd]
		if plmName then
			local color, side = plmName:match'^door_(%w+)_(%w+)'
			if side then
				plmset.plms:remove(i)
			end
		end						
	end
	--]=]
	--[=[ change all doors to red
	for _,plm in ipairs(plmset.plms) do
		local name = doorPLMNameForValue[plm.cmd]
		if name then
			local color, side = name:match'^door_(%w+)_(%w+)'
			if side then
				plm.cmd = assert(doorPLMTypes['door_red_'..side])
			end
		end
	end
	--]=]
	-- if we erased all plms then we should clear all flags in all referencing rooms
	if #plmset.plms == 0 then
		for _,rs in ipairs(plmset.roomStates) do
			rs.ptr[0].plm = 0
			rs.plmset = nil
		end
	end
end
--]]

--[[ writing back plms ...
-- turns out this needs more bulletproofing
-- because the door changes and stuff modify those original plm locations 
--[=[
plm memory ranges:
 0/ 0: $078000..$079193 (plm_t x174) 
 3/ 0: $07c215..$07c230 (plm_t x2) 
 	... 20 bytes of padding ...
 3/ 3: $07c245..$07c2fe (plm_t x15) 
 	... 26 bytes of padding ...
 3/ 3: $07c319..$07c8c6 (plm_t x91) 
 	... 199 bytes of padding ...
--]=]
-- where plms were written before, so should be safe, right?
-- ranges are inclusive
local plmWriteRanges = {
 	{0x78000, 0x79193},	
 	-- then comes mdb_t data, and a lot of other stuff ...
	{0x7c215, 0x7c230},
 	--... 20 bytes of padding ... which is "Hallway Atop Wrecked Ship" PLM data, according to metroid rom map.
	-- I don't see where it is referenced from though.
	{0x7c245, 0x7c2fe},
 	--... 26 bytes of padding ... "Hallway Atop Wrecked Ship" again
	{0x7c319, 0x7c8c6},
 	-- next comes which is L12 data, and then a lot more stuff
	{0x7e87f, 0x7e880},
	-- then comes 
	{0x7e99B, 0x7ffff},	-- this is listed as 'free data' in the metroid rom map
}
for _,range in ipairs(plmWriteRanges) do
	range.sofar = range[1]
end


-- if the roomstate points to an empty plmset then it can be cleared
for _,plmset in ipairs(plmsets) do
	if #plmset.plms == 0 then
		for j=#plmset.roomStates,1,-1 do
			local rs = plmset.roomStates[j]
			rs.ptr[0].plm = 0
			rs.plmset = nil
			plmset.roomStates[j] = nil
		end
	end
end
-- remove empty plmsets
-- TODO hmm if I remove the plmsets from the list, then the first room to the left from the ship stalls 
-- another byproduct of this is ... when you start a new game, the door outside old mother brain is grey
-- i think plms have ptrs to other plms that need to be updated ... 
--[=[
for i=#plmsets,1,-1 do
	local plmset = plmsets[i]
	if #plmset.plms == 0 then
		plmsets:remove(i)
		-- if you remove plm #8 from the list ... even though it's just a terminator ... you can't walk into the room to the left of the ship
		if i <= 9 then break end
	end
end
--]=]

-- see if there are duplicates
for i=1,#plmsets-1 do
	local pi = plmsets[i]
	for j=i+1,#plmsets do
		local pj = plmsets[j]
		if #pi.plms == #pj.plms 
		-- a lot of zero-length plms match ... but what about non-zero-length plms? none match
		and #pi.plms > 0
		then
			local differ
			for k=1,#pi.plms do
				if pi.plms[k] ~= pj.plms[k] then
					differ = true
					break
				end
			end
			if not differ then
				print('plms '..('$%06x'):format(pi.addr)..' and '..('$%06x'):format(pj.addr)..' are matching')
			end
		end
	end
end
for _,plmset in ipairs(plmsets) do
	-- TODO, if there are any duplicate plmsets then get rid of them
	local bytesToWrite = #plmset.plms * ffi.sizeof'plm_t' + 2	-- +2 for null term
	local fromaddr, toaddr
	for _,range in ipairs(plmWriteRanges) do
		if range.sofar + bytesToWrite <= range[2]+1 then
			fromaddr = range.sofar	
			-- write
			for _,plm in ipairs(plmset.plms) do
				ffi.cast('plm_t*', rom+range.sofar)[0] = plm
				range.sofar = range.sofar + ffi.sizeof'plm_t'
			end
			ffi.cast('uint16_t*', rom+range.sofar)[0] = 0
			range.sofar = range.sofar + ffi.sizeof'uint16_t'
			toaddr = range.sofar
			break
		end
	end
	if fromaddr then
-- this shows the new rom memory
insertUniqueMemoryRange(fromaddr, toaddr-fromaddr, 'plm_t', m)
		--[=[
		print('writing plms from '
			..('$%06x'):format(fromaddr)
			..' to '..('$%06x'):format(toaddr))
		--]=]
		for _,rs in ipairs(plmset.roomStates) do
			local newofs = bit.band(0xffff, fromaddr)
			if newofs ~= rs.ptr[0].plm then
				print('updating roomstate plm from '..('%04x'):format(rs.ptr[0].plm)..' to '..('%04x'):format(newofs))
				rs.ptr[0].plm = newofs 
			end
		end
	else
		error("couldn't find anywhere to write plm_t")
	end
end
--]]

print()
print("all plm_t's:")
for _,plmset in ipairs(plmsets) do
	print(' '..('$%06x'):format(plmset.addr)
		..' mdbs: '..plmset.mdbs:map(function(m)
			return m.ptr[0].region..'/'..m.ptr[0].index
		end):concat' '
	)
	for _,plm in ipairs(plmset.plms) do
		print('  '..plm)
	end
end

-- print bg info
print()
print("all bg_t's:")
bgs:sort(function(a,b) return a.addr < b.addr end)
for _,bg in ipairs(bgs) do
	print(' '..('$%06x'):format(bg.addr)..': '..bg.ptr[0]
		..' mdbs: '..bg.mdbs:map(function(m)
			return m.ptr[0].region..'/'..m.ptr[0].index
		end):concat' '
	)
end


--[[ load data
-- this worked fine when I was discounting zero-length bg_ts, but once I started requiring bgdata to point to at least one, this is now getting bad values
for _,bg in ipairs(bgs) do
	local addr = topc(bg.ptr[0].bank, bg.ptr[0].addr)
	local decompressed, compressedSize = lz.decompress(addr, 0x10000)
	bg.data = decompressed
	insertUniqueMemoryRange(addr, compressedSize, 'bg data', m)
end
--]]

-- print fx1 info
print()
print("all fx1_t's:")
fx1s:sort(function(a,b) return a.addr < b.addr end)
for _,fx1 in ipairs(fx1s) do
	print(' '..('$%06x'):format(fx1.addr)..': '..fx1.ptr[0]
		..' mdbs: '..fx1.mdbs:map(function(m)
			return m.ptr[0].region..'/'..m.ptr[0].index
		end):concat' '
	)
end

-- print mdb info
print()
print("all mdb_t's:")
for _,m in ipairs(mdbs) do
	print((' $%06x'):format(ffi.cast('uint8_t*', m.ptr) - rom)..' mdb_t '..m.ptr[0])
	for _,rs in ipairs(m.roomStates) do
		print('  '..('$%06x'):format(ffi.cast('uint8_t*',rs.ptr)-rom)..' roomstate_t '..rs.ptr[0]) 
		if rs.select then
			print('  '..('$%06x'):format(ffi.cast('uint8_t*', rs.select) - rom)..' '..rs.select_ctype..' '..rs.select[0]) 
		end
		-- [[
		if rs.plmset then
			for _,plm in ipairs(rs.plmset.plms) do
				io.write('   plm_t: '..plm)
				local plmName = doorPLMNameForValue[plm.cmd]
				if plmName then io.write(' '..plmName) end
				print()	
			end
		end
		--]]
		for _,enemyPop in ipairs(rs.enemyPops) do	
			print('   enemyPop: '
				..((enemyForAddr[enemyPop.enemyAddr] or {}).name or '')
				..': '..enemyPop)
		end
		for _,enemySet in ipairs(rs.enemySets) do
			print('   enemySet: '
				..((enemyForAddr[enemySet.enemyAddr] or {}).name or '')
				..': '..enemySet)
		end
		for _,fx1 in ipairs(rs.fx1s) do
			print('   fx1_t '..('$%06x'):format( ffi.cast('uint8_t*',fx1.ptr)-rom )..': '..fx1.ptr[0])
		end
		for _,bg in ipairs(rs.bgs) do
			print('   bg_t '..('$%06x'):format( ffi.cast('uint8_t*',bg.ptr)-rom )..': '..bg.ptr[0])
		end
	end
	for _,ddb in ipairs(m.ddbs) do
		print('  doors: '
			..('$83:%04x'):format(ddb.addr)
			..' '..ddb.ptr[0])
	end
end

-- print/draw rooms
print()
print'all rooms'
for _,room in ipairs(rooms) do
	for _,m in ipairs(room.mdbs) do
		io.write(' '..m.ptr[0].region..'/'..m.ptr[0].index)
	end
	print()

	local function printblock(data, width)
		for i=1,#data do
			io.write((('%02x'):format(tonumber(data[i])):gsub('0','.')))
			if i % width == 0 then print() end 
		end
		print()
	end

	local w,h = room.width, room.height
	local m = room.m
	printblock(room.head, 2) 
	printblock(room.solids, 2*w) 
	printblock(room.bts, w)
	
	drawRoom(m.ptr[0], room.solids, room.bts)
--[=[ write back compressed data
-- ... reduces to 57% of the original compressed data
-- but goes slow

--[==[ do some modifications
	for j=0,h-1 do
		for i=0,w-1 do
			local v = room.bts[1+ i + w * j]
		
--[===[
bit 0 = 2-wide
bit 1 = 2-high
bit 2:3 = 0 = bomb, 1 = shot, 2 = super missile, 3 = power bomb

here's a 2x2 shootable block:
.3ff
ffff

looks like this might be a combination with plms...
--]===]
			
			if false
			--or (v >= 0 and v <= 3) -- bomb
			or (v >= 4 and v <= 7) -- bomb
			or (v >= 8 and v <= 0xb) -- super missile
			or (v >= 0xc and v <= 0xf)	-- powerbomb
			then
				v = 0x8
				room.bts[1+ i + w * j] = v
			end
		end
	end
--]==]
	
	local data = room:getData()
	local recompressed = lz.compress(data)
	print('recompressed size: '..#recompressed..' vs original compressed size '..room.origCompressedSize)
	assert(#recompressed <= room.origCompressedSize, "recompressed to a larger size than the original.  recompressed "..#recompressed.." vs original "..room.origCompressedSize)
totalOriginalCompressedSize = totalOriginalCompressedSize + room.origCompressedSize
	local compressedSize = #recompressed
totalRecompressedSize = totalRecompressedSize + compressedSize
	-- now write back to the original location at addr
	for i,v in ipairs(recompressed) do
		rom[room.addr+i-1] = v
	end
--[==[ verify that compression works by decompressing and re-compressing
	local data2, compressedSize2 = lz.decompress(addr, 0x10000)
	assert(compressedSize == compressedSize2)
	assert(#data == #data2)
	for i=1,#data do
		assert(data[i] == data2[i])
	end
--]==]
--]=]
	
	-- insert this range to see what the newly compressed data takes up	
	--insertUniqueMemoryRange(addr, compressedSize, 'room', m)
end

mapimg:save'map.png'

print()
print('overall recompressed from '..totalOriginalCompressedSize..' to '..totalRecompressedSize..
	', saving '..(totalOriginalCompressedSize - totalRecompressedSize)..' bytes '
	..'(new data is '..math.floor(totalRecompressedSize/totalOriginalCompressedSize*100)..'% of original size)')
