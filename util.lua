local ffi = require 'ffi'

local function pickRandom(t)
	return t[math.random(#t)]
end

local function byteArraySubset(src, ofs, len)
	assert(type(src) == 'cdata')
	-- only do bounds check if we're dealing with an array
	-- if it's a pointer then we can't deduce size
	if tostring(ffi.typeof(src)):sub(-2) == ']>' then
		if ofs + len > ffi.sizeof(src) then
			error('tried to copy past end '..tolua{
				src = src,
				ofs = ofs,
				len = len,
				sizeof_src = ffi.sizeof(src),
			})
		end
	end
	local dest = ffi.new('uint8_t[?]', len)
	src = ffi.cast('uint8_t*', src)
	ffi.copy(dest, src + ofs, len)
	return dest
end

local function tableSubsetsEqual(a,b,i,j,n)
	for k=0,n-1 do
		if a[i+k] ~= b[j+k] then return false end
	end
	return true
end

local function tablesAreEqual(a,b)
	if #a ~= #b then return false end
	for i=1,#a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function byteArraysAreEqual(a,b,len)
	if len == nil then
		len = ffi.sizeof(a)
		if len ~= ffi.sizeof(b) then return false end
	end
	a = ffi.cast('uint8_t*', a)
	b = ffi.cast('uint8_t*', b)
	for i=0,len-1 do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function tableToByteArray(src)
	local dest = ffi.new('uint8_t[?]', #src)
	for i,v in ipairs(src) do
		assert(type(v) == 'number' and v >= 0 and v <= 255)
		dest[i-1] = v
	end
	return dest
end

local function byteArrayToTable(src)
	local dest = table()
	for i=1,ffi.sizeof(src) do
		dest[i] = src[i-1]
	end
	return dest
end

local function hexStrToByteArray(src)
	local n = #src/2
	assert(n == math.floor(n))
	local dest = ffi.new('uint8_t[?]', n)
	for i=1,n do
		dest[i-1] = tonumber(src:sub(2*i-1, 2*i), 16)
	end
	return dest
end

local function byteArrayToHexStr(src, len, sep)
	len = len or ffi.sizeof(src)
	src = ffi.cast('uint8_t*', src)
	local s = ''
	local tsep = ''
	for i=1,len do
		s = s .. tsep..('%02x'):format(src[i-1])
		tsep = sep or ''
	end
	return s
end

local function mergeByteArrays(...)
	local srcs = {...}
	local totalSize = 0
	for _,src in ipairs(srcs) do
		totalSize = totalSize + ffi.sizeof(src)
	end
	local dest = ffi.new('uint8_t[?]', totalSize)
	local k = 0
	for _,src in ipairs(srcs) do
		local len = ffi.sizeof(src)
		ffi.copy(dest + k, src, len)
		k = k + len
	end
	assert(k == totalSize)
	return dest
end



return {
	byteArraySubset = byteArraySubset,
	pickRandom = pickRandom,
	tableSubsetsEqual = tableSubsetsEqual,
	tablesAreEqual = tablesAreEqual,
	byteArraysAreEqual = byteArraysAreEqual,
	tableToByteArray = tableToByteArray,
	byteArrayToTable = byteArrayToTable,
	hexStrToByteArray = hexStrToByteArray,
	byteArrayToHexStr = byteArrayToHexStr,
	mergeByteArrays = mergeByteArrays,
}
