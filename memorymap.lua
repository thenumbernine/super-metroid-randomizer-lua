local class = require 'ext.class'
local table = require 'ext.table'

local MemoryMap = class()

function MemoryMap:init()
	self.ranges = table()
end

function MemoryMap:add(addr, len, name, m, ...)
	if not self.ranges:find(nil, function(range)
		return range.addr == addr and range.len == len and range.name == name
	end) then
		self.ranges:insert{addr=addr, len=len, name=name, m=m, ...}
	end
end

function MemoryMap:print()
	local ranges = self.ranges
	ranges:sort(function(a,b)
		return a.addr < b.addr
	end)
	
	-- [[ combine ranges
	for i=#ranges-1,1,-1 do
		local ra = ranges[i]
		local rb = ranges[i+1]
		if ra.addr + ra.len == rb.addr
		and ra.name == rb.name
		then
			ra.len = ra.len + rb.len
			ra.dup = (ra.dup or 1) + (rb.dup or 1)
			ranges:remove(i+1)
		end
	end
	for _,range in ipairs(ranges) do
		if range.dup then
			range.name = range.name..' x'..range.dup
		end
	end
	--]]

	local f = assert(io.open('memorymap.txt', 'w'))
	local function fwrite(...)
		f:write(...)
		io.write(...)
	end
	fwrite('    memory ranges:\n')
	fwrite('mdb region/index: addr $start-$end (desc) ... trailing bytes until next region ...')	
	for i,range in ipairs(ranges) do
		local prevRange
		if i>1 then
			prevRange = ranges[i-1]
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
				('%02x'):format(tonumber(m.ptr.region))..'/'..
				('%02x'):format(tonumber(m.ptr.index)))
		else
			fwrite('     ')
		end
		fwrite(': '..('$%06x'):format(range.addr)..'..'..('$%06x'):format(range.addr+range.len-1))
		fwrite(' ('..range.name..') ')
	end
	fwrite(' ('..ranges:last().name..')\n')
	f:close()
end

return MemoryMap
