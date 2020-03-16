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


-- [[ apply patches
file.__tmp = file[infilename]
local function applyPatch(patchfilename)
	local results = {os.execute('luajit ../ips/ips.lua __tmp patches/'..patchfilename..' __tmp2')}
	print('results', table.unpack(results))
	file.__tmp = file.__tmp2
	file.__tmp2 = nil
end
if config.skipIntro then applyPatch'introskip_doorflags.ips' end

-- using the wake_zebes.ips patch
--if config.wakeZebesEarly then applyPatch'wake_zebes.ips' end

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
	
	--wakeZebesEarlyDoorCode = 0xe51f		-- DONT USE THIS - THIS IS WHERE SOME CERES DOOR CODE IS.  right after the last door code
	--wakeZebesEarlyDoorCode = 0xe99b	-- somewhere further out
	wakeZebesEarlyDoorCode = 0xff00	-- original location.  works as long as I don't re-compress the plms and tiles.
	
	--patching offset 018eb4 size 0002
	--local i = 0x018eb4	-- change the far right door code to $ff00
	--rom[i] = bit.band(0xff, wakeZebesEarlyDoorCode) i=i+1
	--rom[i] = bit.band(0xff, bit.rshift(wakeZebesEarlyDoorCode, 8)) i=i+1
	
	--patching offset 07ff00 size 0015
	local data = tableToByteArray{
		0xaf, 0x72, 0xd8, 0x7e,	-- LDA $7e:d872 
		0x89, 0x00, 0x04,		-- BIT #$0004
		0xf0, 0x0b, 			-- BEQ $0b (to the RTS at the end)
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
	sm:mapSaveImage'map.png'
end
-- http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
sm:buildMemoryMap():print'memorymap.txt'


-- [[ manually change the wake condition instead of using the wake_zebes.ips patch
for _,m in ipairs(sm.mdbs) do
	-- [=[ 01/0e = blue brinstar first room
	if m.ptr.index == 0x0e
	and m.ptr.region == 0x01
	then
		-- change the 2nd door
		assert(m.doors[2].addr == 0x8eaa)
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

if config.randomizeDoors then
	require 'rooms'
end

-- do the item randomization. this is the in-place randomization algorithm
if config.randomizeItems then
	require 'items'
end

-- writing back is screwing up the wakeZebesEarly stuff
do --if config.randomizeDoors or config.randomizeItems then
	-- write back changes
	sm:mapWrite()
end

-- write out altered stuff
sm:print()
if config.writeOutImage then
	sm:mapSaveImage'map-random.png'
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
