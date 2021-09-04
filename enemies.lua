local ffi = require 'ffi'
local config = require 'config'
local struct = require 'struct'
local expRand = require 'exprand'
local randomizeEnemyProps = config.randomizeEnemyProps
local topc = require 'pc'.to

local typeinfo = {
	uint8_t = {range={0,0xff}},
	uint16_t = {range={0,0xffff}},
}

local function randomizeFieldExp(enemyPtr, fieldname)
	if randomizeEnemyProps[fieldname] then
		local value = expRand(table.unpack(randomizeEnemyProps[fieldname..'ScaleRange'])) * enemyPtr[0][fieldname]
		local field = select(2, enemyClass_t_fields:find(nil, function(field) return next(field) == fieldname end))
		local fieldtype = select(2, next(field))
		local fieldrange = typeinfo[fieldtype].range
		value = math.clamp(value, fieldrange[1], fieldrange[2])
		enemyPtr[0][fieldname] = value
	end
end



-- do the randomizing

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
		local rgb = ffi.cast('rgb_t*', sm.rom + addr)
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

	for field,values in pairs(sm.allEnemyFieldValues) do
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
