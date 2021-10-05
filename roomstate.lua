local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local struct = require 'struct'
local Blob = require 'blob'
local topc = require 'pc'.to


local roomstate_t = struct{
	name = 'roomstate_t',
	fields = {
		{roomBlockAddr24 = 'addr24_t'},		-- points to block data.  bank is $c2 to $c9
		{tileSetIndex = 'uint8_t'},			-- tile graphics data
		{musicTrack = 'uint8_t'},
		{musicControl = 'uint8_t'},
		{fx1PageOffset = 'uint16_t'},				-- $83
		{enemySpawnPageOffset = 'uint16_t'},		-- TODO "enemySpawnSetAddr". points to an array of enemySpawn_t
		{enemyGFXPageOffset = 'uint16_t'},		-- holds palette info on the enemies used?  points to an array of enemyGFX_t's ... which are just pairs of enemyClass_t's + palettes
	
		--[[
		From https://wiki.metroidconstruction.com/doku.php?id=super:technical_information:data_structures:
				
			The layer 2 scroll X/Y is a value that determines whether or not custom layer 2 is used, and how fast layer 2 scrolls compared to layer 1 (parallax effect)
				In binary, let layer 2 scroll X/Y = sssssssb
				If b = 1, then the library background is used, otherwise custom layer 2 (defined in level data) is used
				s = 0 is a special case that depends on b
					If b = 0 (custom layer 2), then layer 2 and layer 1 scroll together at the same speed (like an extension of layer 1)
					If b = 1 (library background), then layer 2 does not scroll at all (static image background)
				Otherwise (if s != 0), layer 2 scroll speed = (layer 1 scroll speed) * (s / 0x80)
		
		... I'm really not sure what this means.  Not sure if the 'sssb' means 'b' is bit0 or bit7 ... or bit15 since it's referering to a uint16_t .... smh 
		--]]
		{layer2scrollXY = 'uint16_t'},	-- TODO
		
		--[[
		scroll is either a constant, or an offset in bank $8f to 1 byte per map block
		if scroll is 0 or 1 then it is a constant -- to fill all map blocks with that scroll value
		otherwise it is a ptr to an array of scroll values for each map block.
		0 = don't scroll up/down, or past the scroll==0 boundaries at all
		1 = scroll anywhere, but clip the top & bottom 2 blocks (which will hide vertical exits)
		2 = scroll anywhere at all ... but keeps samus in the middle, which makes it bad for hallways
		--]]
		{scrollPageOffset = 'uint16_t'},
		
		--[[
		this is only used by the grey torizo room, and points to the extra data after room_t
		--]]
		{roomvarPageOffset = 'uint16_t'},		-- "special x-ray blocks" according to https://wiki.metroidconstruction.com/doku.php?id=super:technical_information:data_structures
		{mainAsmPageOffset = 'uint16_t'},
		{plmPageOffset = 'uint16_t'},
		{bgPageOffset = 'uint16_t'},				-- offset to bg_t's
		{layerHandlingPageOffset = 'uint16_t'},
	},
}


local RoomState = class(Blob)

RoomState.type = 'roomstate_t'
RoomState.count = 1
RoomState.roomstate_t = roomstate_t 

function RoomState:init(args)
	RoomState.super.init(self, args)

	self.room = assert(args.room)
	self.roomSelect = assert(args.roomSelect)
	
	local sm = self.sm
	local rom = sm.rom
	local room = self.room
	
	self.bgs = self.bgs or table()
	
	-- non-addr will have a blank object ... need to init it 
	if not self.addr then
		-- roomBlockAddr24 will be blank too ... don't load the roomblockdata 
		self:obj().roomBlockAddr24.bank = 0
		self:obj().roomBlockAddr24.ofs = 0
		self:obj().tileSetIndex = 0
		self:obj().musicTrack = 0
		self:obj().musicControl = 0
		self:obj().fx1PageOffset = 0			-- can this be zero?
		self:obj().enemySpawnPageOffset = 0		-- can this be zero?
		self:obj().enemyGFXPageOffset = 0		-- can this be zero?
		self:obj().layer2scrollXY = 0
		self:obj().scrollPageOffset = 0
		self:obj().roomvarPageOffset = 0
		self:obj().mainAsmPageOffset = 0
		self:obj().plmPageOffset = 0
		self:obj().bgPageOffset = 0
		self:obj().layerHandlingPageOffset = 0
			
		self:setRoomBlockData(sm:mapAddRoomBlockData(nil, self.room))
	
		-- can these not be set?
		self:setEnemySpawnSet(sm:mapAddEnemySpawnSet(nil))
		self:setEnemyGFXSet(sm:mapAddEnemyGFXSet(nil))
		self:setFX1Set(sm:mapAddFX1Set(nil))
	else

		-- TODO > 0x8000 ?
		if self:obj().scrollPageOffset > 0x0001 
		and self:obj().scrollPageOffset ~= 0x8000 
		then
			local addr = topc(sm.scrollBank, self:obj().scrollPageOffset)
			local size = room:obj().width * room:obj().height
			self.scrollData = range(size):map(function(i)
				return rom[addr+i-1]
			end)
		end

		if self:obj().plmPageOffset ~= 0 then
			self:setPLMSet(sm:mapAddPLMSetFromAddr(topc(sm.plmBank, self:obj().plmPageOffset)))
		end
		
		self:setEnemySpawnSet(sm:mapAddEnemySpawnSet(topc(sm.enemySpawnBank, self:obj().enemySpawnPageOffset)))
		self:setEnemyGFXSet(sm:mapAddEnemyGFXSet(topc(sm.enemyGFXBank, self:obj().enemyGFXPageOffset)))
		self:setFX1Set(sm:mapAddFX1Set(topc(sm.fx1Bank, self:obj().fx1PageOffset)))
		
		if self:obj().bgPageOffset > 0x8000 then
			-- bg_*_t's are sequentially stored, and their size varies depending on their header
			-- which means (should this be a MapBGSet?) if one fails to read then the rest can't be read either.
			xpcall(function()
				local addr = topc(sm.bgBank, self:obj().bgPageOffset)
				while true do
					local bg = sm:mapAddBG(addr, rom)
					bg.roomStates:insert(self)
					self.bgs:insert(bg)
					addr = addr + ffi.sizeof(bg.type)
					if bg:obj().header == 0 then break end
				end
			end, function(err)
				print(err..'\n'..debug.traceback())
			end)
		end

		if self:obj().layerHandlingPageOffset > 0x8000 then
			--[[
			with flags == 0x00 we have 8 mismatched flag calls
			with flags == 0x20 we have 17 mismatched flag calls and 2 OOB branches
			--]]
			self.layerHandlingCode = sm:codeAdd(topc(sm.layerHandlingBank, self:obj().layerHandlingPageOffset))
			self.layerHandlingCode.srcs:insert(self)
		end

		xpcall(function()
			self:setRoomBlockData(sm:mapAddRoomBlockData(self:obj().roomBlockAddr24:topc(), room))
		end, function(err)
			print(err..'\n'..debug.traceback())
		end)

		
		-- $079804 - 00/15 - grey torizo room - has 14 bytes here 
		-- pointed to by room[00/15].roomstate_t[#1].roomvarPageOffset
		-- has data $986b: 0f 0a 52 00 | 0f 0b 52 00 | 0f 0c 52 00 | 00 00
		-- this is the rescue animals roomstate
		-- so this data has to do with the destructable wall on the right side
		--if roomPageOffset == 0x79804 then
		if self:obj().roomvarPageOffset ~= 0 then
			local d = rom + topc(sm.plmBank, self:obj().roomvarPageOffset)
			local roomvar = table()
			repeat
				roomvar:insert(d[0])	-- x
				roomvar:insert(d[1])	-- y
				if ffi.cast('uint16_t*', d)[0] == 0 then break end
				roomvar:insert(d[2])	-- mod 1 == 0x52
				roomvar:insert(d[3])	-- mod 2 == 0x00
				-- TODO insert roomvar_t and uint16_t term (or omit term)
				d = d + 4
			until false
			-- TODO should be roomstate
			self.roomvar = roomvar
		end
	end

	-- try to load tile graphics from rs.obj():tileSetIndex
	-- TODO cache this per tileSet, since there are only 256 possible, and probably much less used?
	self:setTileSet(select(2, sm.tileSets:find(nil, function(tileSet)
		return tileSet.index == self:obj().tileSetIndex
	end)))
end

function RoomState:setPLMSet(plmset)
	if self.plmset then
		self.plmset.roomStates:removeObject(self)
	end
	self.plmset = plmset
	if self.plmset then
		self.plmset.roomStates:insert(self)
	end
end

function RoomState:setFX1Set(fx1set)
	if self.fx1set then
		self.fx1set.roomStates:removeObject(self)
	end
	self.fx1set = fx1set
	if self.fx1set then
		self.fx1set.roomStates:insert(self)
	end
end

function RoomState:setEnemySpawnSet(enemySpawnSet)
	if self.enemySpawnSet then
		self.enemySpawnSet.roomStates:removeObject(self)
	end
	self.enemySpawnSet = enemySpawnSet
	if self.enemySpawnSet then
		self.enemySpawnSet.roomStates:insert(self)
	end
end

function RoomState:setEnemyGFXSet(enemyGFXSet)
	if self.enemyGFXSet then
		self.enemyGFXSet.roomStates:removeObject(self)
	end
	self.enemyGFXSet = enemyGFXSet
	if self.enemyGFXSet then
		self.enemyGFXSet.roomStates:insert(self)
	end
end

function RoomState:setRoomBlockData(roomBlockData)
	if self.roomBlockData then
		self.roomBlockData.roomStates:removeObject(self)
		self.roomBlockData:refreshRooms()
	end
	self.roomBlockData = roomBlockData
	if self.roomBlockData then
		self.roomBlockData.roomStates:insert(self)
		self.roomBlockData:refreshRooms()
	end
end

function RoomState:setTileSet(tileSet)
	if self.tileSet then
		self.tileSet.roomStates:removeObject(self)
	end
	self.tileSet = tileSet
	if self.tileSet then
		self.tileSet.roomStates:insert(self)
	end
end

return RoomState
