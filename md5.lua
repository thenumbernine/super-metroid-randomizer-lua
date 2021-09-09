local ffi = require 'ffi'
local range = require 'ext.range'

local k = ffi.new('uint32_t[64]')
for i=0,63 do
	k[i] = math.floor(2^32*math.abs(math.sin(i+1)))
end

local fs = {
	function(x,y,z) return bit.bor(bit.band(x,y),bit.band(-x-1,z)) end,
	function(x,y,z) return bit.bor(bit.band(x,z),bit.band(y,-z-1)) end,
	function(x,y,z) return bit.bxor(x,bit.bxor(y,z)) end,
	function(x,y,z) return bit.bxor(y,bit.bor(x,-z-1)) end,
}

local ss = ffi.new('uint8_t[16]', {
	0x07, 0x0c, 0x11, 0x16,
	0x05, 0x09, 0x0e, 0x14,
	0x04, 0x0b, 0x10, 0x17,
	0x06, 0x0a, 0x0f, 0x15,
})

local cas = ffi.new('uint8_t[4]', {1, 5, 3, 7})
local cbs = ffi.new('uint8_t[4]', {0, 1, 5, 0})

local function md5(s, msglen)
	local save
	if type(s) == 'string' then
		if msglen then
			s = s:sub(1, msglen)
			assert(#s == msglen)
		else
			msglen = #s
		end
		save = s
		s = ffi.cast('char*', s)
	else
		assert(type(s) == 'cdata')
		assert(msglen)
	end
	
	local pad = 56 - bit.band(msglen, 63)
	if bit.band(msglen, 63) > 56 then pad = pad+64 end
	if pad == 0 then pad = 64 end

	local msglen2 = msglen + pad + 8
	assert(bit.band(msglen2, 63) == 0)
	
	local sptr = ffi.new('uint8_t[?]', msglen2)
	ffi.copy(sptr, ffi.cast('char*', s), msglen)
	
	sptr[msglen] = 0x80
	ffi.fill(sptr + msglen + 1, pad - 1, 0)
	ffi.cast('uint32_t*', sptr + msglen2 - 8)[0] = 8*msglen
	ffi.cast('uint32_t*', sptr + msglen2 - 4)[0] = 0

	local abcd0 = ffi.new('uint32_t[4]')
	abcd0[0] = 0x67452301
	abcd0[1] = 0xefcdab89
	abcd0[2] = 0x98badcfe
	abcd0[3] = 0x10325476
	local abcd = ffi.new('uint32_t[4]')
	local mptr = ffi.cast('uint32_t*', sptr)
	for i=0,msglen2-1,64 do
		ffi.copy(abcd, abcd0, 16)
		for j=0,3 do
			local f = fs[j+1]
			local ca = cas[j]
			local cb = cbs[j]
			for i=0,15 do
				local x = mptr[bit.band(ca * i + cb, 0xf)]
				local s = ss[bit.bor(bit.band(i, 3), bit.lshift(j, 2))]
				local kij = k[bit.bor(i, bit.lshift(j, 4))]
				abcd[0], abcd[3], abcd[2], abcd[1] = 
					abcd[3], abcd[2], abcd[1], bit.rol(bit.band(f(abcd[1], abcd[2], abcd[3]) + abcd[0] + kij + x), s) + abcd[1]
			end
		end
		abcd0[0], abcd0[1], abcd0[2], abcd0[3] = 
			abcd0[0] + abcd[0], abcd0[1] + abcd[1], abcd0[2] + abcd[2], abcd0[3] + abcd[3]
		mptr = mptr + 16
	end
	
	return ffi.string(ffi.cast('char*', abcd0), 16)
end

return md5
