print()
print'weapon damages:'
local addrs
for _,addr in ipairs(sm.weaponDamageForAddr:keys():sort()) do
	local dmg = sm.weaponDamageForAddr[addr]
	local name = dmg.name
	local ptr = dmg.ptr
	ptr[0] = math.random(20, 0x200)
	print(('$%06x'):format(addr)..' = '..('%04x'):format(ptr[0])..' '..name)
end
