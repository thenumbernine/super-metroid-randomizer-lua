-- this holds the enemies[] table, used by rooms, items, etc
-- TODO call this 'enemies.lua'
-- and call 'enemies.lua' => 'randomize_enemies.lua'

local ffi = require 'ffi'
local struct = require 'struct'
local config = require 'config'
local randomizeEnemyProps = config.randomizeEnemyProps

local enemyShotBank = 0x86
local enemyBank = 0x9f
local enemyAuxTableBank = 0xb4

local itemDrop_t_fields = table{
	{smallEnergy = 'uint8_t'},
	{largeEnergy = 'uint8_t'},
	{missile = 'uint8_t'},
	{nothing = 'uint8_t'},
	{superMissile = 'uint8_t'},
	{powerBomb = 'uint8_t'},
}
local itemDrop_t = struct{
	name = 'itemDrop_t',
	fields = itemDrop_t_fields,
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
local weakness_t_fields = table{
	{normal = 'uint8_t'},
	{wave = 'uint8_t'},
	{ice = 'uint8_t'},
	{ice_wave = 'uint8_t'},
	{spazer = 'uint8_t'},
	{wave_spazer = 'uint8_t'},
	{ice_spazer = 'uint8_t'},
	{wave_ice_spazer = 'uint8_t'},
	{plasma = 'uint8_t'},
	{wave_plasma = 'uint8_t'},
	{ice_plasma = 'uint8_t'},
	{wave_ice_plasma = 'uint8_t'},
	{missile = 'uint8_t'},
	{supermissile = 'uint8_t'},
	{bomb = 'uint8_t'},
	{powerbomb = 'uint8_t'},
	{speed = 'uint8_t'},
	{sparkcharge = 'uint8_t'},
	{screwattack = 'uint8_t'},
	{hyper = 'uint8_t'},	-- also charge
	{pseudo_screwattack = 'uint8_t'},
	{unknown = 'uint8_t'},
}
local weakness_t = struct{
	name = 'weakness_t',
	fields = weakness_t_fields,
}


-- one array is from 0xf8000 +0xcebf to +0xf0ff
local enemyStart = topc(enemyBank, 0xcebf)
local enemyCount = (0xf0ff - 0xcebf) / 0x40 + 1
-- another is from +0xf153 to +0xf793 (TODO)
local enemy2Start = topc(enemyBank, 0xf153)
local enemy2Count = (0xf793 - 0xf153) / 0x40 + 1

-- TODO is still a global...
enemyClass_t_fields = table{
	{tileDataSize = 'uint16_t'},
	{palette = 'uint16_t'},
	{health = 'uint16_t'},
	{damage = 'uint16_t'},
	{width = 'uint16_t'},
	{height = 'uint16_t'},
	{aiBank = 'uint8_t'},
	{hurtTime = 'uint8_t'},
	{sound = 'uint16_t'},
	{bossValue = 'uint16_t'},
	{initiationAI = 'uint16_t'},
	{numberOfParts = 'uint16_t'},
	{unused_extraAI_1 = 'uint16_t'},
	{mainAI = 'uint16_t'},
	{grappleAI = 'uint16_t'},
	{hurtAI = 'uint16_t'},
	{frozenAI = 'uint16_t'},
	{xrayAI = 'uint16_t'},
	{deathEffect = 'uint16_t'},	-- explosions upon death. valued 0-4
	{unused_extraAI_2 = 'uint16_t'},
	{unused_extraAI_3 = 'uint16_t'},
	{powerbombAI = 'uint16_t'},
	{unused_extraAI_4 = 'uint16_t'},
	{unused_extraAI_5 = 'uint16_t'},
	{unused_extraAI_6 = 'uint16_t'},
	{touchAI = 'uint16_t'},
	{shotAI = 'uint16_t'},
	{unused_extraAI_7 = 'uint16_t'},
	{graphicsPtr = 'uint24_t'},	-- aka tile data
	{layerPriority = 'uint8_t'},
	{itemdrop = 'uint16_t'},	-- pointer 
	{weakness = 'uint16_t'},	-- pointer 
	{name = 'uint16_t'},		-- pointer
}
local enemyClass_t = struct{
	name = 'enemyClass_t',
	fields = enemyClass_t_fields,
}


local enemyShot_t = struct{
	name = 'enemyShot_t',
	fields = {
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
	},
}

local Enemy = class()

-- get the pointer to the weakness_t
-- TODO weakness_t is defined in EnemyWeaknessTable:init
--  so an instance must be created for this typecast to work
-- maybe I should separate out the typecase definition from the Table init ...
function Enemy:getWeakness()
	local addr = self.ptr.weakness
	if addr == 0 then return end
	local ptr = self.rom + topc(enemyAuxTableBank, addr)
	return ffi.cast('weakness_t*', ptr)
end

-- return the function that builds the structures
local SMEnemies = {}


local ROMTable = class()

function ROMTable:init(sm)
	self.sm = sm
	self.structSize = ffi.sizeof(self.structName)
	self.fieldNameMaxLen = self.fields:map(function(kv)
		return #next(kv)
	end):sup()
end


-- this is a table that the Enemy table uses .. like weaknesses or item drops
local EnemyAuxTable = class(ROMTable)

EnemyAuxTable.showDistribution = true
EnemyAuxTable.bank = enemyAuxTableBank 

function EnemyAuxTable:init(sm)
	EnemyAuxTable.super.init(self, sm)
	
	self.addrs = sm.enemies:map(function(enemy)
		return true, enemy.ptr[0][self.enemyField]
	end):keys():sort()
end

function EnemyAuxTable:randomize()
	local rom = self.sm.rom
	local ptrtype = self.structName..'*'
	
	for _,addr in ipairs(self.addrs) do
		if addr ~= 0 then
			-- return nil to not randomize this entry
			local values = self:getRandomizedValues(addr)
			if values then
				assert(#values == #self.fields)
			end

			local pcaddr = topc(self.bank, addr)
			local entry = ffi.cast(ptrtype, sm.rom + pcaddr)

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

function EnemyAuxTable:buildMemoryMap(mem)
	for _,addr in ipairs(self.addrs) do
		if addr ~= 0 then
			mem:add(topc(self.bank, addr), ffi.sizeof(self.structName), self.structName)
		end
	end
end

function EnemyAuxTable:print()
	local sm = self.sm
	local rom = sm.rom
	local ptrtype = self.structName..'*'
	
	print()
	print(self.name..' has '..#self.addrs..' unique addrs:')
	print(' '..self.addrs:map(function(addr) return ('%04x'):format(addr) end):concat', ')

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
	local field = self.enemyField
	if not randomizeEnemyProps[field] then return end
	enemy.ptr[0][field] = pickRandom(self.addrs)
end

-- print information on an individual enemy
function EnemyAuxTable:printEnemy(enemy)
	local rom = self.sm.rom
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
EnemyItemDropTable.enemyField = 'itemdrop'	-- field in enemyClass_t to get addresses from
EnemyItemDropTable.structName = 'itemDrop_t'	-- structure at the address
EnemyItemDropTable.fields = itemDrop_t_fields

-- returns a list of bytes that are written to the structure
-- TODO I could use the ffi info and return arbitrary values that are correctly cast into the structure ...
function EnemyItemDropTable:getRandomizedValues(addr)
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
	-- don't randomize Kraid's weaknesses ... for now
	["Kraid (body)"] = true, 
	Metroid = true,
	["Spore Spawn"] = true,
	['Mother Brain'] = true,
	["Walking Chozo Statue"] = true,	-- setting the normal beam weakness doesn't make it weak to normal beam
	["Destructible Shutter (vertical)"] = true,	-- shutters in the room after mother brain
	-- don't randomize Shaktool -- leave it at its default weakness entry (which is unshared by default)
	Shaktool = true,
	-- either make sure Black Pirates have weak to hyper, or just don't touch their weakness
	["Black Zebesian"] = true,
	["Black Zebesian (Wall)"] = true,
}

--[[
here's the distribution of original weakness values:
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
	local sm = self.sm
	local values = self.fields:map(function(field)
		local fieldName, fieldType = next(field)

		if config.forceEnemyWeakness
		and config.forceEnemyWeakness[fieldName] 
		then 
			return config.forceEnemyWeakness[fieldName] 
		end

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
			value = 1	--pickWeighted(range(0,15):map(function(x) return math.exp(-x/7) end))
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
	
	if dontChangeWeaknessSet[enemy.name] then
		print('NOT WRITING WEAKNESS OF '..enemy.name)
		return
	end

	EnemyWeaknessTable.super.randomizeEnemy(self, enemy)
end

function SMEnemies:enemiesInit()
	local rom = self.rom
	self.enemies = table{
		{addr=0xcebf, name="Boyon"},
		{addr=0xceff, name="Mini-Crocomire [unused]"},
		{addr=0xcf3f, name="Tatori"},
		{addr=0xcf7f, name="Young Tatori"},
		{addr=0xcfbf, name="Puyo"},
		{addr=0xcfff, name="Cacatac"},
		{addr=0xd03f, name="Owtch"},
		{addr=0xd07f, name="Samus' ship (piece #1)"},
		{addr=0xd0bf, name="Samus' ship (piece #2)"},
		{addr=0xd0ff, name="Mellow"},
		{addr=0xd13f, name="Mella"},
		{addr=0xd17f, name="Memu"},
		{addr=0xd1bf, name="Multiviola"},
		{addr=0xd1ff, name="Polyp"},
		{addr=0xd23f, name="Rinka"},
		{addr=0xd27f, name="Rio"},
		{addr=0xd2bf, name="Squeept"},
		{addr=0xd2ff, name="Geruta"},
		{addr=0xd33f, name="Holtz"},
		{addr=0xd37f, name="Oum"},
		{addr=0xd3bf, name="Chute"},
		{addr=0xd3ff, name="Gripper"},
		{addr=0xd43f, name="Ripper II"},
		{addr=0xd47f, name="Ripper"},
		{addr=0xd4bf, name="Dragon"},
		{addr=0xd4ff, name="Shutter (vertical)"},
		{addr=0xd53f, name="Shutter (vertical)"},
		{addr=0xd57f, name="Shutter (horizontal)"},
		{addr=0xd5bf, name="Destructible Shutter (vertical)"},
		{addr=0xd5ff, name="Kamer (vertical)"},
		{addr=0xd63f, name="Waver"},
		{addr=0xd67f, name="Metaree"},
		{addr=0xd6bf, name="Fireflea"},
		{addr=0xd6ff, name="Skultera"},
		{addr=0xd73f, name="Elevator"},
		{addr=0xd77f, name="Sciser"},
		{addr=0xd7bf, name="Zero"},
		{addr=0xd7ff, name="Tripper"},
		{addr=0xd83f, name="Kamer (horizontal)"},
		{addr=0xd87f, name="Bug"},
		{addr=0xd8bf, name="Glitched bug [unused]"},
		{addr=0xd8ff, name="Mochtroid"},
		{addr=0xd93f, name="Sidehopper"},
		{addr=0xd97f, name="Desgeega"},
		{addr=0xd9bf, name="Big Sidehopper"},
		{addr=0xd9ff, name="Big Sidehopper (Tourian)"},	-- this doesn't obey its weaknesses.  maybe the original table pointer is hardcoded into the AI, and must be used?
		{addr=0xda3f, name="Big Desgeega"},
		{addr=0xda7f, name="Zoa"},
		{addr=0xdabf, name="Viola"},
		{addr=0xdaff, name="[Debug enemy]"},
		{addr=0xdb3f, name="Bang [unused]"},
		{addr=0xdb7f, name="Skree"},
		{addr=0xdbbf, name="Yard"},
		{addr=0xdbff, name="Reflec [unused]"},
		{addr=0xdc3f, name="“Samus” Geemer"},
		{addr=0xdc7f, name="Zeela"},
		{addr=0xdcbf, name="Norfair Geemer"},
		{addr=0xdcff, name="Geemer"},
		{addr=0xdd3f, name="Grey Geemer"},
		{addr=0xdd7f, name="Metroid"},
		{addr=0xddbf, name="Crocomire"},
		{addr=0xddff, name="Crocomire (skeleton)"},
		{addr=0xde3f, name="Draygon (body)"},
		{addr=0xde7f, name="Draygon (eye)"},
		{addr=0xdebf, name="Draygon (tail)"},
		{addr=0xdeff, name="Draygon (arms)"},
		{addr=0xdf3f, name="Spore Spawn"},
		{addr=0xdf7f, name="??? (related to Spore Spawn)"},
		{addr=0xdfbf, name="Boulder"},
		{addr=0xdfff, name="Kzan"},
		{addr=0xe03f, name="??? (related to Kzan)"},
		{addr=0xe07f, name="Hibashi"},
		{addr=0xe0bf, name="Puromi"},
		{addr=0xe0ff, name="Mini-Kraid"},
		{addr=0xe13f, name="Ceres Ridley"},
		{addr=0xe17f, name="Ridley"},
		{addr=0xe1bf, name="??? (related to Ridley)"},
		{addr=0xe1ff, name="Smoke"},
		{addr=0xe23f, name="Ceres door"},
		{addr=0xe27f, name="Zebetite"},
		{addr=0xe2bf, name="Kraid (body)"},
		{addr=0xe2ff, name="Kraid (arm)"},
		{addr=0xe33f, name="Kraid (top belly spike)"},
		{addr=0xe37f, name="Kraid (middle belly spike)"},
		{addr=0xe3bf, name="Kraid (bottom belly spike)"},
		{addr=0xe3ff, name="Kraid (leg)"},
		{addr=0xe43f, name="Kraid (claw)"},
		{addr=0xe47f, name="Kraid (??? belly spike)"},
		{addr=0xe4bf, name="Phantoon (body)"},
		{addr=0xe4ff, name="Phantoon (piece#1)"},
		{addr=0xe53f, name="Phantoon (piece#2)"},
		{addr=0xe57f, name="Phantoon (piece#3)"},
		{addr=0xe5bf, name="Etecoon"},
		{addr=0xe5ff, name="Dachora"},
		{addr=0xe63f, name="Evir"},
		{addr=0xe67f, name="Evir (bullet)"},
		{addr=0xe6bf, name="Eye (security system)"},
		{addr=0xe6ff, name="Fune"},
		{addr=0xe73f, name="Namihe"},
		{addr=0xe77f, name="Coven"},
		{addr=0xe7bf, name="Yapping Maw"},
		{addr=0xe7ff, name="Kago"},
		{addr=0xe83f, name="Magdollite"},
		{addr=0xe87f, name="Beetom"},
		{addr=0xe8bf, name="Powamp"},
		{addr=0xe8ff, name="Work Robot"},
		{addr=0xe93f, name="Work Robot (disabled)"},
		{addr=0xe97f, name="Bull"},
		{addr=0xe9bf, name="Alcoon"},
		{addr=0xe9ff, name="Atomic"},
		{addr=0xea3f, name="Sparks (Wrecked Ship)"},
		{addr=0xea7f, name="Koma"},
		{addr=0xeabf, name="Green Kihunter"},
		{addr=0xeaff, name="Green Kihunter (wing)"},
		{addr=0xeb3f, name="Greenish Kihunter"},
		{addr=0xeb7f, name="Greenish Kihunter (wing)"},
		{addr=0xebbf, name="Red Kihunter"},
		{addr=0xebff, name="Red Kihunter (wing)"},
		{addr=0xec3f, name="Mother Brain"},			-- this is the brain in a jar.  it needs to be weak against missiles and super missiles at least..   this is also the final form of mother brain's weakness (NOT Mother Brain (w/ Body))
		{addr=0xec7f, name="Mother Brain (w/ body)"},
		{addr=0xecbf, name="??? (related to Mother Brain)"},
		{addr=0xecff, name="??? (related to Mother Brain)"},
		{addr=0xed3f, name="Torizo (Drained by metroids)"},
		{addr=0xed7f, name="Big Sidehopper (Drained by metroids)"},
		{addr=0xedbf, name="??? (related to drained enemies)"},
		{addr=0xedff, name="Geemer (Drained by metroids)"},
		{addr=0xee3f, name="Ripper (Drained by metroids)"},
		{addr=0xee7f, name="Skree (Drained by metroids)"},
		{addr=0xeebf, name="Super Metroid"},
		{addr=0xeeff, name="Grey Torizo"},
		{addr=0xef3f, name="??? (Torizo's orb)"},
		{addr=0xef7f, name="Gold Torizo"},
		{addr=0xefbf, name="??? (Gold Torizo's orb)"},
		{addr=0xefff, name="??? (4 Statues flying thing)"},
		{addr=0xf03f, name="??? (4 Statues)"},
		{addr=0xf07f, name="Shaktool"},
		{addr=0xf0bf, name="Shattering Glass (Maridian tube)"},
		{addr=0xf0ff, name="Walking Chozo Statue"},
		{addr=0xf153, name="??? (wierd spining orb)"},
		{addr=0xf193, name="Zeb"},
		{addr=0xf1d3, name="Zebbo"},
		{addr=0xf213, name="Gamet"},
		{addr=0xf253, name="Geega"},
		{addr=0xf293, name="Botwoon"},
		{addr=0xf2d3, name="Etecoon (Escape)"},
		{addr=0xf313, name="Dachora (Escape)"},
		{addr=0xf353, name="Grey Zebesian (Wall)"},
		{addr=0xf393, name="Green Zebesian (Wall)"},
		{addr=0xf3d3, name="Red Zebesian (Wall)"},
		{addr=0xf413, name="Gold Zebesian (Wall)"},
		{addr=0xf453, name="Pink Zebesian (Wall)"},
		{addr=0xf493, name="Black Zebesian (Wall)"},
		{addr=0xf4d3, name="Grey Zebesian (Fighter)"},
		{addr=0xf513, name="Green Zebesian (Fighter)"},
		{addr=0xf553, name="Red Zebesian (Fighter)"},
		{addr=0xf593, name="Gold Zebesian (Fighter)"},	-- this is black/gold
		{addr=0xf5d3, name="Pink Zebesian (Fighter)"},
		{addr=0xf613, name="Black Zebesian (Fighter)"},
		{addr=0xf653, name="Grey Zebesian"},
		{addr=0xf693, name="Green Zebesian"},
		{addr=0xf6d3, name="Red Zebesian"},
		{addr=0xf713, name="Gold Zebesian"},
		{addr=0xf753, name="Pink Zebesian"},
		{addr=0xf793, name="Black Zebesian"},
	}:map(function(enemy)
		-- used for getWeakness(), which casts the rom location to a ptr (or returns nil)
		-- do I really need this function?
		enemy.rom = rom
		return setmetatable(enemy, Enemy)
	end)

	self.enemyForName = self.enemies:map(function(enemy)
		return enemy, enemy.name
	end)

	self.enemyForAddr = self.enemies:map(function(enemy)
		return enemy, enemy.addr
	end)

	for _,enemy in ipairs(self.enemies) do
		local addr = topc(enemyBank, enemy.addr)
		enemy.ptr = ffi.cast('enemyClass_t*', rom + addr)
	end


	self.enemyItemDropTable = EnemyItemDropTable(self)
	self.enemyWeaknessTable = EnemyWeaknessTable(self)

	-- addr is bank $86
	self.enemyShots = table{
		{addr=0xd02e, name="Kago's bugs (enemy $E7FF)"},
		{addr=0xa17b, name="Space pirate's eye lasers"},
		{addr=0xa189, name="Claws that fighting space pirates throw at Samus"},
		{addr=0xcf26, name="Kihunter acid, going right (enemies $EABF, $EB3F, $EBBF)"},
		{addr=0xcf18, name="Kihunter acid, going left (enemies $EABF, $EB3F, $EBBF)"},
		{addr=0x9e90, name="Walking dragon's fireballs (enemy $E9BF)"},
		{addr=0xb5cb, name="Lava dragon's fireballs (enemy $D4BF)"},
		{addr=0x8bc2, name="Skree's debris #1 (enemy $DB7F)"},
		{addr=0x8bd0, name="Skree's debris #2 (enemy $DB7F)"},
		{addr=0x8bde, name="Skree's debris #3 (enemy $DB7F)"},
		{addr=0x8bec, name="Skree's debris #4 (enemy $DB7F)"},
		{addr=0x8bfa, name="Metalee's debris #1 (enemy $D67F)"},
		{addr=0x8c08, name="Metalee's debris #2 (enemy $D67F)"},
		{addr=0x8c16, name="Metalee's debris #3 (enemy $D67F)"},
		{addr=0x8c24, name="Metalee's debris #4 (enemy $D67F)"},
		{addr=0xdafe, name="Cactus' needles, projectile runs once for each of the five needles (enemy $CFFF)"},
		{addr=0xdfbc, name="Eyed version of Name & Fune's fireball (enemy $E73F)"},
		{addr=0xdfca, name="Eyeless version of Name & Fune's fireball (enemy $E6FF)"},
		{addr=0xe0e0, name="Lava clumps thrown by lavaman (enemy $E83F)"},
		{addr=0xd298, name="Puu's debris when it explodes (enemy $E8BF)"},
		{addr=0xd2d0, name="Wrecked ship robot's ring lasers, travelling up right (enemy $E8FF)"},
		{addr=0xd2b4, name="Wrecked ship robot's ring lasers, travelling left (enemy $E8FF)"},
		{addr=0xd2a6, name="Wrecked ship robot's ring lasers, travelling up left (enemy $E8FF)"},
		{addr=0xd2c2, name="Wrecked ship robot's ring lasers, travelling down right (enemy $E8FF)"},
		{addr=0xd2de, name="Wrecked ship robot's ring lasers, travelling down left (enemy $E8FF)"},
		{addr=0xf498, name="Wrecked ship's falling green sparks (enemy $EA3F)"},
		{addr=0xbd5a, name="Flying rocky debris in Norfair (enemy $D1FF)"},
		{addr=0x9db0, name="Rocks that mini Kraid spits (enemy $E0FF)"},
		{addr=0x9dbe, name="Mini Kraid's belly spikes, facing left (enemy $E0FF)"},
		{addr=0x9dcc, name="Mini Kraid's belly spikes, facing right (enemy $E0FF)"},
		{addr=0xa985, name="Bomb Torizo's explosive hand swipe (enemy $EEFF)"},
		{addr=0xaea8, name="Bomb Torizo's crescent projectile (enemy $EEFF)"},
		{addr=0xad5e, name="Orbs that Bomb Torizo spits (enemy $EEFF)"},
		{addr=0xde6c, name="Spore spawners? (enemy $DF3F)"},
		{addr=0xde88, name="Spore spawners? (enemy $DF3F)"},
		{addr=0xde7a, name="Spore Spawn's spores (enemy $DF3F)"},
		{addr=0x9c6f, name="Rocks when Kraid rises (enemy $E2BF)"},
		{addr=0x9c61, name="Rocks when Kraid rises again (enemy $E2BF)"},
		{addr=0x9c45, name="Rocks that Kraid spits (enemy $E2BF)"},
		{addr=0x9c53, name="Rocks that fall when Kraid's ceiling crumbles (enemy $E2BF) (Kraid's flying claws and belly spike platforms aren't enemy projectiles.)"},
		{addr=0x8f8f, name="Glowing orbs that Crocomire spits (enemy $DDBF)"},
		{addr=0x8f9d, name="Blocks crumbling underneath Crocomire (enemy $DDBF)"},
		{addr=0x90c1, name="Crocomire's spike wall when it crumbles (enemy $DDBF)"},
		{addr=0x9c37, name="Phantoon's starting fireballs (enemy $E4BF)"},
		{addr=0x9c29, name="All of Phantoon's other fireballs (enemy $E4BF)"},
		{addr=0xeba0, name="Botwoon's wall? (enemy $F293)"},
		{addr=0xec48, name="Botwoon's green spit (enemy $F293)"},
		{addr=0x8e5e, name="Draygon's wall turret projectiles (enemy $DE3F)"},
		{addr=0x8e50, name="Draygon gunk (enemy $DE3F)"},
		{addr=0xb428, name="Golden Torizo's eye beam (enemy $EF7F)"},
		{addr=0xafe5, name="Golden Torizo preparing to attack; equipment check? (enemy $EF7F)"},
		{addr=0xaff3, name="Golden Torizo preparing to attack; equipment check? (enemy $EF7F)"},
		{addr=0xad7a, name="Orbs that Golden Torizo spits  (enemy $EF7F)"},
		{addr=0xaeb6, name="Golden Torizo's crescent projectile; doesn't run if Samus's ammo is too low (enemy $EF7F)"},
		{addr=0xb31a, name="Super missile that Golden Torizo throws at Samus (enemy $EF7F)"},
		{addr=0xb1c0, name="Hatchlings that Golden Torizo uses when it's almost dead (enemy $EF7F)"},
		{addr=0x9642, name="Ridley's fireball (enemy $E17F)"},
		{addr=0x965e, name="Something for Ridley (enemy $E17F)"},
		{addr=0x9688, name="Something for Ridley (enemy $E17F)"},
		{addr=0x9696, name="Something for Ridley (enemy $E17F)"},
		{addr=0xc17e, name="Something for Mother Brain; spawning turrets? (enemy $EC3F)"},
		{addr=0xc18c, name="Mother Brain's turret bullets (enemy $EC3F)"},
		{addr=0xcefc, name="Mother Brain's glass shattering (enemy $EC3F)"},
		{addr=0xcf0a, name="Mother Brain's glass shards falling (enemy $EC3F)"},
		{addr=0xcb91, name="Mother Brain's mother brain's saliva (enemy $EC3F)"},
		{addr=0xcb2f, name="Mother Brain's purple breath, larger puff (enemy $EC3F)"},
		{addr=0xcb3d, name="Mother Brain's purple breath, smaller puff (enemy $EC3F)"},
		{addr=0xcb4b, name="Mother Brain's blue ring lasers (enemy $EC3F)"},
		{addr=0xa17b, name="Mother Brain's space pirate eye laser (enemy $EC3F)"},
		{addr=0xcb59, name="Mother Brain's bomb as it spawns from her mouth (enemy $EC3F)"},
		{addr=0x9650, name="Mother Brain's bomb as it bounces on ground (enemy $EC3F)"},
		{addr=0x966c, name="Mother Brain's bomb as it explodes (enemy $EC3F)"},
		{addr=0x967a, name="Mother Brain's bomb as it explodes again (enemy $EC3F)"},
		{addr=0xcb67, name="Mother Brain's orange chain explosion beam starting (enemy $EC3F)"},
		{addr=0xcb75, name="Mother Brain's orange chain explosion beam running (enemy $EC3F)"},
		{addr=0xcb83, name="Animated graphics in front of Mother Brain's eye while rainbow beam attack charges (enemy $EC3F)"},
		{addr=0xcbad, name="Mother Brain's rainbow beam firing, runs while beam is active (enemy $EC3F)"},
		{addr=0xb743, name="Eye door projectiles (PLMs $DB48 and $DB56)"},
		{addr=0xd904, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
		{addr=0xd912, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
		{addr=0xd920, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
		{addr=0xf345, name="Enemy death graphics (different types of explosions, particles, etc.)"},
		{addr=0xf337, name="Unknown/varies. Spawning larger quantities of energy/ammo drops?"},
		{addr=0xe509, name="Unknown/varies. Used by boulder enemies, Kraid, Crocomire, Ridley, Mother Brain."},
		{addr=0xec95, name="Unknown/varies. Runs when rooms with acid are loaded."},
	}
	for _,shot in ipairs(self.enemyShots) do
		local addr = topc(enemyShotBank, shot.addr)
		shot.ptr = ffi.cast('enemyShot_t*', rom + addr)
	end

	self.allEnemyFieldValues = {}
	for _,field in ipairs{
		'sound',

	-- doesn't look so great.
		'palette',	
		
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
			self.allEnemyFieldValues[field] = self.allEnemyFieldValues[field] or {
				distr = {},
			}
			local values = self.allEnemyFieldValues[field]
			for _,enemy in ipairs(self.enemies) do
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
end


function SMEnemies:enemiesPrint()
	local rom = self.rom

	self.enemyItemDropTable:print()
	self.enemyWeaknessTable:print()


	-- do the printing


	print"all enemyClass_t's:"
	for i,enemy in ipairs(self.enemies) do
		print(('0x%04x'):format(enemy.addr)..': '..enemy.name)

		print(' tileDataSize='..('0x%04x'):format(enemy.ptr.tileDataSize))
	
		-- wait, is the aiBank the aiBank or the paletteBank?
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
		
		for field,values in pairs(self.allEnemyFieldValues) do
			print(' '..field..'='..('0x%x'):format(enemy.ptr[0][field]))
		end
		
		self.enemyWeaknessTable:printEnemy(enemy)
		self.enemyItemDropTable:printEnemy(enemy)
		
		io.write(' debug name: '
			..('0x%04x'):format(enemy.ptr.name))
		if enemy.ptr.name ~= 0 then
			local addr = topc(0xb4, enemy.ptr.name)
			local len = 10
			local betaname = ffi.string(rom + addr, len)
			io.write(': '..betaname)
			--io.write(' / '..betaname:gsub('.', function(c) return ('%02x '):format(c:byte()) end)
		end
		print()

	end

	print'enemy shot table:'
	for _,shot in ipairs(self.enemyShots) do
		print(shot.addr, shot.ptr[0])
	end
end


function SMEnemies:enemiesBuildMemoryMap(mem)
	for _,enemy in ipairs(self.enemies) do
		local addr = topc(enemyBank, enemy.addr)
		mem:add(addr, ffi.sizeof'enemyClass_t', 'enemyClass_t')
		if enemy.ptr.name ~= 0 then
			mem:add(topc(0xb4, enemy.ptr.name), 14, 'debug name')
		end
	end
		
	self.enemyWeaknessTable:buildMemoryMap(mem)
	self.enemyItemDropTable:buildMemoryMap(mem)

	for _,shot in ipairs(self.enemyShots) do
		local addr = topc(enemyShotBank, shot.addr)
		mem:add(addr, ffi.sizeof'enemyShot_t', 'enemyShot_t')
	end	
end

return SMEnemies
