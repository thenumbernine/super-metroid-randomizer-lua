local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local struct = require 'struct'
local Blob = require 'blob'

--[[
now using http://patrickjohnston.org/bank/8F#fB76A
bg headers:
0000 = 2 bytes = terminator
0002 = 9 bytes
0004 = 7 bytes
0006 = 2 bytes (not used?)
0008 = 9 bytes
000a = 2 bytes
000c = 2 bytes (only used once)
000e = 11 bytes

explanation here: https://wiki.metroidconstruction.com/doku.php?id=super:technical_information:data_structures
--]]

--[[
used by 0, a, c
header==0x0 => terminator
header==0x6 => clear layer 3 (is this used?)
header==0xa => clear layer 2
header==0xc => clear kraid's layer 2
--]]
local bg_header_t = struct{
	name = 'bg_header_t',
	fields = {
		{header = 'uint16_t'},
	},
}

--[[
header==0x2 => copy len bytes from .addr24 to VRAM:.dstOfs
header==0x8 => copy len bytes from .addr24 to VRAM:.dstOfs ... and set bg3 tile base addr to $2000
--]]
local bg_2_8_t = struct{
	name = 'bg_2_8_t',
	fields = {
		{header = 'uint16_t'},
		{addr24 = 'addr24_t'},
		{dstOfs = 'uint16_t'},
		{len = 'uint16_t'},
	},
}

--[[
header==0x4 => decompress from .addr24 to $7e:.dstOfs
--]]
local bg_4_t = struct{
	name = 'bg_4_t',
	fields = {
		{header = 'uint16_t'},
		{addr24 = 'addr24_t'},
		{dstOfs = 'uint16_t'},
	},
}

--[[
header==0xe => copy len bytes from .addr24 to VRAM:.dstOfs if the current doorPageOffset == .doorPageOffset
--]]
local bg_e_t = struct{
	name = 'bg_e_t',
	fields = {
		{header = 'uint16_t'},
		{doorPageOffset = 'uint16_t'},
		{addr24 = 'addr24_t'},
		{dstOfs = 'uint16_t'},
		{len = 'uint16_t'},
	},
}

local bgCTypeForHeader = {
	[0x0] = bg_header_t,
	[0x2] = bg_2_8_t,
	[0x4] = bg_4_t,
	[0x6] = bg_header_t,
	[0x8] = bg_2_8_t,
	[0xa] = bg_header_t,
	[0xc] = bg_header_t,
	[0xe] = bg_e_t,
}



local MapBG = class(Blob)

MapBG.count = 1

function MapBG:init(args)
	local sm = args.sm
	local rom = sm.rom
	local addr = args.addr
	args = table(args):setmetatable(nil)
	local header = ffi.cast('uint16_t*', rom + addr)[0]
	local bgctypeinfo = bgCTypeForHeader[header]
	if not bgctypeinfo then
		error("failed to find type for bg_t header "..('%04x'):format(header)..' addr '..('%06x'):format(addr))
	end
	args.type = assert(bgctypeinfo.name)
	MapBG.super.init(self, args)

	-- list of all m's that use this bg
	self.roomStates = table()

	if header == 4 then
--print('decoding bg addr '..('%06x'):format(addr)..' tileset '..('%06x'):format(ptr.addr24:topc()))
		self.tilemap = sm:mapAddBGTilemap(self:obj().addr24:topc())
		-- don't overwrite?  and if we do then make this self.tilemap.bgs:insert(self)
		-- but nope, seems bg tilemaps are 1:1 with bgs
		assert(not self.tilemap.bg)
		self.tilemap.bg = self	-- is this 1:1?
	elseif header == 0xe then
		-- keep track of the door
		-- TODO later
		-- don't do this here since we are mid-loading the roomstates here
	end

end

return MapBG
