-- http://www.romhacking.net/documents/243/
-- http://pikensoft.com/docs/Zelda_LTTP_compression_(Piken).txt

-- decompresses from 'rom' to a lua table of uint8_t's
local function decompress(addr, maxlen)
	local startaddr = addr
	local result = table()

	local function readbyte()
		assert(addr >= 0 and addr < #romstr)
		local v = rom[addr]
		-- v is now a lua number
		addr = addr + 1
		return v
	end

	local function lzdecompress(len, bytes, mask, absolute)
		assert(bytes == 1 or bytes == 2)
		assert(mask == 0 or mask == 0xff)
		local from = readbyte()
		if bytes == 2 then
			from = bit.bor(from, bit.lshift(readbyte(), 8))
		end
		if not absolute then
			from = #result - from
		end
		if from >= 0 and from < #result then
			for i=0,len-1 do
				local ofsi = from+i+1
				assert(ofsi >= 1 and ofsi <= #result)
				result:insert(
					bit.bxor(result[ofsi], mask)
				)
			end
		else
			error 'got a bad lz decompression offset'
		end
	end

	while true do
		assert(addr < startaddr + maxlen, "compressed data exceeded boundary")
		local c = readbyte()
		if c == 0xff then break end
		local cmd = bit.band(bit.rshift(c, 5), 7)
		local len = bit.band(c, 0x1f)
		if bit.band(c, 0xe0) == 0xe0 then	-- 1110:0000
			-- extended cmd
			local v = readbyte()
			cmd = bit.band(bit.rshift(c, 2), 7)
			len = bit.bor(v, bit.lshift(bit.band(len, 0x3), 8))
		end
		len=len+1
		if cmd == 0 then	-- 000b: direct copy
			for i=0,len-1 do
				result:insert(readbyte())
			end
		elseif cmd == 1 then	-- 001b: byte fill
			local v = readbyte()
			for i=0,len-1 do
				result:insert(v)
			end
		elseif cmd == 2 then	-- 010b: word fill
			local v1 = readbyte()
			local v2 = readbyte()
			for i=0,len-1 do
				if bit.band(i,1)==0 then
					result:insert(v1)
				else
					result:insert(v2)
				end
			end
		elseif cmd == 3 then	-- 011b: incremental fill
			local v = readbyte()
			for i=0,len-1 do
				result:insert(v)
				v = bit.band(0xff, v+1)
			end
		elseif cmd == 4 then	-- 100b: 
			lzdecompress(len, 2, 0, true)
		elseif cmd == 5 then	-- 101b: 
			lzdecompress(len, 2, 0xff, true)
		elseif cmd == 6 then	-- 110b: 
			lzdecompress(len, 1, 0, false)
		elseif cmd == 7 then	-- 111b: 
			lzdecompress(len, 1, 0xff, false)
		end
	end

for _,v in ipairs(result) do 
	assert(type(v) == 'number')
end

	return result, addr - startaddr
end

-- compresses from a lua table of uint8_t's to another lua table of uint8_t's

-- max op len of 1023 = 11:1111:1111
--local MAX_BLOCK_LENGTH = 1024
-- but this produces false terminators: 111(ext):111(lzw):11(upper 2 bits of size) = 0xff
-- max op len of 255+512 = 10:1111:1111
local MAX_BLOCK_LENGTH = 255+512

local function putBlockHeader(result, op, length)
--print('inserting op '..op..' len '..length)	
	assert(length >= 1 and length <= MAX_BLOCK_LENGTH, "got bad length of "..length)
	length = length - 1
	-- extended op
	if length > 0x1f or op == 7 then
		local v1 = bit.bor(0xe0, bit.lshift(op, 2), bit.band(bit.rshift(length, 8), 0x3))
		local v2 = bit.band(length, 0xff)
		assert(v1 ~= 0xff, "might get a false terminator for op "..op..' len '..length)
		result:insert(v1)
		result:insert(v2)
	-- just regular kind
	else 
		local v = bit.bor(bit.lshift(op,5), length)
		result:insert(v)
	end
end

local function noCompress(source, offset, length, result)
	putBlockHeader(result, 0, length)
	for i=0,length-1 do
		result:insert(source[1+ offset-length+i])
	end
end

local function rleCompress(source, offset, op)
	local bytes = 1
	local gradient = 0
	if op == 1 then
	elseif op == 2 then 
		bytes = 2 
	elseif op == 3 then 
		gradient = 1
	else 
		error 'here' 
	end
	local length = 1
	local i = 1
	while offset + i < #source and length < MAX_BLOCK_LENGTH do
		if source[1+ offset+i] == (source[1+ offset + i % bytes] + gradient * i) % 0x100 then 
			length = length + 1 
		else 
			break
		end
		i = i + 1
	end
	local result = table()
	putBlockHeader(result, op, length)
	result:insert(source[1+ offset])
	if bytes == 2 then
		result:insert(source[1+ offset+1])
	end
	return {
		result = result,
		srclen = length,
	}
end

local LZC = class()
function LZC:init(source)
	self.source = source
	self.offsets = range(0,255):map(function(i) 
		return table(), i
	end)
	for i,v in ipairs(source) do
		assert(type(v) == 'number')
		self.offsets[v]:insert(i-1)
	end
end

function LZC:compress(offset, op)
	local source = self.source
	local offsets = self.offsets
	local bytes = 1
	local mask = 0
	local absolute = true
	if op == 4 then
		bytes = 2
	elseif op == 5 then
		bytes = 2
		mask = 0xff
	elseif op == 6 then
		absolute = false
	elseif op == 7 then
		mask = 0xff
		absolute = false
	else
		error'here'
	end
	local lowest = 0
	local highest = offset
	if absolute then
		if bytes == 2 then
			highest = math.min(0x10000, highest)
		else 
			highest = math.min(0x100, highest)
		end
	else
		if bytes == 2 then
			lowest = math.max(offset - 0xffff, 0)
		else 
			lowest = math.max(offset - 0xff, 0)
		end
	end
	--build Knuth–Morris–Pratt table
	local tabl = {}
	local wordLength = math.min(MAX_BLOCK_LENGTH, #source - offset)
	tabl[1] = -1
	tabl[2] = 0
	local i = 2
	local j = 0
	while i < wordLength do
		if source[1+ offset+i-1] == source[1+ offset+j] then
			j=j+1
			tabl[1+ i] = j
			i=i+1
		elseif j > 0 then
			j = tabl[1+ j]
		else
			tabl[1+ i] = 0
			i=i+1
		end
	end
	--find longest match using Knuth–Morris–Pratt algorithm
	local bestStart = 0
	local bestLength = 0
	local nextOffsetToTry = 0
	while nextOffsetToTry < #offsets[bit.bxor(source[1+ offset],mask)] do
		i = offsets[bit.bxor(source[1+ offset],mask)][1+ nextOffsetToTry]
		if i >= lowest then break end
		nextOffsetToTry = nextOffsetToTry + 1
	end
	if nextOffsetToTry >= #offsets[bit.bxor(source[1+ offset],mask)] then
		length = 0
		return {result=table(), srclen=0}
	end
	j = 0 --offset into string being searched for
	while i + j < highest or (j ~=0 and i < offset and i + j < highest + MAX_BLOCK_LENGTH and i + j < #source) do
		if source[1+ offset+j] == bit.bxor(source[1+ i+j],mask) then
			j=j+1
			if j > bestLength then
				bestStart = i
				bestLength = j
			end
			if j == wordLength then break end
		else
			i = i + j - tabl[1+ j]
			if tabl[1+ j] >= 0 then 
				j = tabl[1+ j]
			else
				j = 0
				--advance i based on index of source
				while true do
					nextOffsetToTry = nextOffsetToTry + 1
					if nextOffsetToTry >= #offsets[bit.bxor(source[1+ offset],mask)] then break end
					if offsets[bit.bxor(source[1+ offset],mask)][1+ nextOffsetToTry] >= i then break end
				end
				if nextOffsetToTry >= #offsets[bit.bxor(source[1+ offset],mask)] then 
					break 
				else 
					i = offsets[bit.bxor(source[1+ offset],mask)][1+ nextOffsetToTry]
				end
			end
		end
	end
	--apply
	length = bestLength
	if length == 0 then return {result=table(), srclen=0} end
	local result = table()
	putBlockHeader(result, op, length)
	if not absolute then bestStart = offset - bestStart end
	result:insert(bit.band(0xff, bestStart))
	if bytes == 2 then
		result:insert(bit.rshift(bestStart, 8))
	end
	return {
		srclen = length,
		result = result,
	}
end

local function compress(source)
print('compress #source '..#source)	
	local result = table()	
	local i = 0
	local noCompressionLength = 0
	local lzc = LZC(source)
	while i < #source do
		local options = {
			rleCompress(source, i, 1),
			rleCompress(source, i, 2),
			rleCompress(source, i, 3),
			lzc:compress(i, 4),
			lzc:compress(i, 5),
			lzc:compress(i, 6),
			lzc:compress(i, 7),
		}
		local bestOption
		local bestSourceLength = 1
		local bestDestinationLength = 1
		for j,option in ipairs(options) do
			local sourceLength = options[j].srclen
			if sourceLength > 0 then
				local destinationLength = #options[j].result
				local bestRatio = bestDestinationLength / bestSourceLength
				local ratio = destinationLength / sourceLength
				if bestSourceLength > 8 and sourceLength > 8 then
					if sourceLength < bestSourceLength then
						ratio = (destinationLength + 2) / sourceLength
					elseif sourceLength > bestSourceLength then
						bestRatio = (bestDestinationLength + 2) / bestSourceLength
					end
				end
				if ratio < bestRatio then
					bestOption = option
					bestSourceLength = options[j].srclen
					bestDestinationLength = #options[j].result
				end
			end
		end
		if not bestOption then
			noCompressionLength = noCompressionLength + 1
			i = i + 1
			if i >= #source 
or noCompressionLength == MAX_BLOCK_LENGTH
			then 
--print('adding no-compress len '..noCompressionLength)			
				noCompress(source, i, noCompressionLength, result)
noCompressionLength = 0
			end
		else
			if noCompressionLength ~= 0 then
				noCompress(source, i, noCompressionLength, result)
--print('adding no-compress len '..noCompressionLength)			
				noCompressionLength = 0
			end
--print('adding compress len '..#bestOption.result)			
			result:append(bestOption.result)
			i = i + bestOption.srclen
		end
	end
	result:insert(0xff)
print('total result len '..#result)	
	return result
end

return {
	compress = compress,
	decompress = decompress,
}
