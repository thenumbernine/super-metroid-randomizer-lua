local class = require 'ext.class'

local WriteRange = class()

function WriteRange:init(name, ranges)
	self.name = name
	self.ranges = ranges
	for _,range in ipairs(self.ranges) do
		range.sofar = range[1]
	end
end

function WriteRange:get(len)
	local range = select(2, table.find(self.ranges, nil, function(range)
		return range.sofar + len <= range[2]+1 
	end))
	assert(range, "couldn't find anywhere to write "..self.name)
	local fromaddr = range.sofar
	range.sofar = range.sofar + len
	return fromaddr, range.sofar
end

function WriteRange:print()
	print()
	print(self.name..' write usage:')
	for _,range in ipairs(self.ranges) do
		print('range '
			..('%04x'):format(range[1])..'..'..('%04x'):format(range[2])
			..'  '..('%04x'):format(range.sofar)..' used = '
			..('%.1f'):format(100*(range.sofar-range[1])/(range[2]-range[1]+1))..'% of '
			..('%04x'):format(range[2]-range[1]+1)..' bytes')
	end
end

return WriteRange
