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
	exec('luajit ../ips/ips.lua __tmp patches/'..patchfilename..' __tmp2')
	file.__tmp = file.__tmp2
	file.__tmp2 = nil
end
if config.skipIntro then applyPatch'introskip_doorflags.ips' end
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

function mergeByteArrays(...)
	local srcs = {...}
	local totalSize = 0
	for _,src in ipairs(srcs) do
		totalSize = totalSize + ffi.sizeof(src)
	end
	local dest = ffi.new('uint8_t[?]', totalSize)
	local k = 0
	for _,src in ipairs(srcs) do
		ffi.copy(dest + k, src, ffi.sizeof(src))
		k = k + ffi.sizeof(src)
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
	-- why only these banks?
	if bank == 0xb4 
	or bank == 0x83		-- for doors.
--	or bank == 0x8e 	-- map mdb's, roomstate's, door tables.  nope, not this one
	or bank == 0x8f		-- scroll and plm
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



-- [=[ using the ips contents of wake_zebes.ips
-- if I skip writing the plms back then all works fine
if config.wakeZebesEarly then
	
	--wakeZebesEarlyDoorCode = 0xe51f	-- DONT USE THIS - THIS IS WHERE SOME CERES DOOR CODE IS.  right after the last door code
	--wakeZebesEarlyDoorCode = 0xe99b	-- somewhere further out
	wakeZebesEarlyDoorCode = 0xff00		-- original location of the patch.  works as long as I don't re-compress the plms and tiles.
	
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
	ffi.copy(rom + 0x070000 + wakeZebesEarlyDoorCode, data, ffi.sizeof(data))
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
- enemyPop: normal has 9478, intro has 94fb
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
	-- find mdb 01/0e, find its plmset
	local _,m = sm.mdbs:find(nil, function(m)
		return m.ptr.index == 0x0e and m.ptr.region == 0x01
	end)
	if not m then error'here' end
	assert(#m.roomStates == 2)
	local rsNormal = m.roomStates[1]
	local rsIntro = m.roomStates[2]
	rsIntro.ptr.musicTrack = rsNormal.ptr.musicTrack
	rsIntro.ptr.musicControl = rsNormal.ptr.musicControl
-- the security cameras stay there, and if I update these then their palette gets messed up
-- but changing this - only for the first time you visit the room - will remove the big sidehoppers from behind the powerbomb wall 
-- however there's no way to get morph + powerbomb all in one go for the first time you're in the room, so I think I'll leave it this way for now
--	rsIntro.ptr.fx1 = rsNormal.ptr.fx1
--	rsIntro.ptr.enemyPop = rsNormal.ptr.enemyPop
--	rsIntro.ptr.enemySet = rsNormal.ptr.enemySet
	rsIntro.ptr.layerHandling = rsNormal.ptr.layerHandling
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
	for _,m in ipairs(sm.mdbs) do
		--[=[ 01/0e = blue brinstar first room
		if m.ptr.index == 0x0e
		and m.ptr.region == 0x01
		then
			m.doors[2].ptr.code = assert(wakeZebesEarlyDoorCode)
		end
		--]=]
		-- [=[ change the lift going down into blue brinstar
		-- hmm, in all cases it seems the change doesn't happen until after you leave the next room
		if m.ptr.index == 0x14
		and m.ptr.region == 0x00
		then
			assert(m.doors[2].addr == 0x8b9e)
			m.doors[2].ptr.code = assert(wakeZebesEarlyDoorCode)
		end
		--]=]
		--[=[ 00/00 = first room ... doesn't seem to work
		if m.ptr.index == 0x00
		and m.ptr.region == 0x00
		then
			for _,door in ipairs(m.doors) do
				door.code = assert(wakeZebesEarlyDoorCode)
			end
		end
		--]=]
	end
end
--]]


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
if not config.randomizeItems then
	print()
	print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	print'!!!!!!!!!!! NOT RANDOMIZING ITEMS !!!!!!!!!!!'
	print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
end
print()

print('banks requested: '..banksRequested:keys():map(function(bank) return ('$%02x'):format(bank) end):concat', ')
