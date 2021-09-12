local class = require 'ext.class'
local table = require 'ext.table'
local pc = require 'pc'

local MemoryMap = class()

function MemoryMap:init()
	self.ranges = table()
end

function MemoryMap:add(addr, len, name, room, ...)
	if not self.ranges:find(nil, function(range)
		return range.addr == addr and range.len == len and range.name == name
	end) then
		self.ranges:insert{
			addr = assert(addr), 
			len = len, 
			name = name, 
			room = room,
			...
		}
	end
end

function MemoryMap:print(filename)
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
		and ra.room == rb.room
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

	local f = filename 
		and assert(io.open(filename, 'w'))
		or io.stdout
	
	f:write('    memory ranges:\n')
	f:write('map region/index: addr $start-$end (desc) ... trailing bytes until next region ...')	
	for i,range in ipairs(ranges) do
		local prevRange
		if i>1 then
			prevRange = ranges[i-1]
			local padding = range.addr - (prevRange.addr + prevRange.len)
			if padding ~= 0 then
				f:write(' ... '..padding..' bytes of padding ...')
			end
		end
		f:write'\n'
		if prevRange and bit.rshift(prevRange.addr, 15) ~= bit.rshift(range.addr, 15) then
			f:write'--------------\n'
		end
		
		local room = range.room
		if room then
			f:write(('%02x/%02x'):format(room:obj().region, room:obj().index))
		else
			f:write('     ')
		end
		f:write(': '..('$%06x'):format(range.addr)..'..'..('$%06x'):format(range.addr+range.len-1))
		f:write(' : '..('$%02x:%04x'):format(pc.from(range.addr))..'..'..('$%02x:%04x'):format(pc.from(range.addr+range.len-1)))
		f:write(' ('..range.name..')')
	end
	f:write(' ('..ranges:last().name..')\n')
	if filename then
		f:close()
	end
end

return MemoryMap
