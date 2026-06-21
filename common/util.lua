-- ============================= 公共辅助函数 ===========================

local M = {}
local string_format = string.format
local table_concat = table.concat
local lua_keywords = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true,
	["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true, ["return"] = true,
	["then"] = true, ["true"] = true, ["until"] = true, ["while"] = true
}

local function _is_valid_lua_identifier(s)
	return type(s) == "string" 
            and s:match("^[_%a][_%w]*$") ~= nil and not lua_keywords[s]
end

local function _serialize_value(v, sep, isNotTab, seen)
	local t = type(v)
	if t == "number" or t == "boolean" or t == "nil" then
		return tostring(v)
	elseif t == "string" then
		return string_format("%q", v)
	elseif t == "table" then
		return M.serialize(v, sep, isNotTab, seen)
	end
	return string_format("%q", tostring(v))
end

-- lua中序列化数据
function M.serialize(obj, sep, isNotTab, seen)
	if sep ~= ";" then
		sep = ","
	end

	local t = type(obj)
	if t == "number" then
		return tostring(obj)
	elseif t == "boolean" then
		return tostring(obj)
	elseif t == "string" then
		return string_format("%q", obj)
	elseif t == "table" then
		seen = seen or {}
		if seen[obj] then
			error("can not serialize table with circular reference.")
		end
		seen[obj] = true

		local cache = isNotTab and {" "} or {"{"}
		local keys = {}
		-- metatable
		--local metatable = getmetatable(obj)

		-- array
		for i, v in ipairs(obj) do
			cache[#cache + 1] = _serialize_value(v, sep, isNotTab, seen)
			cache[#cache + 1] = sep
			keys[i] = true
		end

		-- key, value
		for k, v in pairs(obj) do
			if not keys[k] then
				t = type(k)
				if t == "number" then
					cache[#cache + 1] = "["
					cache[#cache + 1] = tostring(k)
					cache[#cache + 1] = "]"
				elseif t == "string" then
					if _is_valid_lua_identifier(k) then
						cache[#cache + 1] = k
					else
						cache[#cache + 1] = "["
						cache[#cache + 1] = string_format("%q", k)
						cache[#cache + 1] = "]"
					end
				else
					cache[#cache + 1] = "["
					cache[#cache + 1] = string_format("%q", tostring(k))
					cache[#cache + 1] = "]"
				end
				cache[#cache + 1] = "="
				cache[#cache + 1] = _serialize_value(v, sep, isNotTab, seen)
				cache[#cache + 1] = sep
				keys[k] = true
			end
		end

		cache[#cache + 1] = isNotTab and " " or "}"
		seen[obj] = nil
		return table_concat(cache)
	elseif t == "nil" then
		return "nil"
	else
		error("can not serialize a " .. t .. " type.")
	end
end

local _unserializeEnv = {
	type = _G.type,
	tostring = _G.tostring,
	error = _G.error,
}

-- lua中反序列化数据
function M.unserialize(lua)
	local t = type(lua)
	if t == "nil" or lua == "" then
		return nil
	elseif t == "number" or t == "string" or t == "boolean" then
		lua = tostring(lua)
	else
		error("can not unserialize a " .. t .. " type.")
	end
	lua = "return " .. lua
	local func, err = load(lua, "M.unserialize", "t", _unserializeEnv)
	if func == nil then
		return nil, err
	end
	local ok, result = pcall(func)
	if not ok then
		return nil, result
	end
	return result
end


function M.random_int(min, max)
	min = min or 1
	max = max or 1000000
	if min > max then
		min, max = max, min
	end
	if min == max then
		return min
	end
	return math.random(min, max)
end

return M