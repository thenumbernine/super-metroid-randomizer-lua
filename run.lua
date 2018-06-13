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


local romstr = file[infilename]
local header = ''
--header = romstr:sub(1,512)
--romstr = romstr:sub(513)

-- global so enemies.lua can see it
rom = ffi.cast('uint8_t*', romstr) 

local config = require 'config'

-- do the enemy randomization
if config.randomizeEnemies then
	require 'enemies'(rom)
end

-- do the item randomization
if config.randomizeItems then
	require 'items'(rom)
end

-- write back out
file[outfilename] = header .. ffi.string(rom, #romstr)

print('done converting '..infilename..' => '..outfilename)
