local ffi = require 'ffi'
local template = require 'template'

local function hextostr(digits)
	return function(value)
		return ('%0'..digits..'x'):format(value)
	end
end

local typeToString = {
	uint8_t = hextostr(2),
	uint16_t = hextostr(4),
}

local function defineFields(name)
	return function(fields)
		local code = template([[
typedef union {
	struct {
<? 
local ffi = require 'ffi'
local size = 0
for _,kv in ipairs(fields) do
	local name, ctype = next(kv)
	size = size + ffi.sizeof(ctype)
?>		<?=ctype?> <?=name?>;
<? 
end
?>	} __attribute__((packed));
	uint8_t ptr[<?=size?>];
} <?=name?>;
]], {name=name, fields=fields})
		ffi.cdef(code)

		local mt = ffi.metatype(name, {
			__tostring = function(ptr)
				local t = table()
				for _,field in ipairs(fields) do
					local name, ctype = next(field)
					
					local s = (typeToString[ctype] or tostring)(ptr[name])
					
					t:insert(name..'='..s)
				end
				return '{'..t:concat', '..'}'
			end,
			__concat = function(a,b) 
				return tostring(a) .. tostring(b) 
			end,
			__eq = function(a,b)
				for _,field in ipairs(fields) do
					local name, ctype = next(field)
					if a[name] ~= b[name] then return false end
				end
				return true
			end,
		})

		local sizeOfFields = table.map(fields, function(kv)
			local name,ctype = next(kv)
			return ffi.sizeof(ctype)
		end):sum()
		assert(ffi.sizeof(name) == sizeOfFields, "struct "..name.." isn't packed!")

		return mt
	end
end

return defineFields
