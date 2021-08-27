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

local function struct(args)
	local name = assert(args.name)
	local fields = assert(args.fields)
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
	
	local metatype 
	xpcall(function()
		print(code)

		ffi.cdef(code)
	
		-- also in common with my hydro-cl project
		-- consider merging
		local metatable = {
			toLua = function(self)
				local result = {}
				for _,field in ipairs(fields) do
					local name, ctype = next(field)
					local value = self[name]
					if ctype.toLua then
						value = value:toLua()
					end
					result[name] = value
				end
				return result
			end,
			__tostring = function(self)
				local t = table()
				for _,field in ipairs(fields) do
					local name, ctype = next(field)
					
					local s = (typeToString[ctype] or tostring)(self[name])
					
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
			code = code,
			fields = fields,
		}
		metatable.__index = metatable
		if args.metatable then
			args.metatable(metatable)
		end
		metatype = ffi.metatype(name, metatable)

		local sizeOfFields = table.map(fields, function(kv)
			local name,ctype = next(kv)
			return ffi.sizeof(ctype)
		end):sum()
		assert(ffi.sizeof(name) == sizeOfFields, "struct "..name.." isn't packed!")

	end, function (err)
		io.stderr:write(require 'template.showcode'(code),'\n')
		io.stderr:write(err,'\n',debug.traceback(),'\n')
		os.exit(1)
	end)
	return metatype, code
end

return struct
