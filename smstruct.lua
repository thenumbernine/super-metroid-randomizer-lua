local table = require 'ext.table'
local struct = require 'struct'
struct.typeToString.uint8_t = struct.hextostr(2)
struct.typeToString.uint16_t = struct.hextostr(4)
return function(args)
	return struct{
		name = args.name,
		union = true,
		fields = {
			{name='s', type='uint8_t[1]', no_iter=true},
			{type=struct{
				anonymous = true,
				packed = true,
				fields = table.mapi(args.fields, function(kv)
					local name, ctype = next(kv)
					return {
						name = name,
						type = ctype,
					}
				end),
			}},
		},
		metatable = args.metatable,
	}
end
