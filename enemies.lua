local ffi = require 'ffi'
local config = require 'config'
local struct = require 'struct'
local randomizeEnemyProps = config.randomizeEnemyProps



local ROMTable = class()

function ROMTable:init()
	self.structSize = ffi.sizeof(self.structName)
	self.fieldNameMaxLen = self.fields:map(function(kv)
		return #next(kv)
	end):sup()
end


-- this is a table that the Enemy table uses .. like weaknesses or item drops
local EnemyAuxTable = class(ROMTable)

EnemyAuxTable.showDistribution = true
EnemyAuxTable.bank = 0xb4

function EnemyAuxTable:init()
	EnemyAuxTable.super.init(self)
	
	self.addrs = sm.enemies:map(function(enemy)
		return true, enemy.ptr[0][self.enemyField]
	end):keys():sort()

	print(self.name..' has '..#self.addrs..' unique addrs:')
	print(' '..self.addrs:map(function(addr) return ('%04x'):format(addr) end):concat', ')
end

function EnemyAuxTable:randomize()
	local randomizeEnemyProps = config.randomizeEnemyProps
	local ptrtype = self.structName..'*'
	
	for _,addr in ipairs(self.addrs) do
		if addr ~= 0 then
			-- return nil to not randomize this entry
			local values = self:getRandomizedValues(addr)
			if values then
				assert(#values == #self.fields)
			end

			local pcaddr = topc(self.bank, addr)
			local entry = ffi.cast(ptrtype, rom + pcaddr)

			for i,field in ipairs(self.fields) do
				local name = next(field)
		
				-- if we are randomizing the enemy field ... then randomize the table associated with it
				if randomizeEnemyProps[self.enemyField] 
				and values 
				then
					local value = values[i]
					entry[0][name] = value
				end
			end
		end
	end
end

function EnemyAuxTable:print()
	local ptrtype = self.structName..'*'

	local distr
	if self.showDistribution then
		distr = table()
	end
	
	print()
	print(self.name..':')
	for _,addr in ipairs(self.addrs) do
		-- concise:
		--io.write('  '..('0x%04x'):format(addr)..' ')
		-- verbose:
		print(('0x%04x'):format(addr))
		print('used by: '..sm.enemies:filter(function(enemy)
			return enemy.ptr[0][self.enemyField] == addr
		end):map(function(enemy)
			return enemy.name
		end):concat', ')
		if addr ~= 0 then
			local pcaddr = topc(self.bank, addr)
			local entry = ffi.cast(ptrtype, rom + pcaddr)
			insertUniqueMemoryRange(pcaddr, ffi.sizeof(self.structName), self.structName)
			for i,field in ipairs(self.fields) do
				local name = next(field)
				local value = entry[0][name]
				
				if self.showDistribution then
					local value = entry[0][name]
					distr[value] = (distr[value] or 0) + 1
				end
				
				-- concise:
				--io.write( (' %02x'):format(value) )
				-- verbose:
				print('  '..name..' '.. ('.'):rep(self.fieldNameMaxLen-#name+5)..' '..('0x%02x'):format(value))
			end
		end
		-- concise:
		--print()
	end
	
	if self.showDistribution then
		print'...distribution of values:'
		for _,k in ipairs(distr:keys():sort()) do
			print('  '..('0x%x'):format(k)..' x'..distr[k])
		end
		print()
	end
end

function EnemyAuxTable:randomizeEnemy(enemy)
	local randomizeEnemyProps = config.randomizeEnemyProps
	local field = self.enemyField
	if not randomizeEnemyProps[field] then return end
	enemy.ptr[0][field] = pickRandom(self.addrs)
end

function EnemyAuxTable:printEnemy(enemy)
	local field = self.enemyField
	
	io.write(' ',field,'=',('0x%04x'):format(enemy.ptr[0][field]))
	local addr = enemy.ptr[0][field]
	if addr ~= 0 then
		io.write(' ',tostring(ffi.cast(self.structName..'*', rom + topc(self.bank, addr))))
	end
	print()
end


local EnemyItemDropTable = class(EnemyAuxTable)

EnemyItemDropTable.name = 'enemy item drop table'
EnemyItemDropTable.enemyField = 'itemdrop'	-- field in enemy_t to get addresses from
EnemyItemDropTable.structName = 'itemDrop_t'	-- structure at the address
EnemyItemDropTable.fields = itemDrop_t_fields

-- returns a list of bytes that are written to the structure
-- TODO I could use the ffi info and return arbitrary values that are correctly cast into the structure ...
function EnemyItemDropTable:getRandomizedValues(addr)
	local randomizeEnemyProps = config.randomizeEnemyProps
	-- 6 percentages (of 0xff):
	-- small energy, large energy, missile, nothing, super missile, power bomb
	local values = range(self.structSize):map(function()
		return math.random() <= randomizeEnemyProps.itemDropZeroChance and 0 or math.random()
	end)
	-- now normalize
	local sum = values:sum()
	-- ... should I allow for monsters to not drop anything?
	-- ... should I have special exception for bosses?
	if sum > 0 then
		values = values:map(function(value) return math.ceil(value * 0xff / sum) end)
	end
	--- TODO should always add up to 0xff here ...but if I was lazy, would floor() or ceil() be better?			
	return values
end


local EnemyWeaknessTable = class(EnemyAuxTable)

EnemyWeaknessTable.name = 'enemy weakness table'
EnemyWeaknessTable.enemyField = 'weakness'
EnemyWeaknessTable.structName = 'weakness_t'
EnemyWeaknessTable.fields = weakness_t_fields

--[[
t is value => percentage
returns a value at random, weighted by percentage
--]]
local function pickWeighted(t)
	local r = math.random() * table.sum(t)
	for value,prob in pairs(t) do
		r = r - prob
		if r <= 0 then
			return value
		end
	end
	error("shouldn't get here")
end

local dontChangeWeaknessSet = {
	["Kraid (body)"] = true, 
	Metroid = true,
}

--[[
here's possible values:    
	0 = no damage to enemy.
    1 = 0.5x damage to enemy.
    2 = default (1x) damage to enemy.
    3 = 1.5x damage to enemy.
    4 = 2x damage to enemy.
    5 = 2.5x damage to enemy.
    4-F = higher damage to enemy.

in addition, the 0x80 bitflag is used for whether it can be frozen or not
--]]
--[[
here's the distribution of original values:
  0x00 x385	<- can freeze / immune
  0x01 x17
  0x02 x488
  0x04 x67
 
can't freeze flag:
  0x80 x235	<- can't freeze / immune flag
  0x81 x8
  0x82 x152
  0x84 x26

insta freeze & no damage flag:
  0xff x52
OOPS this still allows monsters to be damaged by non-beams (since 0x0f is the low nibble value)
so what's going on ... what's the insta freeze flag?

total: 1409
can freeze (0,1,2,4): 936 = 66%
can't freeze (80,81,82,84): 421 = 30%
instafreeze (ff): 52 = 4%

I'm suspicious the last 0x80 is a bitflag of some sort
and who knows what 0xff is ...

kraid is at 0xe2bf
and has a weakness address 0xf15a <-> 0x1a715a :  
82 82 82 82 82 
82 82 82 82 82 
82 82 82 82 80 
80 80 80 80 02 
80 80

looks like all beams/missiles have 82 (hyper has 02)
and all else has 80
I'm thinking 0x80 must be a bitflag
otherwise 2 = normal damage, 0 = no damage

metroidconstruction.com says:

    0 = no damage to enemy.
    1 = 0.5x damage to enemy.
    2 = default (1x) damage to enemy.
    3 = 1.5x damage to enemy.
    4 = 2x damage to enemy.
    5 = 2.5x damage to enemy.
    4-F = higher damage to enemy.
--]]

--[[
value effects:

0
makes monsters immune to everything
...except grappling still kills some minor enemies

1
should be 50%
looks like it

0x10
0x20
0x40
0x42
insta-freezes then insta-kills

0x80 
After writing 'freeze' everywhere, 
I'm now pretty sure this bit is for whether charge+beam can damage it


0xff
insta freeze 
speed booster still kills green zebesians
screw attack kills mini kraid
screw attack kils
grappling still kills too, but not mini kraid or green zebesians 

soooo ... it all looks very conditional


some exceptions to the rule:
Spore Spawn can't be hurt by power bombs or non-charge beams no matter what
--]]
local iceFieldSet = {
	ice=1,
	ice_wave=1,
	ice_spazer=1,
	wave_ice_spazer=1,
	wave_ice_plasma=1,
}
function EnemyWeaknessTable:getRandomizedValues(addr)
	local randomizeEnemyProps = config.randomizeEnemyProps
	local values = self.fields:map(function(field)
		local fieldName, fieldType = next(field)

		local freezeField = iceFieldSet[fieldName]
		
		-- only if it's a freeze field 
		if freezeField  then
			if math.random() < randomizeEnemyProps.chanceToInstaFreeze then 
				return 0xff 
			end
		end

		local value
		if math.random() <= randomizeEnemyProps.weaknessImmunityChance then
			value = 0
		else
			-- exp(-x/7) has the following values for 0-15:
			-- 1.0, 0.86687789975018, 0.75147729307529, 0.65143905753106, 0.56471812200776, 0.48954165955695, 0.42437284567695, 0.36787944117144, 0.31890655732397, 0.27645304662956, 0.23965103644178, 0.2077481871436, 0.18009231214795, 0.15611804531597, 0.13533528323661, 0.11731916609425
			value = pickWeighted(range(0,15):map(function(x) return math.exp(-x/7) end))
		end	

		if freezeField  then
			if math.random() > randomizeEnemyProps.chanceToFreeze then
				value = bit.bor(value, 0x80)	-- can't freeze flag
			end
		end

		return value
	end)

	-- make sure there's at least one nonzero weakness within the first 20
	local found
	for i=1,20 do
		if bit.band(values[i], 0xf) ~= 0 then
			found = true
			break
		end
	end
	if not found then
		values[math.random(20)] = math.random(1,0xf)
	end

	-- don't change kraid's part's weaknesses
	-- until I know how to keep the game from crashing
	for name,_ in pairs(dontChangeWeaknessSet) do
		if sm.enemyForName[name].ptr.weakness == addr then
			return
		end
	end

	-- make sure Shaktool weakness entry is immune to powerbombs
	--if addr == ShaktoolWeaknessAddr then	-- local ShaktoolWeaknessAddr = 0xef1e
	if addr == sm.enemyForName.Shaktool.ptr.weakness then
		values[16] = 0
	end
	
	return values
end

function EnemyWeaknessTable:randomizeEnemy(enemy)
	-- NOTICE
	-- if (for item placement to get past canKill constraints)
	-- we choose to allow re-rolling of weaknesses
	-- then they will have to work around the fact that these certain enemies shouldn't re-roll
	
	-- don't randomize Kraid's weaknesses ... for now
	-- leave this at 0
	if dontChangeWeaknessSet[enemy.name] 
	-- don't randomize Shaktool -- leave it at its default weakness entry (which is unshared by default)
	or enemy.name == Shaktool
	then
		print('NOT WRITING WEAKNESS OF '..enemy.name)
		return
	end

	EnemyWeaknessTable.super.randomizeEnemy(self, enemy)
end

-- globals because ...
-- 1) the ctor is what builds the weakness_t type
-- 2) enemies.lua needs this for randomization
-- TODO put the type info here, and move the classes back to enemies.lua => randomize_enemies.lua
enemyItemDropTable = EnemyItemDropTable()
enemyWeaknessTable = EnemyWeaknessTable()


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

struct'enemyShot_t'{
	{initAI = 'uint16_t'},
	{firstAI = 'uint16_t'},
	{graphicsAI = 'uint16_t'},
	{halfWidth = 'uint8_t'},
	{halfHeight = 'uint8_t'},
	
	{damageAndFlags = 'uint16_t'},
--[[ flags:
0x8000 = can be shot by samus
0x4000 = shot doesn't die when it hits samus
0x2000 = don't collide with samus
0x1000 = invisible
0x0fff = damage
--]]

	{touchAI = 'uint16_t'},	-- AI to run when samus gets hit
	{shootAI = 'uint16_t'},	-- AI to run if samus shoots the shot
}
-- addr is bank $86
local enemyShots = table{
	{addr=0xD02E, name="Kago's bugs (enemy $E7FF)"},
	{addr=0xA17B, name="Space pirate's eye lasers"},
	{addr=0xA189, name="Claws that fighting space pirates throw at Samus"},
	{addr=0xCF26, name="Kihunter acid, going right (enemies $EABF, $EB3F, $EBBF)"},
	{addr=0xCF18, name="Kihunter acid, going left (enemies $EABF, $EB3F, $EBBF)"},
	{addr=0x9E90, name="Walking dragon's fireballs (enemy $E9BF)"},
	{addr=0xB5CB, name="Lava dragon's fireballs (enemy $D4BF)"},
	{addr=0x8BC2, name="Skree's debris #1 (enemy $DB7F)"},
	{addr=0x8BD0, name="Skree's debris #2 (enemy $DB7F)"},
	{addr=0x8BDE, name="Skree's debris #3 (enemy $DB7F)"},
	{addr=0x8BEC, name="Skree's debris #4 (enemy $DB7F)"},
	{addr=0x8BFA, name="Metalee's debris #1 (enemy $D67F)"},
	{addr=0x8C08, name="Metalee's debris #2 (enemy $D67F)"},
	{addr=0x8C16, name="Metalee's debris #3 (enemy $D67F)"},
	{addr=0x8C24, name="Metalee's debris #4 (enemy $D67F)"},
	{addr=0xDAFE, name="Cactus' needles, projectile runs once for each of the five needles (enemy $CFFF)"},
	{addr=0xDFBC, name="Eyed version of Name & Fune's fireball (enemy $E73F)"},
	{addr=0xDFCA, name="Eyeless version of Name & Fune's fireball (enemy $E6FF)"},
	{addr=0xE0E0, name="Lava clumps thrown by lavaman (enemy $E83F)"},
	{addr=0xD298, name="Puu's debris when it explodes (enemy $E8BF)"},
	{addr=0xD2D0, name="Wrecked ship robot's ring lasers, travelling up right (enemy $E8FF)"},
	{addr=0xD2B4, name="Wrecked ship robot's ring lasers, travelling left (enemy $E8FF)"},
	{addr=0xD2A6, name="Wrecked ship robot's ring lasers, travelling up left (enemy $E8FF)"},
	{addr=0xD2C2, name="Wrecked ship robot's ring lasers, travelling down right (enemy $E8FF)"},
	{addr=0xD2DE, name="Wrecked ship robot's ring lasers, travelling down left (enemy $E8FF)"},
	{addr=0xF498, name="Wrecked ship's falling green sparks (enemy $EA3F)"},
	{addr=0xBD5A, name="Flying rocky debris in Norfair (enemy $D1FF)"},
	{addr=0x9DB0, name="Rocks that mini Kraid spits (enemy $E0FF)"},
	{addr=0x9DBE, name="Mini Kraid's belly spikes, facing left (enemy $E0FF)"},
	{addr=0x9DCC, name="Mini Kraid's belly spikes, facing right (enemy $E0FF)"},
	{addr=0xA985, name="Bomb Torizo's explosive hand swipe (enemy $EEFF)"},
	{addr=0xAEA8, name="Bomb Torizo's crescent projectile (enemy $EEFF)"},
	{addr=0xAD5E, name="Orbs that Bomb Torizo spits (enemy $EEFF)"},
	{addr=0xDE6C, name="Spore spawners? (enemy $DF3F)"},
	{addr=0xDE88, name="Spore spawners? (enemy $DF3F)"},
	{addr=0xDE7A, name="Spore Spawn's spores (enemy $DF3F)"},
	{addr=0x9C6F, name="Rocks when Kraid rises (enemy $E2BF)"},
	{addr=0x9C61, name="Rocks when Kraid rises again (enemy $E2BF)"},
	{addr=0x9C45, name="Rocks that Kraid spits (enemy $E2BF)"},
	{addr=0x9C53, name="Rocks that fall when Kraid's ceiling crumbles (enemy $E2BF) (Kraid's flying claws and belly spike platforms aren't enemy projectiles.)"},
	{addr=0x8F8F, name="Glowing orbs that Crocomire spits (enemy $DDBF)"},
	{addr=0x8F9D, name="Blocks crumbling underneath Crocomire (enemy $DDBF)"},
	{addr=0x90C1, name="Crocomire's spike wall when it crumbles (enemy $DDBF)"},
	{addr=0x9C37, name="Phantoon's starting fireballs (enemy $E4BF)"},
	{addr=0x9C29, name="All of Phantoon's other fireballs (enemy $E4BF)"},
	{addr=0xEBA0, name="Botwoon's wall? (enemy $F293)"},
	{addr=0xEC48, name="Botwoon's green spit (enemy $F293)"},
	{addr=0x8E5E, name="Draygon's wall turret projectiles (enemy $DE3F)"},
	{addr=0x8E50, name="Draygon gunk (enemy $DE3F)"},
	{addr=0xB428, name="Golden Torizo's eye beam (enemy $EF7F)"},
	{addr=0xAFE5, name="Golden Torizo preparing to attack; equipment check? (enemy $EF7F)"},
	{addr=0xAFF3, name="Golden Torizo preparing to attack; equipment check? (enemy $EF7F)"},
	{addr=0xAD7A, name="Orbs that Golden Torizo spits  (enemy $EF7F)"},
	{addr=0xAEB6, name="Golden Torizo's crescent projectile; doesn't run if Samus's ammo is too low (enemy $EF7F)"},
	{addr=0xB31A, name="Super missile that Golden Torizo throws at Samus (enemy $EF7F)"},
	{addr=0xB1C0, name="Hatchlings that Golden Torizo uses when it's almost dead (enemy $EF7F)"},
	{addr=0x9642, name="Ridley's fireball (enemy $E17F)"},
	{addr=0x965E, name="Something for Ridley (enemy $E17F)"},
	{addr=0x9688, name="Something for Ridley (enemy $E17F)"},
	{addr=0x9696, name="Something for Ridley (enemy $E17F)"},
	{addr=0xC17E, name="Something for Mother Brain; spawning turrets? (enemy $EC3F)"},
	{addr=0xC18C, name="Mother Brain's turret bullets (enemy $EC3F)"},
	{addr=0xCEFC, name="Mother Brain's glass shattering (enemy $EC3F)"},
	{addr=0xCF0A, name="Mother Brain's glass shards falling (enemy $EC3F)"},
	{addr=0xCB91, name="Mother Brain's mother brain's saliva (enemy $EC3F)"},
	{addr=0xCB2F, name="Mother Brain's purple breath, larger puff (enemy $EC3F)"},
	{addr=0xCB3D, name="Mother Brain's purple breath, smaller puff (enemy $EC3F)"},
	{addr=0xCB4B, name="Mother Brain's blue ring lasers (enemy $EC3F)"},
	{addr=0xA17B, name="Mother Brain's space pirate eye laser (enemy $EC3F)"},
	{addr=0xCB59, name="Mother Brain's bomb as it spawns from her mouth (enemy $EC3F)"},
	{addr=0x9650, name="Mother Brain's bomb as it bounces on ground (enemy $EC3F)"},
	{addr=0x966C, name="Mother Brain's bomb as it explodes (enemy $EC3F)"},
	{addr=0x967A, name="Mother Brain's bomb as it explodes again (enemy $EC3F)"},
	{addr=0xCB67, name="Mother Brain's orange chain explosion beam starting (enemy $EC3F)"},
	{addr=0xCB75, name="Mother Brain's orange chain explosion beam running (enemy $EC3F)"},
	{addr=0xCB83, name="Animated graphics in front of Mother Brain's eye while rainbow beam attack charges (enemy $EC3F)"},
	{addr=0xCBAD, name="Mother Brain's rainbow beam firing, runs while beam is active (enemy $EC3F)"},
	{addr=0xB743, name="Eye door projectiles (PLMs $DB48 and $DB56)"},
	{addr=0xD904, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
	{addr=0xD912, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
	{addr=0xD920, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
	{addr=0xF345, name="Enemy death graphics (different types of explosions, particles, etc.)"},
	{addr=0xF337, name="Unknown/varies. Spawning larger quantities of energy/ammo drops?"},
	{addr=0xE509, name="Unknown/varies. Used by boulder enemies, Kraid, Crocomire, Ridley, Mother Brain."},
	{addr=0xEC95, name="Unknown/varies. Runs when rooms with acid are loaded."},
}
for _,shot in ipairs(enemyShots) do
	local addr = topc(0x86, shot.addr)
	shot.ptr = ffi.cast('enemyShot_t*', rom + addr)
	insertUniqueMemoryRange(addr, ffi.sizeof'enemyShot_t', 'enemyShot_t')
end


-- do the randomizing

if config.randomizeEnemies then
	enemyItemDropTable:randomize()
	enemyWeaknessTable:randomize()

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

		enemyWeaknessTable:randomizeEnemy(enemy)
		enemyItemDropTable:randomizeEnemy(enemy)
	end

	if randomizeEnemyProps.shotDamage then
		for _,shot in ipairs(enemyShots) do
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


enemyItemDropTable:print()
enemyWeaknessTable:print()

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
	
	enemyWeaknessTable:printEnemy(enemy)
	enemyItemDropTable:printEnemy(enemy)
	
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
for _,shot in ipairs(enemyShots) do
	print(shot.addr, shot.ptr[0])
end
