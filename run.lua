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
local romstr = file.__tmp
file.__tmp = nil
--]]
--[[
local romstr = file[infilename]
--]]

local header = ''
--header = romstr:sub(1,512)
--romstr = romstr:sub(513)

-- global so other files can see it
rom = ffi.cast('uint8_t*', romstr) 


-- global stuff

ffi.cdef[[
typedef uint8_t uint24_t[3];
]]

function pickRandom(t)
	return t[math.random(#t)]
end



-- http://www.metroidconstruction.com/SMMM/index.php?css=black#door-editor
function bank(i)
	return ({
		[0x83] = 0x018000,
		[0x86] = 0x030000,
		[0x8e] = 0x070000,
		[0x8f] = 0x078000,
		[0x9f] = 0x0f8000,
		[0xa1] = 0x108000,
		[0xb4] = 0x198000,
	})[i] or error("need bank "..('%02x'):format(i))
end


-- build enemies table / type info
-- do this before rooms, enemies, items
require 'enemies_data'

-- randomize rooms?  still working on this
-- *) enemy placement
-- *) door placement
-- *) refinancin
--require 'rooms'
--os.exit()

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
