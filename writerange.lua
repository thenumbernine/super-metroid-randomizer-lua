local class = require 'ext.class'
local table = require 'ext.table'

-- [inclusive,exclusive), [start,end), or [addr,addr+len-1)
local Interval = class()

function Interval:init(start, finish)
	self[1] = start
	self[2] = finish
end

function Interval.contains(a,b)
	return b[1] >= a[1] and b[2] <= a[2]
end

function Interval:containsPt(b)
	return self[1] <= b and b < self[2]
end

function Interval.touches(a,b)
	return a[2] > b[1] and a[1] < b[2]
end

function Interval:__tostring()
	return ('[$%06x, $%06x)'):format(self[1], self[2])
end


local WriteRange = class()

function WriteRange:init(ranges, name)
	ranges = table(ranges)
	-- [[
	-- merge congruent ranges ... ?
	-- or is this a bad idea due to a need to prevent writes across banks
	-- or sholud I prevent that through a seprate flag?
	for i=#ranges-1,1,-1 do
		if ranges[i][2] == ranges[i+1][1] then
			ranges[i][2] = ranges[i+1][2]
			table.remove(ranges, i+1)
		end
	end
	--]]
	self.ranges = table.mapi(ranges, function(range)
		return Interval(range[1], range[2])
	end)
	self.sofar = self.ranges:mapi(function(range)
		return Interval(range[1], range[1])
	end)
	-- optional
	self.name = name or 'mem'
end

function WriteRange:get(len, addr)
	if addr then
		local int = Interval(addr, addr+len)
		local i=0
		while true do
			i=i+1
			if i > #self.ranges then break end
			-- if [addr,addr+len) intersects the [sofar[1], sofar[2]) interval then fail
			if int:touches(self.sofar[i]) then
				error("tried to request a range that was already used\n"
					..'req: '..int..'\n'
					..'used: '..self.sofar[i])
			end
			if int:contains(self.ranges[i]) then
				self.ranges:remove(i)
				i = i - 1
			elseif int:containsPt(self.ranges[i][1]) then
				-- if [addr,addr+len) contains region[1] then push region[1] forward
				assert(self.sofar[i][1] == self.ranges[i][1])	-- assert our sofar hasn't been moved
				self.ranges[i][1] = int[2]
				self.sofar[i][1] = int[2]
			elseif int:containsPt(self.ranges[i][2]) then
				-- if [addr,addr+len) contains region[2]-1 then push region[2] back
				self.ranges[i][2] = int[1]
			elseif self.ranges[i]:contains(int) then
				-- if [region[1],region[2]+1) contains [addr,addr+len) then split it
				self.ranges:insert(i+1, Interval(int[2], self.ranges[i][2]))
				self.sofar:insert(i+1, Interval(int[2], int[2]))
				self.ranges[i][2] = int[1]
				i = i + 1
			end
		end
		return table.unpack(int)
	end
	local range, sofar
	for i=1,#self.ranges do
		if self.sofar[i][2] + len <= self.ranges[i][2] then
			range = self.ranges[i]
			sofar = self.sofar[i]
			break
		end
	end
	assert(range, "couldn't find anywhere to write "..self.name)
	local fromaddr = sofar[2]
	sofar[2] = sofar[2] + len
	return fromaddr, sofar[2]
end

function WriteRange:print()
	print()
	print(self.name..' write usage:')
	for i,range in ipairs(self.ranges) do
		local sofar = self.sofar[i]
		print('range '
			..('%04x'):format(range[1])..'..'..('%04x'):format(range[2])
			..'  '..('%04x'):format(sofar[2])..' used = '
			..('%.1f'):format(100*(sofar[2]-range[1])/(range[2]-range[1]))..'% of '
			..('%04x'):format(range[2]-range[1])..' bytes')
	end
end

return WriteRange
