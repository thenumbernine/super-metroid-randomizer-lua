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
	local results = {os.execute('../ips/ips.lua __tmp patches/'..patchfilename..' __tmp2')}
	print('results', table.unpack(results))
	file.__tmp = file.__tmp2
	file.__tmp2 = nil
end
if config.skipIntro then applyPatch'introskip_doorflags.ips' end
if config.wakeZebesEarly then applyPatch'wake_zebes.ips' end
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
rom = ffi.cast('uint8_t*', romstr) 


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


memoryRanges = table()
function insertUniqueMemoryRange(addr, len, name, m, ...)
	if not memoryRanges:find(nil, function(range)
		return range.addr == addr and range.len == len and range.name == name
	end) then
		memoryRanges:insert{addr=addr, len=len, name=name, m=m, ...}
	end
end



local name = ffi.string(rom + 0x7fc0, 0x15)
print(name)


-- build enemies table / type info
-- do this before rooms, enemies, items
require 'enemies_data'

-- randomize rooms?  still working on this
-- *) enemy placement
-- *) door placement
-- *) refinancin
require 'rooms'

-- do the enemy randomization
require 'enemies'

-- do the item randomization
if config.randomizeItems then
	require 'items'
end

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
	print'!!!!!!!!!!!! NOT RANDOMIZING IEMS !!!!!!!!!!!'
	print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
end

do
	memoryRanges:sort(function(a,b)
		return a.addr < b.addr
	end)
	
	-- combine ranges
	for i=#memoryRanges-1,1,-1 do
		local ra = memoryRanges[i]
		local rb = memoryRanges[i+1]
		if ra.addr + ra.len == rb.addr
		and ra.name == rb.name
		then
			ra.len = ra.len + rb.len
			ra.dup = (ra.dup or 1) + (rb.dup or 1)
			memoryRanges:remove(i+1)
		end
	end
	for _,range in ipairs(memoryRanges) do
		if range.dup then
			range.name = range.name..' x'..range.dup
		end
	end

	local f = assert(io.open('memorymap.txt', 'w'))
	local function fwrite(...)
		f:write(...)
		io.write(...)
	end
	fwrite('memory ranges:')
	for i,range in ipairs(memoryRanges) do
		local prevRange
		if i>1 then
			local prevname = range.name
			fwrite(' ('..prevname..') ')
			prevRange = memoryRanges[i-1]
			local padding = range.addr - (prevRange.addr + prevRange.len)
			if padding ~= 0 then
				fwrite('... '..padding..' bytes of padding ...')
			end
		end
		fwrite'\n'
		if prevRange and bit.band(prevRange.addr, 0x7f8000) ~= bit.band(range.addr, 0x7f8000) then
			fwrite'--------------\n'
		end
		
		local m = range.m
		if m then
			fwrite( 
				('%2d'):format(tonumber(m.ptr[0].region))..'/'..
				('%2d'):format(tonumber(m.ptr[0].index)))
		else
			fwrite('     ')
		end
		fwrite(': '..('$%06x'):format(range.addr)..'-'..('$%06x'):format(range.addr+range.len-1))
	end
	fwrite(' ('..memoryRanges:last().name..')\n')
	f:close()
end


print('banks requested: '..banksRequested:keys():map(function(bank) return ('$%02x'):format(bank) end):concat', ')
