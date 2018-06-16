local ffi = require 'ffi'
local template = require 'template'

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
					t:insert(name..'='..tostring(ptr[name]))
				end
				return '{'..t:concat', '..'}'
			end,
			__concat = function(a,b) return tostring(a) .. tostring(b) end,
		})
	end
end

return defineFields
