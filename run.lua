#!/usr/bin/env luajit
	
--[[
useful pages:
http://wiki.metroidconstruction.com/doku.php?id=super:enemy:list_of_enemies
http://wiki.metroidconstruction.com/doku.php?id=super:technical_information:list_of_enemies
http://metroidconstruction.com/SMMM/
https://gamefaqs.gamespot.com/snes/588741-super-metroid/faqs/39375%22
http://deanyd.net/sm/index.php?title=List_of_rooms
--]]

local file = require 'ext.file'
local table = require 'ext.table'
local range = require 'ext.range'
local tolua = require 'ext.tolua'
local cmdline = require 'ext.cmdline'(...)

local topc = require 'pc'.to

local timerIndent = 0
function timer(name, callback, ...)
	print('TIMER '..(' '):rep(timerIndent)..name..' begin...')
	timerIndent = timerIndent + 1
	local startTime = os.clock()
	local results = table.pack(callback(...))
	local endTime = os.clock()
	timerIndent = timerIndent - 1
	print('TIMER '..(' '):rep(timerIndent)..name..' done, took '..(endTime - startTime)..'s')
	return results:unpack()
end

timer('everything', function()
	function I(...) return ... end
	local ffi = require 'ffi'
	local config = require 'config'

	for k,v in pairs(cmdline) do
		if not ({
			seed=1,
			['in']=1,
			out=1,
		})[k] then
			error("got unknown cmdline argument "..k)
		end
	end

	local seed = cmdline.seed
	if seed then
		seed = tonumber(seed, 16)
	else
		seed = os.time() 
		math.randomseed(seed)
		for i=1,100 do math.random() end
		seed = math.random(0,0x7fffffff)
	end
	print('seed', ('%x'):format(seed))
	math.randomseed(seed)


	--[[
	f24904a32f1f6fc40f5be39086a7fa7c  Super Metroid (JU) [!] PAL.smc
	21f3e98df4780ee1c667b84e57d88675  Super Metroid (JU) [!].smc
	3d64f89499a403d17d530388854a7da5  Super Metroid (E) [!].smc
	
	so what version is "Metroid 3" ? if it's not JU or E?
	"Metroid 3" matches "Super Metroid (JU)" except for:
			"Metroid 3"		"Super Metroid (JU)"
	$60d	a9				89
	$60e	00				10
	<- 89 10 = BIT #$10 = set bit (this is patrickjohnston.org's)
	<- a9 00 = LDA #$00 = clear bit 

	$617	a9				89
	$618	00				10
	<- 89 10 = BIT #$10 = set bit (this is patrickjohnston.org's)
	<- a9 00 = LDA #$00 = clear bit 
	
	$6cb	ea				d0
	$6cc	ea				16
	<- ea ea = NOP NOP		<- skip the check altogether
	<- d0 16 = BNE +16		<- jump if SRAM check fails

	that's it.
	and between JU and E? a lot.
	
	so which does patrickjohnston.org use? 
	
	--]]
	local infilename = cmdline['in'] or 'Super Metroid (JU) [!].smc'
	
	local outfilename = cmdline.out or 'sm-random.smc'

	function exec(s)
		print('>'..s)
		local results = table.pack(os.execute(s))
		print('results', table.unpack(results, 1, results.n))
		return table.unpack(results, 1, results.n)
	end

	--[[ apply patches -- do this before removing any rom header (i guess that depends on the patch's requirements)
	file.__tmp = file[infilename]
	local function applyPatch(patchfilename)
		exec('luajit ../ips/ips.lua __tmp patches/'..patchfilename..' __tmp2 show')
		file.__tmp = file.__tmp2
		file.__tmp2 = nil
	end
	
	--applyPatch'SuperMissiles.ips'	-- shoot multiple super missiles!... and it glitched the game when I shot one straight up in the air ...
	
	romstr = file.__tmp
	file.__tmp = nil
	--]]
	-- [[
	local romstr = file[infilename]
	--]]


	local header = ''
	if bit.band(#romstr, 0x7fff) ~= 0 then
		print('skipping rom file header')
		header = romstr:sub(1,512)
		romstr = romstr:sub(513)
	end
	assert(bit.band(#romstr, 0x7fff) == 0, "rom is not bank-aligned")

	-- global so other files can see it
	local rom = ffi.cast('uint8_t*', romstr) 

	-- global stuff

	local patches = require 'patches'(rom)

	if config.skipItemFanfare then
		patches:skipItemFanfare()
	end
	if config.skipIntro then 
		patches:skipIntro()
	end
	if config.beefUpXRay then
		patches:beefUpXRay()
	end
	if config.wakeZebesEarly then
		patches:wakeZebesEarly()
	end


-- [===[ skip all the randomization stuff

	-- make a single object for the representation of the ROM
	-- this way I can call stuff on it -- like making a memory map -- multiple times
	local SM = require 'sm'

	-- global for now
	timer('read ROM', function()
		sm = SM(rom, #romstr)
	end)

	-- write out unaltered stuff
	if config.mapSaveImageInformative then
		timer('write original ROM info images', function()
			sm:mapSaveImageInformative'map'
		end)
	end
	if config.mapSaveImageTextured then
		timer('write original ROM textured image', function()
			sm:mapSaveImageTextured'map'
		end)
	end
	if config.mapSaveDumpworldImage then
		timer('write original ROM output images', function()
			sm:mapSaveDumpworldImage()
		end)
	end
	if config.mapSaveGraphicsMode7 then
		timer('write original ROM map mode7 images', function()
			sm:mapSaveGraphicsMode7()
		end)
	end
	if config.mapSaveGraphicsTileSets then
		timer('write original ROM map tileset images', function()
			sm:mapSaveGraphicsTileSets()
		end)
	end
	if config.mapSaveGraphicsBGs then
		timer('write original ROM map backgrounds', function()
			sm:mapSaveGraphicsBGs()
		end)
	end
	if config.mapSaveGraphicsLayer2BGs then
		timer('write original ROM map layer 2 backgrounds', function()
			sm:mapSaveGraphicsLayer2BGs()
		end)
	end
	if config.graphicsSavePauseScreenImages then
		timer('write out pause screen images', function()
			sm:graphicsSavePauseScreenImages()
		end)
	end
	if config.samusSaveImages then
		timer('write out samus images', function()
			sm:samusSaveImages()
		end)
	end
	timer('write original ROM memory map', function()
		-- http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
		sm:buildMemoryMap():print'memorymap.txt'
	end)

	if config.writeOutDisasm then
		timer('write out disasm', function()
			for _,bank in ipairs(table{
				0x80,	-- system routines
				0x81,	-- SRAM
				0x82,	-- top level main game routines
				0x83,	-- (data) fx and door definitions 
				0x84,	-- plms
				0x85,	-- message boxes
				0x86,	-- enemy projectiles
				0x87,	-- animated tiles
				0x88,	-- hdma
			}:append(range(0x89, 0xdf))) do
				-- you know, data could mess this up 
				local addr = topc(bank, 0x8000)
				file[('bank/%02X.txt'):format(bank)] = require 'disasm'.disasm(addr, rom+addr, 0x8000)
			end
		end)
	end

	--[[
	for verificaiton: there is one plm per item throughout the game
	however some rooms have multiple room states where some roomstates have items and some don't 
	... however if ever multiple roomStates have items, they are always stored in the same plmset
	and in the case that different roomStates have different items (like the first blue brinstar room, intro roomState has morph, gameplay roomState has powerbomb)
	 there is still no duplicating those roomStates.

	but here's the problem: a few rooms have roomStates where the item comes and goes
	for example, the first blue brinstar room, where the item is morph the first time and powerbomb the second time.
	how can we get around this ...
	one easy way: merge those two plmsets
	how often do we have to merge separate plmsets if we only want to consolidate all items?
		
		this is safe, the item appears after wake-zebes:
	00/13 = Crateria former mother brain room, one plmset has nothing, the other has a missile (and space pirates)
		idk when these happen but they are safe
	00/15 = Crateria chozo boss, there is a state where there is no bomb item ... 
	00/1f = Crateria first missiles after bombs, has a state without the item
		
	!!!! here is the one problem child:
	01/0e = Brinstar first blue room.  one state has morph, the other has powerbombs (behind the powerbomb wall).
		
		these are safe, the items come back when triggered after killing Phantoon:
	03/00 = Wrecked Ship, reserve + missile in one state, not in the other
	03/03 = Wrecked Ship, missile in one state, not in the other
	03/07 = Wrecked Ship, energy in one state, not in the other (water / chozo holding energy?)
	03/0c = Wrecked Ship, super missile in one state, not in the other
	03/0d = Wrecked Ship, super missile in one state, not in the other
	03/0e = Wrecked Ship, gravty in one state, not in the other

	So how do we work around this, keeping a 1-1 copy of all items while not letting the player enter a game state where they can't get an essential item?
	By merging the two roomstates of 01/0e together.
	What do we have to do in order to merge them?
	the two roomstate_t's differ...
	- musicTrack: normal has 09, intro has 06
	- musicControl: normal has 05, intro has 07
	- fx1: normal has 81f4, intro has 8290
	- enemySpawn: normal has 9478, intro has 94fb
	- enemySet: normal has 83b5, intro has 83d1
	- plm: normal has 86c3, intro has 8666 (stupid evil intro plmset that's what screwed everything up ... this is the one i will delete)
	- layerHandling: normal has 91bc, intro has 91d5
	the two plmsets differ...
	- only normal has:
	   plm_t: door_grey_left: {cmd=c848, x=01, y=26, args=0c31}
	   plm_t: item_powerbomb: {cmd=eee3, x=28, y=2a, args=001a}
	- only intro has:
	   plm_t: item_morph: {cmd=ef23, x=45, y=29, args=0019}
	--]]
	-- [[
	if config.wakeZebesEarly then
		local m = assert(sm:mapFindRoom(1, 0x0e))
		assert(#m.roomStates == 2)
		local rsNormal = m.roomStates[1]
		local rsIntro = m.roomStates[2]
		rsIntro.obj.musicTrack = rsNormal.obj.musicTrack
		rsIntro.obj.musicControl = rsNormal.obj.musicControl
	-- the security cameras stay there, and if I update these then their palette gets messed up
	-- but changing this - only for the first time you visit the room - will remove the big sidehoppers from behind the powerbomb wall 
	-- however there's no way to get morph + powerbomb all in one go for the first time you're in the room, so I think I'll leave it this way for now
	--	rsIntro.obj.fx1PageOffset = rsNormal.obj.fx1PageOffset
	--	rsIntro.obj.enemySpawnPageOffset = rsNormal.obj.enemySpawnPageOffset
	--	rsIntro.obj.enemySet = rsNormal.obj.enemySet
		rsIntro.obj.layerHandlingPageOffset = rsNormal.obj.layerHandlingPageOffset
		local rsIntroPLMSet = rsIntro.plmset
		rsIntro:setPLMSet(rsNormal.plmset)
		-- TODO remove the rsIntroPLMSet from the list of all PLMSets
		--  notice that, if you do this, you have to reindex all the items plmsetIndexes
		--  also, if you don't do this, then the map write will automatically do it for you, so no worries
		-- now add those last plms into the new plm set
		local lastIntroPLM = rsIntroPLMSet.plms:remove()
		assert(lastIntroPLM.cmd == sm.plmCmdValueForName.item_morph)
		rsNormal.plmset.plms:insert(lastIntroPLM)
		
		-- and finally, adjust the item randomizer plm indexes and sets
		local _, morphBallItem = sm.items:find(nil, function(item)
			local name = sm.plmCmdNameForValue[item.plm.cmd]
			return name == 'item_morph'
		end)
		
		assert(morphBallItem)
		morphBallItem.plmsetIndex = 56	-- same as blue brinstar powerbomb item
		morphBallItem.plmIndex = 19		-- one past the powerbomb
	end
	--]]



	-- [[ manually change the wake condition instead of using the wake_zebes.ips patch
	-- hmm sometimes it is only waking up the brinstar rooms, but not the crateria rooms (intro items were super x2, power x1, etank x2, speed)
	-- it seems Crateria won't wake up until you get your first missile tank ...
	if config.wakeZebesEarly then
		--[=[ 00/00 = first room ... doesn't seem to work
		-- maybe this has to be set only after the player walks through old mother brain room?
		local m = sm:mapFindRoom(0, 0x00)
		for _,door in ipairs(m.doors) do
			door.code = assert(patches.wakeZebesEarlyDoorCode)
		end
		--]=]
		-- [=[ change the lift going down into blue brinstar
		-- hmm, in all cases it seems the change doesn't happen until after you leave the next room
		local m = sm:mapFindRoom(0, 0x14)
		assert(m.doors[2].addr == topc(sm.doorBank, 0x8b9e))
		m.doors[2].ptr.code = assert(patches.wakeZebesEarlyDoorCode)
		--]=]
		--[=[ 01/0e = blue brinstar first room
		locla m = sm:mapFindRoom(1, 0x0e)
		m.doors[2].ptr.code = assert(patches.wakeZebesEarlyDoorCode)
		--]=]
	end
	--]]

	-- also (only for wake zebes early?) open the grey door from old mother brain so you don't need morph to get back?
	if config.removeGreyDoorInOldMotherBrainRoom then
		local m = sm:mapFindRoom(0, 0x13)
		local rs = m.roomStates[2]	-- sleeping old mother brain
		local plmset = rs.plmset
		local plm = plmset.plms:remove(4)		-- remove the grey door
		assert(plm.cmd == sm.plmCmdValueForName.door_grey_left)
	end


	-- also while I'm here, lets remove the unfinished/unused rooms
	if config.removeUnusedRooms then
		timer('removing unused rooms', function()
			sm:mapRemoveRoom(sm:mapFindRoom(7, 0x00))
		end)
	end

	--[[ redirect our doors to cut out the toned-down rooms (like the horseshoe shaped room before springball)
	local merging424and425 = true
	do
		local m4_24 = assert(sm:mapFindRoom(4, 0x24))
		local m4_25 = assert(sm:mapFindRoom(4, 0x25))
		local m4_30 = assert(sm:mapFindRoom(4, 0x30))
		
		-- clear the code on the door in 04/24 that points back to itself?
		local door = assert(m4_24:findDoorTo(m4_24))
		local doorToSelfDoorCode = door:obj().code
		door:obj().code = 0
		
		local door = assert(m4_24:findDoorTo(m4_24))
		door:obj().code = 0
		
		for _,m in ipairs{m4_24, m4_30} do
			-- find the door that points to 4/25, redirect it to 4/24
			local door = assert(m:findDoorTo(m4_25))
			door:setDestRoom(m4_24)
	--		door:obj().code = doorToSelfDoorCode -- this is in the other door that points to itself in this room
			door:obj().code = 0
			if m == m4_24 then
				assert(door:obj().screenX == 0)
				assert(door:obj().screenY == 2)
				door:obj().screenX = 1
				door:obj().screenY = 3
				assert(door:obj().capY == 0x26)
				door:obj().capY = 0x36
			elseif m == m4_30 then
				assert(door:obj().screenX == 0)
				assert(door:obj().screenY == 1)
				door:obj().screenX = 1
				door:obj().screenY = 2
			else
				error'here'
			end
		end

		-- change the scroll data of the room from 0 to 1?
		-- if you leave all original then walking through the door from 0,3 to 1,3 messes up the scroll effect
		-- if you change the starting room to 0 then walking into 0,3 messes up the scroll effect
		-- if you set 0,3 to 1 then it works, but you can see the room that you're walking into.
		-- (maybe I should make the door somehow fix the scrolldata when you walk through it?) 
		for _,rs in ipairs(m4_24.roomStates) do
			rs.scrollData[1+1+2*2] = 2
			rs.scrollData[1+1+2*3] = 1
		end
		
		-- and now remove 04/25
		sm:mapRemoveRoom(m4_25)
	end
	--]]

	if config.fillInOOBMapBlocksWithSolid then
		timer('filling in OOB map blocks with solid', function()
			-- also for the sake of the item randomizer, lets fill in some of those empty room regions with solid
			local fillSolidInfo = table{
				--[[
				-- TODO this isn't so straightforward.  looks like filling in the elevators makes them break. 
				-- I might have to just excise regions from the item-scavenger instead
				{1, 0x00, 0,0,16,32+6},			-- brinstar left elevator to crateria.  another option is to make these hollow ...
				{1, 0x0e, 16*5, 0, 16, 32+2},	-- brinstar middle elevator to crateria
				{1, 0x24, 0,0,16,32+6},			-- brinstar right elevator to crateria.
				{1, 0x34, 0,16,16,16},			-- brinstar elevator to norfair / entrance to kraid
				{2, 0x03, 0,0,16,32},			-- brinstar elevator to norfair
				{2, 0x26, 0,16-6,16,6},			-- norfair elevator to lower norfair
				{2, 0x36, 64,0,16,32+6},		-- norfair elevator to lower norfair
				{4, 0x18, 0, 0, 16, 10*16},		-- maridia pipe room
				{5, 0x00, 0,0,16,32},			-- tourian elevator shaft
				--]]
				
				{0, 0x00, 0,0,16,32},			-- crateria first room empty regions
				{0, 0x00, 0,48,16,16},			-- "
				
				{0, 0x1c, 0,7*16-5,16,5},		-- crateria bottom of green pirate room 

				{1, 0x18, 0,16-3,16,3},			-- brinstar first missile room

				{2, 0x48, 2, 3*16-4, 1,1},		-- return from lower norfair spade room
				{2, 0x48, 16-2, 3*16-4, 1,1},	-- "

				{4, 0x04, 29, 11, 3, 3},		-- maridia big room - under top door pillars
				{4, 0x08, 1, 11, 3, 4},			-- maridia next big room - under top door pillars
				{4, 0x08, 5, 13, 1, 4},			-- "
				{4, 0x08, 5*16, 2*16, 16,16},	-- maridia next big room - debug area not fully developed
				{4, 0x0b, 16, 0, 16, 16},		-- maridia top left room to missile and super
				{4, 0x0e, 1,16+3,1,2},			-- maridia crab room before refill
				{4, 0x0e, 14,16+3,1,2},			-- "
				{4, 0x0e, 1,16+11,1,2},			-- "
				{4, 0x0e, 14,16+11,1,2},		-- "
				{4, 0x1a, 4*16-4, 16-5, 4, 4},	-- maridia first sand area pillars under door on right side 
				{4, 0x1b, 0, 32-5, 16, 4},		-- maridia green pipe in the middle pillars underneath
				{4, 0x1c, 0, 16-5, 4, 4},		-- maridia second sand area pillars under door on left side 
				{4, 0x1c, 3*16-4, 16-5, 4, 4},	-- maridia second sand area pillars under door on right side 
				{4, 0x24, 0, 64-5, 4, 4},		-- maridia lower right sand area
				{4, 0x24, 16-4, 64-5, 8, 4},	-- "
				{4, 0x24, 32-4, 64-5, 4, 4},	-- "
				{4, 0x26, 0, 32-5, 32, 5},		-- maridia spring ball room
			} 
			if not merging424and425 then
				fillSolidInfo:append{
					{4, 0x25, 0, 48-5, 4, 4},		-- you could merge this room into the previous 
					{4, 0x25, 16-4, 48-5, 4, 4},	-- "
				}
			end
			for _,info in ipairs(fillSolidInfo) do
				local region, index, x1,y1,w,h = table.unpack(info)
				local m = assert(sm:mapFindRoom(region, index))
				local roomBlockData = m.roomStates[1].roomBlockData	-- TODO assert all roomStates have matching rooms?
				local blocks12 = roomBlockData:getBlocks12()
				for j=0,h-1 do
					local y = y1 + j
					assert(y >= 0 and y < roomBlockData.height)
					for i=0,w-1 do
						local x = x1 + i
						assert(x >= 0 and x < roomBlockData.width)
						local bi = 1 + 2 * (x + roomBlockData.width * y)
						blocks12[bi] = bit.bor(bit.band(blocks12[bi], 0x0f), 0x80)
					end
				end
			end
		end)
	end

	-- randomize rooms?  still working on this
	-- *) enemy placement
	-- *) door placement
	-- *) item placement
	-- *) refinancin

	-- do the enemy field randomization
	if config.randomizeEnemies then
		timer('randomizing enemies', function()
			require 'enemies'
		end)
	end

	if config.randomizeWeapons then
		timer('randomizing weapons', function()
			require 'weapons'
		end)
	end

	-- this is just my testbed for map modification code
	--require 'rooms'

	if config.randomizeDoors then
		timer('randomizing doors', function()
			require 'doors'	-- still experimental.  this just adds colored doors, but doesn't test for playability.
		end)
	end

	if config.randomizeItems then
		timer('randomizing items', function()
			require 'items'
		end)
	end

	if config.randomizeItemsScavengerHunt then
		timer('applying item-scavenger', function()
			require 'item-scavenger'
		end)
	end

	if config.mapRecompress then
		timer('write map changes to ROM', function()
			-- write back changes
			sm:mapWrite()
		end)
	end
	
	-- write out altered stuff
	sm:print()
	
	-- TODO split this into writing the info map, the mask map, and the textured map
	-- I don't need a new textured map (unless I'm changin textures)
	--  but the other two are very useful in navigating the randomized map
	-- TODO FIXME remember the bmps are cached from the previous write of unmodified data, so 
	if config.writeOutModifiedMapImage then
		timer('write modified ROM output image', function()
			sm:mapSaveImageInformative'map-random'
		end)
	end
	
	timer('write modified ROM memory map', function()
		sm:buildMemoryMap():print()
	end)
--]===]

	-- write back out
	file[outfilename] = header .. ffi.string(rom, #romstr)

	print('done converting '..infilename..' => '..outfilename)

	if not config.randomizeEnemies then
		print()
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
		print'!!!!!!!!!!! NOT RANDOMIZING ENEMIES !!!!!!!!!'
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	end
	if not config.randomizeItems and not config.randomizeItemsScavengerHunt then
		print()
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
		print'!!!!!!!!!!! NOT RANDOMIZING ITEMS !!!!!!!!!!!'
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	end
	print()
end)
