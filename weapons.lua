local expRand = require 'exprand'
local config = require 'config'

print()
print'weapon damages:'
for _,addr in ipairs(sm.weaponDamageForAddr:keys():sort()) do
	local dmg = sm.weaponDamageForAddr[addr]
	local name = dmg.name
	local ptr = dmg.ptr
	local damage = ptr[0]
	damage = expRand(table.unpack(config.randomizeWeaponProps.weaponDamageScaleRange)) * damage
	ptr[0] = damage
	print(('$%06x'):format(addr)..' = '..('%04x'):format(ptr[0])..' '..name)
end
