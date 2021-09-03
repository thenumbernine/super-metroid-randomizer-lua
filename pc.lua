local bit = require 'bit'

local function topc(bank, offset)
	return bit.bor(bit.lshift(bit.band(bank,0x7f),15),bit.band(offset,0x7fff))
end

--[[
TODO the |0x80 is only required for rom, not ram ... 
--]]
local function frompc(addr)
	local bank = bit.bor(bit.band(bit.rshift(addr, 15), 0x7f), 0x80)
	local ofs = bit.bor(bit.band(addr, 0x7fff), 0x8000)
	return bank, ofs
end

return {
	to = topc,
	from = frompc,
}
