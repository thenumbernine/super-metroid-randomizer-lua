local struct = require 'struct'
struct.typeToString.uint8_t = struct.hextostr(2)
struct.typeToString.uint16_t = struct.hextostr(4)
struct.packed = true
return struct
