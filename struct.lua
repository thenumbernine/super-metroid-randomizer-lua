local ffi = require 'ffi'
local table = require 'ext.table'
local template = require 'template'

local function hextostr(digits)
	return function(value)
		return ('%0'..digits..'x'):format(value)
	end
end

local struct = {}

local structmt = {}
structmt.__index = struct
setmetatable(struct, structmt)

struct.typeToString = {
	uint8_t = hextostr(2),
	uint16_t = hextostr(4),
}

--[[
args:
	name
	fields
	metatype
--]]
function structmt:__call(args)
	local name = assert(args.name)
	local fields = assert(args.fields)
	local code = template([[
typedef union <?=name?> {
	struct {
<? 
local ffi = require 'ffi'
local size = 0
for _,kv in ipairs(fields) do
	local name, ctype = next(kv)
	local rest, bits = ctype:match'^(.*):(%d+)$'
	if bits then
		ctype = rest
	end
	local base, array = ctype:match'^(.*)%[(%d+)%]$' 
	if array then
		ctype = base
		name = name .. '[' .. array .. ']'
	end
	if bits then
		assert(not array)
		size = size + bits / 8
	else
		size = size + ffi.sizeof(ctype) * (array or 1)
	end
?>		<?=ctype?> __attribute__((packed)) <?=name?><?=bits and (' : '..bits) or ''?>;
<? 
end
?>	};
	uint8_t ptr[<?=size?>];
} <?=name?>;
]], 	{
			name = name,
			fields = fields,
		}
	)
	
	local metatype 
	xpcall(function()
--print(code)

		ffi.cdef(code)
	
		-- also in common with my hydro-cl project
		-- consider merging
		local metatable = {
			name = name,
			fields = fields,
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
					local s = self:fieldToString(name, ctype)
					if s 
					-- hmm... bad hack
					and s ~= '{}' 
					then
						t:insert(name..'='..s)
					end
				end
				return '{'..t:concat', '..'}'
			end,
			fieldToString = function(self, name, ctype)
				-- special for bitflags ...
				if ctype:sub(-2) == ':1' then
					if self[name] ~= 0 then
						return 'true'
					else
						return nil -- nothing?
					end
				end

				return (struct.typeToString[ctype] or tostring)(self[name])
			end,
			__concat = function(a,b) 
				return tostring(a) .. tostring(b) 
			end,
			__eq = function(a,b)
				local function isprim(x)
					return ({
						['nil'] = true,
						boolean = true,
						number = true,
						string = true,
					})[type(x)]
				end
				if isprim(a) or isprim(b) then return rawequal(a,b) end
				for _,field in ipairs(fields) do
					local name, ctype = next(field)
					if a[name] ~= b[name] then return false end
				end
				return true
			end,
			code = code,
		}
		metatable.__index = metatable
		if args.metatable then
			args.metatable(metatable)
		end
		metatype = ffi.metatype(name, metatable)

		local sizeOfFields = table.mapi(fields, function(kv)
			local fieldName, fieldType = next(kv)
			local rest, bits = fieldType:match'^(.*):(%d+)$'
			local base, array = fieldType:match'^(.*)%[(%d+)%]$' 
			if bits then
				assert(not array)
				return bits / 8
			else
				return ffi.sizeof(fieldType)
			end
		end):sum()
		local sizeof = ffi.sizeof(name)
		if sizeof ~= sizeOfFields then
			error(
				"sizeof("..name..") = "..sizeof.."\n"
				.."sizeof fields = "..sizeOfFields.."\n"
				.."struct "..name.." isn't packed!"
			)
		end
--[[
		local null = ffi.cast(name..'*', nil)
		local sizeOfFields = table.map(fields, function(kv)
			local fieldName,fieldType = next(kv)
			return ffi.sizeof(null[fieldName])
		end):sum()
		if ffi.sizeof(name) ~= sizeOfFields then
			io.stderr:write("struct "..name.." isn't packed!\n")
			for _,field in ipairs(fields) do
				local fieldName,fieldType = next(kv)
				io.stderr:write('field '..fieldName..' size '..ffi.sizeof(null[fieldName]),'\n')
			end
		end
--]]	
	end, function (err)
		io.stderr:write(require 'template.showcode'(code),'\n')
		io.stderr:write(err,'\n',debug.traceback(),'\n')
		os.exit(1)
	end)
	return metatype, code
end

return struct
