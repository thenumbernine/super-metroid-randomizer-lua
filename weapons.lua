-- https://jathys.zophar.net/supermetroid/kejardon/EnemyResistence.txt
local ffi = require 'ffi'
local table = require 'ext.table'
local rom = sm.rom

local damageAddrs = table{
	normal = 0x98431,
	wave = 0x984b5,
	ice = 0x9849f,
	wave_ice = 0x984e1,
	spazer = 0x98447,
	spazer_wave = 0x984f7,
	spazer_ice = 0x9845d,
	spazer_wave_ice = 0x98473,
	plasma = 0x984cb,
	plasma_wave = 0x9850d,
	plasma_ice = 0x98523,
	plasma_wave_ice = 0x98489,
	plasma_spazer = 0x98539,
	plasma_spazer_wave = 0x985d3,
	plasma_spazer_ice = 0x985a7,
	plasma_spazer_wave_ice = 0x985e9,
	charge_normal = 0x98539,
	charge_wave = 0x985d3,
	charge_ice = 0x985a7,
	charge_wave_ice = 0x985e9,
	charge_spazer = 0x9854f,
	charge_spazer_wave = 0x985ff,
	charge_spazer_ice = 0x98565,
	charge_spazer_wave_ice = 0x9857b,
	charge_plasma = 0x985bd,
	charge_plasma_wave = 0x9862b,
	charge_plasma_ice = 0x98615,
	charge_plasma_wave_ice = 0x98591,
	charge_plasma_spazer = 0x98641,
	charge_plasma_spazer_wave = 0x98641,
	charge_plasma_spazer_ice = 0x98657,
	charge_plasma_spazer_wave_ice = 0x98671,
	wave_sba = topc(0x93, 0x8689),
	ice_sba = topc(0x93, 0x85a7),
	spazer_sba = topc(0x93, 0x86ab),
	plasma_sba = topc(0x93, 0x8685),
}
local weaponNameForDamageAddr = damageAddrs:map(function(v,k) return k,v end)

print()
print'weapon damages:'
local addrs
for _,addr in ipairs(weaponNameForDamageAddr:keys():sort()) do
	local name = weaponNameForDamageAddr[addr]
	local ptr = ffi.cast('uint16_t*', rom+addr)
	ptr[0] = 0x999	--math.random(20, 0x200)
	print(('$%06x'):format(addr)..' = '..('%04x'):format(ptr[0])..' '..name)
end
