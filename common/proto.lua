local sprotoparser = require "sprotoparser"

local proto = {}

local function parse_from_file(path)
	local f = assert(io.open(path, "r"), "Can't open sproto file: " .. path)
	local data = f:read "a"
	f:close()
	return sprotoparser.parse(data)
end

proto.c2s = parse_from_file("../sproto/c2s.sproto")
proto.s2c = parse_from_file("../sproto/s2c.sproto")

return proto
