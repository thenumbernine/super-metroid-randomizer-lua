local ffi = require 'ffi'
local config = require 'config'
local struct = require 'struct'
local randomizeEnemyProps = config.randomizeEnemyProps



-- exponentially weighted
local function expRand(min, max)
	local logmin, logmax = math.log(min), math.log(max)
	return math.exp(math.random() * (logmax - logmin) + logmin)
end


local allEnemyFieldValues = {}
for _,field in ipairs{
	'sound',

-- doesn't look so great.
--	'palette',	
	
	-- don't pick from previous values here
	--  because only 0,2,3,4 are used, but 1 is valid
	--'deathEffect',

	--[[ randomize AI?  
	-- maybe only for certain monsters ... among only certain values ...
	-- just doing everything causes it to freeze very often
	'aiBank',
	'initiationAI',
	'mainAI',
	'grappleAI',
	'hurtAI',
	'frozenAI',
	'xrayAI',
	--]]

} do
	if randomizeEnemyProps[field] then
		allEnemyFieldValues[field] = allEnemyFieldValues[field] or {
			distr = {},
		}
		local values = allEnemyFieldValues[field]
		for _,enemy in ipairs(sm.enemies) do
			local value = enemy.ptr[0][field]
			values.distr[value] = (values.distr[value] or 0) + 1
		end
		values.values = table.keys(values.distr):sort()
		--[[ TODO print distribution *after* randomization
		print('enemy '..field..' distribution:')
		for _,value in ipairs(values.values) do
			print('  '..value..' x'..values.distr[value])
		end
		--]]
	end
end

local typeinfo = {
	uint8_t = {range={0,0xff}},
	uint16_t = {range={0,0xffff}},
}

local function randomizeFieldExp(enemyPtr, fieldname)
	if randomizeEnemyProps[fieldname] then
		local value = expRand(table.unpack(randomizeEnemyProps[fieldname..'ScaleRange'])) * enemyPtr[0][fieldname]
		local field = select(2, enemy_t_fields:find(nil, function(field) return next(field) == fieldname end))
		local fieldtype = select(2, next(field))
		local fieldrange = typeinfo[fieldtype].range
		value = math.clamp(value, fieldrange[1], fieldrange[2])
		enemyPtr[0][fieldname] = value
	end
end



-- do the randomizing

if config.randomizeEnemies then
	sm.enemyItemDropTable:randomize()
	sm.enemyWeaknessTable:randomize()

-- [[ still working on this ...
	if randomizeEnemyProps.palette then
		print()
		print'palettes:'
		-- 1) gather unique palette addrs
		local addrs = sm.enemies:map(function(enemy)
			return true, topc(enemy.ptr.aiBank, enemy.ptr.palette)
		end):keys()
		-- 2) get the rgb data
		-- permute them in some way. rotation around (1,1,1) axis or something
		for _,addr in ipairs(addrs) do
			print('addr: '..('0x%06x'):format(addr))
			local rgb = ffi.cast('rgb_t*', rom + addr)
			for i=0,15 do
				print(' '..rgb[0].a
					..' '..rgb[0].r
					..' '..rgb[0].g
					..' '..rgb[0].b)
			
-- this is crashing us ... hmm ... 
--rgb[0].r, rgb[0].g, rgb[0].b = rgb[0].g, rgb[0].b, rgb[0].r
				
				rgb = rgb + 1
			end
		end
	end
--]]

	for i,enemy in ipairs(sm.enemies) do
		randomizeFieldExp(enemy.ptr, 'health')
		randomizeFieldExp(enemy.ptr, 'damage')
		randomizeFieldExp(enemy.ptr, 'hurtTime')
		
		if randomizeEnemyProps.deathEffect then
			enemy.ptr.deathEffect = math.random(0,4)
		end

		for field,values in pairs(allEnemyFieldValues) do
			if randomizeEnemyProps[field] then
				enemy.ptr[0][field] = pickRandom(values.values)
			end
		end

		sm.enemyWeaknessTable:randomizeEnemy(enemy)
		sm.enemyItemDropTable:randomizeEnemy(enemy)
	end

	if randomizeEnemyProps.shotDamage then
		for _,shot in ipairs(sm.enemyShots) do
			local value = shot.ptr.damageAndFlags
			local flags = bit.band(0xf000, value)
			local damage = bit.band(0xfff, value)
			damage = expRand(table.unpack(randomizeEnemyProps.shotDamageScaleRange)) * damage
			damage = math.clamp(damage, 0, 0xfff)
			shot.ptr.damageAndFlags = bit.bor(damage, flags)
		end
	end
end


-- do the printing


sm.enemyItemDropTable:print()
sm.enemyWeaknessTable:print()

print'enemies:'
for i,enemy in ipairs(sm.enemies) do
	print(('0x%04x'):format(enemy.addr)..': '..enemy.name)

	print(' tileDataSize='..('0x%04x'):format(enemy.ptr.tileDataSize))
	
	print(' palette='
		..('$%02x'):format(enemy.ptr.aiBank)
		..(':%04x'):format(enemy.ptr.palette))
--	local ptr = rom + topc(enemy.ptr.aiBank, enemy.ptr.palette)
--	local str = ffi.string(ptr, 32)
--	print('  '..str:gsub('.', function(c) return ('%02x '):format(c:byte()) end))

	for _,field in ipairs{'health', 'damage', 'hurtTime', 'bossValue'} do
		print(' '..field..'='..enemy.ptr[0][field])
	end

	print(' deathEffect='..enemy.ptr.deathEffect)
	
	for field,values in pairs(allEnemyFieldValues) do
		print(' '..field..'='..('0x%x'):format(enemy.ptr[0][field]))
	end
	
	sm.enemyWeaknessTable:printEnemy(enemy)
	sm.enemyItemDropTable:printEnemy(enemy)
	
	io.write(' debug name: '
		..('0x%04x'):format(enemy.ptr.name))
	if enemy.ptr.name ~= 0 then
		local addr = topc(0xb4, enemy.ptr.name)
		local len = 10
		local betaname = ffi.string(rom + addr, len)
		insertUniqueMemoryRange(addr, len+4, 'debug name')
		io.write(': '..betaname)
		--io.write(' / '..betaname:gsub('.', function(c) return ('%02x '):format(c:byte()) end)
	end
	print()

end


print'enemy shot table:'
for _,shot in ipairs(sm.enemyShots) do
	print(shot.addr, shot.ptr[0])
end
