-- Minimal JSON encode/decode for login protocol messages.

local M = {}

local function escape_str(s)
	return s:gsub("\\", "\\\\")
		:gsub('"', '\\"')
		:gsub("\r", "\\r")
		:gsub("\n", "\\n")
		:gsub("\t", "\\t")
end

function M.encode(val)
	if val == nil then
		return "null"
	end
	local t = type(val)
	if t == "string" then
		return '"' .. escape_str(val) .. '"'
	elseif t == "number" then
		if val ~= val or val == math.huge or val == -math.huge then
			return "null"
		end
		return string.format("%.14g", val)
	elseif t == "boolean" then
		return val and "true" or "false"
	elseif t == "table" then
		local parts = {}
		for k, v in pairs(val) do
			if type(k) == "string" then
				parts[#parts + 1] = M.encode(k) .. ":" .. M.encode(v)
			end
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function M.decode(str)
	if type(str) ~= "string" then
		error("json_min.decode expects string")
	end
	local pos = 1
	local len = #str

	local function skip_ws()
		while pos <= len do
			local b = str:byte(pos)
			if b == 32 or b == 9 or b == 10 or b == 13 then
				pos = pos + 1
			else
				break
			end
		end
	end

	local function parse_string()
		assert(str:sub(pos, pos) == '"', "expected string")
		pos = pos + 1
		local buf = {}
		while pos <= len do
			local c = str:sub(pos, pos)
			if c == '"' then
				pos = pos + 1
				return table.concat(buf)
			elseif c == "\\" then
				pos = pos + 1
				local e = str:sub(pos, pos)
				pos = pos + 1
				if e == "n" then
					buf[#buf + 1] = "\n"
				elseif e == "r" then
					buf[#buf + 1] = "\r"
				elseif e == "t" then
					buf[#buf + 1] = "\t"
				elseif e == '"' or e == "\\" then
					buf[#buf + 1] = e
				elseif e == "" then
					error("bad escape")
				else
					buf[#buf + 1] = e
				end
			else
				buf[#buf + 1] = c
				pos = pos + 1
			end
		end
		error("unterminated string")
	end

	local parse_value
	local function parse_object()
		assert(str:sub(pos, pos) == "{", "expected {")
		pos = pos + 1
		skip_ws()
		local t = {}
		if str:sub(pos, pos) == "}" then
			pos = pos + 1
			return t
		end
		while true do
			skip_ws()
			local key = parse_string()
			skip_ws()
			assert(str:sub(pos, pos) == ":", "expected :")
			pos = pos + 1
			skip_ws()
			t[key] = parse_value()
			skip_ws()
			local sep = str:sub(pos, pos)
			if sep == "}" then
				pos = pos + 1
				return t
			elseif sep == "," then
				pos = pos + 1
			else
				error("expected , or }")
			end
		end
	end

	function parse_value()
		skip_ws()
		local c = str:sub(pos, pos)
		if c == '"' then
			return parse_string()
		elseif c == "{" then
			return parse_object()
		elseif c == "t" and str:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif c == "f" and str:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif c == "n" and str:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		elseif c == "-" or (c >= "0" and c <= "9") then
			local num = str:match("^%-?%d+%.?%d*[eE]?%-?%d*", pos)
			if not num then
				error("bad number")
			end
			pos = pos + #num
			return tonumber(num)
		end
		error("unexpected character")
	end

	skip_ws()
	local root = parse_value()
	skip_ws()
	if pos <= len then
		error("trailing data")
	end
	return root
end

return M
