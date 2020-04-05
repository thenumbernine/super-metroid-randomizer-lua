#!/usr/bin/env luajit

--[[
useful pages:
http://wiki.metroidconstruction.com/doku.php?id=super:enemy:list_of_enemies
http://wiki.metroidconstruction.com/doku.php?id=super:technical_information:list_of_enemies
http://metroidconstruction.com/SMMM/
https://gamefaqs.gamespot.com/snes/588741-super-metroid/faqs/39375%22
http://deanyd.net/sm/index.php?title=List_of_rooms
--]]

require 'ext'
function I(...) return ... end
local ffi = require 'ffi'
local config = require 'config'


local cmdline = {}
for i=1,#arg do
	local s = arg[i]
	local j = s:find'=' 
	if j then 
		local k = s:sub(1,j-1)
		local v = s:sub(j+1)
		cmdline[k] = v
	else
		cmdline[s] = true
	end
end
for k,v in pairs(cmdline) do
	if not ({
		seed=1,
		['in']=1,
		out=1,
	})[k] then
		error("got unknown cmdline argument "..k)
	end
end


local seed = cmdline.seed
if seed then
	seed = tonumber(seed, 16)
else
	seed = os.time() 
	math.randomseed(seed)
	for i=1,100 do math.random() end
	seed = math.random(0,0x7fffffff)
end
print('seed', ('%x'):format(seed))
math.randomseed(seed)


local infilename = cmdline['in'] or 'sm.sfc'
local outfilename = cmdline['out'] or 'sm-random.sfc'

function exec(s)
	print('>'..s)
	local results = table.pack(os.execute(s))
	print('results', table.unpack(results, 1, results.n))
	return table.unpack(results, 1, results.n)
end

-- [[ apply patches
file.__tmp = file[infilename]
local function applyPatch(patchfilename)
	exec('luajit ../ips/ips.lua __tmp patches/'..patchfilename..' __tmp2 show')
	file.__tmp = file.__tmp2
	file.__tmp2 = nil
end
if config.skipItemFanfare then applyPatch'itemsounds.ips' end
--applyPatch'SuperMissiles.ips'	-- shoot multiple super missiles!... and it glitched the game when I shot one straight up in the air ...
romstr = file.__tmp
file.__tmp = nil
--]]
--[[
local romstr = file[infilename]
--]]


local header = ''
if bit.band(#romstr, 0x7fff) ~= 0 then
	header = romstr:sub(1,512)
	romstr = romstr:sub(513)
end

-- global so other files can see it
local rom = ffi.cast('uint8_t*', romstr) 


-- global stuff

ffi.cdef[[
typedef uint8_t uint24_t[3];

typedef union {
	uint16_t v;
	struct {
		uint16_t r : 5;
		uint16_t g : 5;
		uint16_t b : 5;
		uint16_t a : 1;
	};
} rgb_t;
]]



function pickRandom(t)
	return t[math.random(#t)]
end

function shuffle(x)
	local y = {}
	while #x > 0 do table.insert(y, table.remove(x, math.random(#x))) end
	while #y > 0 do table.insert(x, table.remove(y, math.random(#y))) end
	return x
end

function tableSubsetsEqual(a,b,i,j,n)
	for k=0,n-1 do
		if a[i+k] ~= b[j+k] then return false end
	end
	return true
end

function tablesAreEqual(a,b)
	if #a ~= #b then return false end
	for i=1,#a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

function byteArraysAreEqual(a,b,len)
	if len == nil then
		len = ffi.sizeof(a)
		if len ~= ffi.sizeof(b) then return false end
	end
	a = ffi.cast('uint8_t*', a)
	b = ffi.cast('uint8_t*', b)
	for i=0,len-1 do
		if a[i] ~= b[i] then return false end
	end
	return true
end

function copyByteArray(dst, src, len)
	if len == nil then
		if type(src) == 'cdata' then
			len = ffi.sizeof(src)
		else
			error'here'
		end
	end
	ffi.copy(dst, src, len)
end

function tableToByteArray(src)
	local dest = ffi.new('uint8_t[?]', #src)
	for i,v in ipairs(src) do
		assert(type(v) == 'number' and v >= 0 and v <= 255)
		dest[i-1] = v
	end
	return dest
end

function byteArrayToTable(src)
	local dest = table()
	for i=1,ffi.sizeof(src) do
		dest[i] = src[i-1]
	end
	return dest
end

function byteArraySubset(src, ofs, len)
	assert(ofs + len <= ffi.sizeof(src))
	local dest = ffi.new('uint8_t[?]', len)
	src = ffi.cast('uint8_t*', src)
	ffi.copy(dest, src + ofs, len)
	return dest
end

function hexStrToByteArray(src)
	local n = #src/2
	assert(n == math.floor(n))
	local dest = ffi.new('uint8_t[?]', n)
	for i=1,n do
		dest[i-1] = tonumber(src:sub(2*i-1, 2*i), 16)
	end
	return dest
end

function byteArrayToHexStr(src, len, sep)
	len = len or ffi.sizeof(src)
	src = ffi.cast('uint8_t*', src)
	local s = ''
	local tsep = ''
	for i=1,len do
		s = s .. tsep..('%02x'):format(src[i-1])
		tsep = sep or ''
	end
	return s
end

function mergeByteArrays(...)
	local srcs = {...}
	local totalSize = 0
	for _,src in ipairs(srcs) do
		totalSize = totalSize + ffi.sizeof(src)
	end
	local dest = ffi.new('uint8_t[?]', totalSize)
	local k = 0
	for _,src in ipairs(srcs) do
		local len = ffi.sizeof(src)
		ffi.copy(dest + k, src, len)
		k = k + len
	end
	assert(k == totalSize)
	return dest
end

-- http://www.metroidconstruction.com/SMMM/index.php?css=black#door-editor
-- http://www.dkc-atlas.com/forum/viewtopic.php?t=1009
-- why is it that some banks need a subtract of 0x8000?
-- it says b4:0000 => 0x1A0000, but the offset doesn't include the 15th bit ... why?
-- the enemy data is really at 0x198000, which would be bank b3 ... what gives?
local banksRequested = table()
function topc(bank, offset)
	assert(offset >= 0 and offset < 0x10000, "got a bad offset for addr $"..('%02x'):format(bank)..':'..('%04x'):format(offset))

--	assert(bit.band(0x8000, offset) ~= 0)

banksRequested[bank] = true 
	-- why only these banks? maybe I should be removing the top bit from the addr?
	if bank == 0xb4 
	or bank == 0x80	
	or bank == 0x83		-- for doors.
	or bank == 0x88
--	or bank == 0x8e 	-- 
	or bank == 0x8f		-- scroll and plm
	or bank == 0x91
	or bank == 0xa1
	or bank == 0xb9 or bank == 0xba	-- both for bg_t
	or (bank >= 0xc2 and bank <= 0xce)	-- room block data
	-- it's not all even banks ...
	--if bit.band(bank, 1) == 0 
	then 
		offset = offset + 0x8000 
	end
	offset = bit.band(offset, 0xffff)
	return bit.lshift(bit.band(bank,0x7f), 15) + offset
end

if config.skipIntro then 
	--applyPatch'introskip_doorflags.ips' 
	copyByteArray(rom + 0x016eda, hexStrToByteArray'1f')
	copyByteArray(rom + 0x010067, hexStrToByteArray'2200ff80')
	copyByteArray(rom + 0x007f00, hexStrToByteArray'af98097ec91f00d024afe2d77ed01eafb6d87e0904008fb6d87eafb2d87e0901008fb2d87eaf52097e22008081a900006b')
end


if config.beefUpXRay then
	local function write(bank, pageofs, newValue, oldValue)
		local addr = topc(bank, pageofs)
		if oldValue ~= nil then
			assert(rom[addr] == oldValue)
		end
		rom[addr] = newValue
	end
	
	-- set max angle to nearly 180' (can't go past that, and can't get it to aim above or below the vertical half-plane.  how to get rid of the vertical limit...
	write(0x88, 0x8792, 0x3f, 0x0b)
	write(0x88, 0x879a, 0x3f, 0x0a)
	-- set angle delta to as fast as possible:
	write(0x88, 0x8770, 0xff, 0x00)
	write(0x88, 0x8771, 0xff, 0x08)
	-- x-ray works in fireflea room
	--write(0x91, 0xd156, 0xea, 0xf0)
	--write(0x91, 0xd157, 0xea, 0x1a)
	-- x-ray works in all rooms (just have 91:d143 immediately return)
	write(0x91, 0xd143, 0x6b, 0xad)

	-- x-ray acts like it is off-screen (and that makes it fill the whole screen)
	write(0x88, 0x8919, 0x11, 0x4b)
	write(0x88, 0x891a, 0xbe, 0xc5)

	-- or better yet, crystal flash (88:8b69) ... doesn't work, but try to figure out how to put a radius of x-ray always around you regardless of pushing 'a' button

	-- make x-ray always on...
	-- freeze-time is stored at 7e:0a78, but it is used in a lot of the detection of whether x-ray is active or not, so just removing code that sets this won't make time continue -- it has side-effects
	-- actually -- fixing it always-on using zsnes causes the x-ray effect to glitch, but while you turn left and right back and forth while using x-ray, enemies will continue to move.  side effects: can't open doors, sometimes freezes.
end


-- [=[ using the ips contents of wake_zebes.ips
-- if I skip writing the plms back then all works fine
if config.wakeZebesEarly then
	
	--wakeZebesEarlyDoorCode = 0xe51f	-- DONT USE THIS - THIS IS WHERE SOME CERES DOOR CODE IS.  right after the last door code
	--wakeZebesEarlyDoorCode = 0xe99b	-- somewhere further out
	wakeZebesEarlyDoorCode = 0xff00		-- original location of the patch.  works.  will re-compressing the plms and tiles affect this?
	
	--patching offset 018eb4 size 0002
	--local i = 0x018eb4	-- change the far right door code to $ff00
	--rom[i] = bit.band(0xff, wakeZebesEarlyDoorCode) i=i+1
	--rom[i] = bit.band(0xff, bit.rshift(wakeZebesEarlyDoorCode, 8)) i=i+1
	
	--patching offset 07ff00 size 0015
	local data = tableToByteArray{
--[[ this is testing whether you have morph
-- morph is item index 26, which is in oct 032, so the 3rd bit on the offset +3 byte 
-- so I'm guessing our item bitflags start at $7e:d86f
-- this only exists because multiple roomStates of the first blue brinstar room have different items
-- the morph item is only in the intro roomstate, so if you wake zebes without getting morph you'll never get it again
-- I'm going to fix this by manually merging the two plmsets of the two roomstates below
		0xaf, 0x72, 0xd8, 0x7e,	-- LDA $7e:d872 
		0x89, 0x00, 0x04,		-- BIT #$0004
		0xf0, 0x0b, 			-- BEQ $0b (to the RTS at the end)
--]]	
		0xaf, 0x20, 0xd8, 0x7e,	-- LDA $7e:d820
		0x09, 0x01, 0x00,		-- ORA #$0001
		0x8f, 0x20, 0xd8, 0x7e, -- STA $7e:d820
		0x60,					-- RTS
	}
	copyByteArray(rom + 0x070000 + wakeZebesEarlyDoorCode, data)
end
--]=]



-- make a single object for the representation of the ROM
-- this way I can call stuff on it -- like making a memory map -- multiple times
local SM = require 'sm'
-- global for now
sm = SM(rom)

-- write out unaltered stuff
if config.writeOutImage then
	sm:mapSaveImage'map'
end
-- http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
sm:buildMemoryMap():print'memorymap.txt'


--[[
for verificaiton: there is one plm per item throughout the game
however some rooms have multiple room states where some roomstates have items and some don't 
... however if ever multiple roomStates have items, they are always stored in the same plmset
and in the case that different roomStates have different items (like the first blue brinstar room, intro roomState has morph, gameplay roomState has powerbomb)
 there is still no duplicating those roomStates.

but here's the problem: a few rooms have roomStates where the item comes and goes
for example, the first blue brinstar room, where the item is morph the first time and powerbomb the second time.
how can we get around this ...
one easy way: merge those two plmsets
how often do we have to merge separate plmsets if we only want to consolidate all items?
	
	this is safe, the item appears after wake-zebes:
00/13 = Crateria former mother brain room, one plmset has nothing, the other has a missile (and space pirates)
	idk when these happen but they are safe
00/15 = Crateria chozo boss, there is a state where there is no bomb item ... 
00/1f = Crateria first missiles after bombs, has a state without the item
	
!!!! here is the one problem child:
01/0e = Brinstar first blue room.  one state has morph, the other has powerbombs (behind the powerbomb wall).
	
	these are safe, the items come back when triggered after killing Phantoon:
03/00 = Wrecked Ship, reserve + missile in one state, not in the other
03/03 = Wrecked Ship, missile in one state, not in the other
03/07 = Wrecked Ship, energy in one state, not in the other (water / chozo holding energy?)
03/0c = Wrecked Ship, super missile in one state, not in the other
03/0d = Wrecked Ship, super missile in one state, not in the other
03/0e = Wrecked Ship, gravty in one state, not in the other

So how do we work around this, keeping a 1-1 copy of all items while not letting the player enter a game state where they can't get an essential item?
By merging the two roomstates of 01/0e together.
What do we have to do in order to merge them?
the two roomstate_t's differ...
- musicTrack: normal has 09, intro has 06
- musicControl: normal has 05, intro has 07
- fx1: normal has 81f4, intro has 8290
- enemySpawn: normal has 9478, intro has 94fb
- enemySet: normal has 83b5, intro has 83d1
- plm: normal has 86c3, intro has 8666 (stupid evil intro plmset that's what screwed everything up ... this is the one i will delete)
- layerHandling: normal has 91bc, intro has 91d5
the two plmsets differ...
- only normal has:
   plm_t: door_grey_left: {cmd=c848, x=01, y=26, args=0c31}
   plm_t: item_powerbomb: {cmd=eee3, x=28, y=2a, args=001a}
- only intro has:
   plm_t: item_morph: {cmd=ef23, x=45, y=29, args=0019}
--]]
-- [[
if config.wakeZebesEarly then
	local m = assert(sm:mapFindRoom(1, 0x0e))
	assert(#m.roomStates == 2)
	local rsNormal = m.roomStates[1]
	local rsIntro = m.roomStates[2]
	rsIntro.obj.musicTrack = rsNormal.obj.musicTrack
	rsIntro.obj.musicControl = rsNormal.obj.musicControl
-- the security cameras stay there, and if I update these then their palette gets messed up
-- but changing this - only for the first time you visit the room - will remove the big sidehoppers from behind the powerbomb wall 
-- however there's no way to get morph + powerbomb all in one go for the first time you're in the room, so I think I'll leave it this way for now
--	rsIntro.obj.fx1Addr = rsNormal.obj.fx1Addr
--	rsIntro.obj.enemySpawnAddr = rsNormal.obj.enemySpawnAddr
--	rsIntro.obj.enemySet = rsNormal.obj.enemySet
	rsIntro.obj.layerHandlingAddr = rsNormal.obj.layerHandlingAddr
	local rsIntroPLMSet = rsIntro.plmset
	rsIntro:setPLMSet(rsNormal.plmset)
	-- TODO remove the rsIntroPLMSet from the list of all PLMSets
	--  notice that, if you do this, you have to reindex all the items plmsetIndexes
	--  also, if you don't do this, then the map write will automatically do it for you, so no worries
	-- now add those last plms into the new plm set
	local lastIntroPLM = rsIntroPLMSet.plms:remove()
	assert(lastIntroPLM.cmd == sm.plmCmdValueForName.item_morph)
	rsNormal.plmset.plms:insert(lastIntroPLM)
	-- and finally, adjust the item randomizer plm indexes and sets
	local _, morphBallItem = sm.items:find(nil, function(item)
		return item.name == 'Morphing Ball'
	end)
	assert(morphBallItem)
	morphBallItem.plmsetIndex = 56	-- same as blue brinstar powerbomb item
	morphBallItem.plmIndex = 19		-- one past the powerbomb
end
--]]



-- [[ manually change the wake condition instead of using the wake_zebes.ips patch
-- hmm sometimes it is only waking up the brinstar rooms, but not the crateria rooms (intro items were super x2, power x1, etank x2, speed)
-- it seems Crateria won't wake up until you get your first missile tank ...
if config.wakeZebesEarly then
	--[=[ 00/00 = first room ... doesn't seem to work
	-- maybe this has to be set only after the player walks through old mother brain room?
	local m = sm:mapFindRoom(0, 0x00)
	for _,door in ipairs(m.doors) do
		door.code = assert(wakeZebesEarlyDoorCode)
	end
	--]=]
	-- [=[ change the lift going down into blue brinstar
	-- hmm, in all cases it seems the change doesn't happen until after you leave the next room
	local m = sm:mapFindRoom(0, 0x14)
	assert(m.doors[2].addr == 0x8b9e)
	m.doors[2].ptr.code = assert(wakeZebesEarlyDoorCode)
	--]=]
	--[=[ 01/0e = blue brinstar first room
	locla m = sm:mapFindRoom(1, 0x0e)
	m.doors[2].ptr.code = assert(wakeZebesEarlyDoorCode)
	--]=]
end
--]]

-- also (only for wake zebes early?) open the grey door from old mother brain so you don't need morph to get back?
do
	local m = sm:mapFindRoom(0, 0x13)
	local rs = m.roomStates[2]	-- sleeping old mother brain
	local plmset = rs.plmset
	local plm = plmset.plms:remove(4)		-- remove the grey door
	assert(plm.cmd == sm.plmCmdValueForName.door_grey_left)
end

-- also while I'm here, lets remove the unfinished/unused rooms
-- notice, when using recursive room building, this skips them anyways
-- [[
sm:mapRemoveRoom(sm:mapFindRoom(2, 0x3d))
sm:mapRemoveRoom(sm:mapFindRoom(7, 0x00))
--]]

--[[ redirect our doors to cut out the toned-down rooms (like the horseshoe shaped room before springball)
local merging424and425 = true
do
	local m4_24 = assert(sm:mapFindRoom(4, 0x24))
	local m4_25 = assert(sm:mapFindRoom(4, 0x25))
	local m4_30 = assert(sm:mapFindRoom(4, 0x30))
	
	-- clear the code on the door in 04/24 that points back to itself?
	local door = assert(m4_24:findDoorTo(m4_24))
	local doorToSelfDoorCode = door.ptr.code
	door.ptr.code = 0
	
	local door = assert(m4_24:findDoorTo(m4_24))
	door.ptr.code = 0
	
	for _,m in ipairs{m4_24, m4_30} do
		-- find the door that points to 4/25, redirect it to 4/24
		local door = assert(m:findDoorTo(m4_25))
		door:setDestRoom(m4_24)
--		door.ptr.code = doorToSelfDoorCode -- this is in the other door that points to itself in this room
		door.ptr.code = 0
		if m == m4_24 then
			assert(door.ptr.screenX == 0)
			assert(door.ptr.screenY == 2)
			door.ptr.screenX = 1
			door.ptr.screenY = 3
			assert(door.ptr.capY == 0x26)
			door.ptr.capY = 0x36
		elseif m == m4_30 then
			assert(door.ptr.screenX == 0)
			assert(door.ptr.screenY == 1)
			door.ptr.screenX = 1
			door.ptr.screenY = 2
		else
			error'here'
		end
	end

	-- change the scroll data of the room from 0 to 1?
	-- if you leave all original then walking through the door from 0,3 to 1,3 messes up the scroll effect
	-- if you change the starting room to 0 then walking into 0,3 messes up the scroll effect
	-- if you set 0,3 to 1 then it works, but you can see the room that you're walking into.
	-- (maybe I should make the door somehow fix the scrolldata when you walk through it?) 
	for _,rs in ipairs(m4_24.roomStates) do
		rs.scrollData[1+1+2*2] = 2
		rs.scrollData[1+1+2*3] = 1
	end
	
	-- and now remove 04/25
	sm:mapRemoveRoom(m4_25)
end
--]]

-- [=[
-- also for the sake of the item randomizer, lets fill in some of those empty room regions with solid
local fillSolidInfo = table{
	--[[
	-- TODO this isn't so straightforward.  looks like filling in the elevators makes them break. 
	-- I might have to just excise regions from the item-scavenger instead
	{1, 0x00, 0,0,16,32+6},			-- brinstar left elevator to crateria.  another option is to make these hollow ...
	{1, 0x0e, 16*5, 0, 16, 32+2},	-- brinstar middle elevator to crateria
	{1, 0x24, 0,0,16,32+6},			-- brinstar right elevator to crateria.
	{1, 0x34, 0,16,16,16},			-- brinstar elevator to norfair / entrance to kraid
	{2, 0x03, 0,0,16,32},			-- brinstar elevator to norfair
	{2, 0x26, 0,16-6,16,6},			-- norfair elevator to lower norfair
	{2, 0x36, 64,0,16,32+6},		-- norfair elevator to lower norfair
	{4, 0x18, 0, 0, 16, 10*16},		-- maridia pipe room
	{5, 0x00, 0,0,16,32},			-- tourian elevator shaft
	--]]
	
	{0, 0x00, 0,0,16,32},			-- crateria first room empty regions
	{0, 0x00, 0,48,16,16},			-- "
	
	{0, 0x1c, 0,7*16-5,16,5},		-- crateria bottom of green pirate room 

	{1, 0x18, 0,16-3,16,3},			-- brinstar first missile room

	{2, 0x48, 2, 3*16-4, 1,1},		-- return from lower norfair spade room
	{2, 0x48, 16-2, 3*16-4, 1,1},	-- "

	{4, 0x04, 29, 11, 3, 3},		-- maridia big room - under top door pillars
	{4, 0x08, 1, 11, 3, 4},			-- maridia next big room - under top door pillars
	{4, 0x08, 5, 13, 1, 4},			-- "
	{4, 0x08, 5*16, 2*16, 16,16},	-- maridia next big room - debug area not fully developed
	{4, 0x0b, 16, 0, 16, 16},		-- maridia top left room to missile and super
	{4, 0x0e, 1,16+3,1,2},			-- maridia crab room before refill
	{4, 0x0e, 14,16+3,1,2},			-- "
	{4, 0x0e, 1,16+11,1,2},			-- "
	{4, 0x0e, 14,16+11,1,2},		-- "
	{4, 0x1a, 4*16-4, 16-5, 4, 4},	-- maridia first sand area pillars under door on right side 
	{4, 0x1b, 0, 32-5, 16, 4},		-- maridia green pipe in the middle pillars underneath
	{4, 0x1c, 0, 16-5, 4, 4},		-- maridia second sand area pillars under door on left side 
	{4, 0x1c, 3*16-4, 16-5, 4, 4},	-- maridia second sand area pillars under door on right side 
	{4, 0x24, 0, 64-5, 4, 4},		-- maridia lower right sand area
	{4, 0x24, 16-4, 64-5, 8, 4},	-- "
	{4, 0x24, 32-4, 64-5, 4, 4},	-- "
	{4, 0x26, 0, 32-5, 32, 5},		-- maridia spring ball room
} 
if not merging424and425 then
	fillSolidInfo:append{
		{4, 0x25, 0, 48-5, 4, 4},		-- you could merge this room into the previous 
		{4, 0x25, 16-4, 48-5, 4, 4},	-- "
	}
end
for _,info in ipairs(fillSolidInfo) do
	local region, index, x1,y1,w,h = table.unpack(info)
	local m = assert(sm:mapFindRoom(region, index))
	local roomBlockData = m.roomStates[1].roomBlockData	-- TODO assert all roomStates have matching rooms?
	for j=0,h-1 do
		local y = y1 + j
		assert(y >= 0 and y < roomBlockData.height)
		for i=0,w-1 do
			local x = x1 + i
			assert(x >= 0 and x < roomBlockData.width)
			local bi = 1 + 3 * (x + roomBlockData.width * y)
			roomBlockData.blocks[bi] = bit.bor(bit.band(roomBlockData.blocks[bi], 0x0f), 0x80)
		end
	end
end
--]=]

-- randomize rooms?  still working on this
-- *) enemy placement
-- *) door placement
-- *) item placement
-- *) refinancin

-- do the enemy field randomization
if config.randomizeEnemies then
	require 'enemies'
end

if config.randomizeWeapons then
	require 'weapons'
end

-- this is just my testbed for map modification code
--require 'rooms'

if config.randomizeDoors then
	require 'doors'	-- still experimental.  this just adds colored doors, but doesn't test for playability.
end

if config.randomizeItems then
	require 'items'
end

if config.randomizeItemsScavengerHunt then
	require 'item-scavenger'
end

do --if config.randomizeDoors or config.randomizeItems or config.wakeZebesEarly then
	-- write back changes
	sm:mapWrite()
end

-- write out altered stuff
sm:print()
if config.writeOutImage then
	sm:mapSaveImage'map-random'
end
sm:buildMemoryMap():print()


-- write back out
file[outfilename] = header .. ffi.string(rom, #romstr)

print('done converting '..infilename..' => '..outfilename)

if not config.randomizeEnemies then
	print()
	print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	print'!!!!!!!!!!! NOT RANDOMIZING ENEMIES !!!!!!!!!'
	print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
end
if not config.randomizeItems and not config.randomizeItemsScavengerHunt then
	print()
	print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	print'!!!!!!!!!!! NOT RANDOMIZING ITEMS !!!!!!!!!!!'
	print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
end
print()

print('banks requested: '..banksRequested:keys():map(function(bank) return ('$%02x'):format(bank) end):concat', ')
