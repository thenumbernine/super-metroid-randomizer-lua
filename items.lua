-- items are from 0781cc to 079184, then from 07c265 to 07c7a7  
-- but both of these ranges overlap dooraddrs ... hmm ...
-- [[

local ffi = require 'ffi'
local config = require 'config'
local playerSkills = config.playerSkills


--[[
sm.items:sort(function(a,b) return a.addr < b.addr end)
print('item addrs')
for _,item in ipairs(sm.items) do
	print((' %06x'):format(item.addr)..' = '..('%04x'):format(item.ptr[0]))
end
print()
os.exit()
--]]



--[[
TODO prioritize placement of certain items last.
especially those that require certain items to escape from.
1) the super missile tank behind spore spawn that requires super missiles.  place that one last, or not at all, or else it will cause an early super missile placement.
2) plasma beam, will require a plasma beam placement
3) spring bill will require a grappling placement
4) pink Brinstar e-tank will require a wave placement
5) space jump requires space jump ... I guess lower norfair also does, if you don't know the suitless touch-and-go in the lava trick
... or another way to look at this ...
... choose item placement based on what the *least* number of future possibilities will be (i.e. lean away from placing items that open up the game quicker)
--]]

-- weighted shuffle, p[i] is the weight of x[i]
local function weightedShuffle(x, p)
	x = table(x)
	p = table(p)
	local y = table()
	while #x > 0 do
		local r = math.random() * p:sum()
		for i=1,#x do
			r = r - p[i]
			if r <= 0 then
				y:insert(x:remove(i))
				p:remove(i)
				break
			end
		end
	end
	return y
end



-- [[ reveal all items
for _,item in ipairs(sm.items) do
	local name = sm.itemTypeNameForValue[item.ptr[0]]

	-- save it as a flag for later -- whether this used to be chozo or hidden
	item.isChozo = not not name:match'_chozo$' 
	item.isHidden = not not name:match'_hidden$' 
	-- remove all chozo and hidden status
	name = name:gsub('_chozo', ''):gsub('_hidden', '')	

	-- write back our change
	item.ptr[0] = sm.itemTypes[name]
end
--]]

print('found '..#sm.items..' items')


--[[
changes around the original values that are to be randomized
in case you want to try a lean run, with less items, or something
args:
	changes = {[from type] => [to type]} key/value pairs
	args = extra args:
		leave = how many to leave
--]]
local function change(from, to, leave)
	local found = sm.items:filter(function(item) 
		return itemTypeNameForValue[item.ptr[0]]:match('^'..from) 
	end)
	if leave then
		for i=1,leave do
			if #found == 0 then break end
			found:remove(math.random(#found))	-- leave as many as the caller wants
		end
	end
	for _,item in ipairs(found) do 
		item.ptr[0] = sm.itemTypes[to] 
	end
end

local function removeItem(itemName, withType)
	local item = assert(sm.itemsForName[itemName], "couldn't find item "..itemName)
	item.ptr[0] = sm.itemTypes[withType]
	
	sm.items:removeObject(item)
	sm.itemsForName[itemName] = nil
end

-- process item changes
for _,entry in ipairs(config.itemChanges or {}) do
	if entry.from and entry.to then 
		assert(not entry.remove)
		change(entry.from, entry.to, entry.leave) 
	elseif entry.remove and entry.to then
		assert(not entry.from)
		removeItem(entry.remove, entry.to)
	end
end

-- [[ placement algorithm:


-- defined above so item constraints can see it 
req = {}

-- deep copy, so the orginal items is intact
local origItemValues = sm.items:map(function(item) return item.ptr[0] end)
-- feel free to modify origItemValues to your hearts content ... like replacing all reserve tanks with missiles, etc
-- I guess I'm doing this above alread with the change() and removeItem() functions


-- keep track of the remaining items to place -- via indexes into the original array
local itemValueIndexesLeft = range(#origItemValues)

local currentItems = table(sm.items)

for _,item in ipairs(sm.items) do
	local value = item.ptr[0]
	item.defaultTypeName = sm.itemTypeNameForValue[sm.itemTypeBaseForType[value]]
end

local replaceMap = {}

local function iterate(depth)
	depth = depth or 0
	local function dprint(...)
		io.write(('%3d%% '):format(depth))
		return print(...)
	end

	if #currentItems == 0 then
		dprint'done!'
		return true
	end

	local chooseLocs = currentItems:filter(function(loc)
		return loc.access()
	end)
	dprint('options to replace: '..tolua(chooseLocs:map(function(loc,i,t) return (t[loc.defaultTypeName] or 0) + 1, loc.defaultTypeName end)))

	-- pick an item to replace
	if #chooseLocs == 0 then 
		dprint('we ran out of options with '..#currentItems..' items unplaced! '..tolua(currentItems:map(function(loc,i,t) return (t[loc.defaultTypeName] or 0)+1, loc.defaultTypeName end)))
		return
	end
	local chooseItem = chooseLocs[math.random(#chooseLocs)]
	dprint('choosing to replace '..chooseItem.name)
	
	-- remove it from the currentItems list 
	local nextItems = currentItems:filter(function(loc) return chooseItem ~= loc end)
	
	-- find an item to replace it with
	if #itemValueIndexesLeft == 0 then 
		dprint('we have no items left to replace it with!')
		os.exit(1)
	end

	-- weighted shuffle, higher priorities placed at the beginning
	local function probability(i)
		if not config.itemPlacementProbability then return 1 end
		return config.itemPlacementProbability[sm.itemTypeNameForValue[origItemValues[itemValueIndexesLeft[i]]]] or 1
	end
	local is = range(#itemValueIndexesLeft)
	for _,i in ipairs(weightedShuffle(is, is:map(probability))) do
		local push_itemValueIndexesLeft = table(itemValueIndexesLeft)
		local replaceInstIndex = itemValueIndexesLeft:remove(i)
		
		local value = origItemValues[replaceInstIndex]
		local name = sm.itemTypeNameForValue[value]
		
		if not chooseItem.filter
		or chooseItem.filter(name)
		then
			dprint('...replacing '..chooseItem.name..' with '..name)
					
			-- plan to write it 
			replaceMap[chooseItem.addr] = {value=value, req=table(req)}
		
			-- now replace it with an item
			local push_req = setmetatable(table(req), nil)
			req[name] = (req[name] or 0) + 1
		
			local push_currentItems = table(currentItems)
			currentItems = nextItems

			-- if the chooseItem has an escape req, and it isn't satisfied, then don't iterate
			if chooseItem.escape and not chooseItem.escape() then
				dprint('...escape condition not met!')
			else
				dprint('iterating...')
				if iterate(depth + 1) then return true end	-- return 'true' when finished to exit out of all recursion
			end
			
			currentItems = push_currentItems
			req = push_req
		end
		itemValueIndexesLeft = push_itemValueIndexesLeft
	end
end	

iterate()


print()
print()
print'summary:'
local longestName = sm.items:map(function(item) return #item.name end):sup()
-- sort by # of constraints, so first item expected to get is listed first
local function score(item)
	return table.values(replaceMap[item.addr].req):sum() or 0
end
table(sm.items):sort(function(a,b) 
	return score(a) < score(b) 
end):map(function(item)
	local addr = item.addr
	local value = replaceMap[addr].value
	local req = replaceMap[addr].req
	print(item.name
		..('.'):rep(longestName - #item.name + 10)
		..sm.itemTypeNameForValue[value]
		..'\t'..tolua(req))
	
	-- do the writing:
	item.ptr[0] = value
end)

--[[
todo generalize this to arbitrary obstacles: 
fixed obstacles like vertical areas that cannot be re-rolled
randomizeable obstacles like blocked walls, doors, grey doors + enemy weaknesses, items
--]]
