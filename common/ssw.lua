local skynet = require "skynet"
require "skynet.manager" -- skynet.register
local cmdstat = require "cmdstat"
local profile = require "skynet.profile"
local sharestorage = require "sharestorage"
local snutil = require "snutil"
local logger = require "logger"
local ahocorasick = require "ahocorasick"
require "utils.functions"

local _cmdstat = cmdstat.new()

--配置
local sensitive_words

local CMD = {}
local rep_checks = {
    -- 确保替换字符串本身没有屏蔽字
}
local loading
local acinst


local function load_ssw(words)
    local acinst_tmp = ahocorasick.create(words)
    if not acinst_tmp then
        logger.err("load ssw, create acinst failed")
        return
    end
    return acinst_tmp
end

local function _load_ssw()
    local words = table.clone(sensitive_words)
    acinst = load_ssw(words)
    return true
end

function CMD.reload()
    if loading then
        logger.warn("already loading ssw")
        return true
    end
    loading = true
    logger.info("loading ssw")
    xpcall(_load_ssw, snutil.handle_err)
    loading = false
    logger.info("load ssw finish")
    return true
end

-- 检查text是否包含敏感词
-- 不包含敏感词返回nil
function CMD.validate(text)
    if not text or text == '' then return true end
    if string.len(text) > 500 then return end
    if not acinst then 
        logger.err("check sensitive word failed, acinst=nil")
        return
    end

    local i1, i2 = ahocorasick.match(acinst, text)
    if (i1 and i2) then
        logger.info("sensitive word %s", string.sub(text, i1+1, i2+1))
        return nil, i1, i2
    end
    return true
end

-- 替换敏感词
local function replace_text(inst, text, rep)
    -- 1. 确保替换字本身不在敏感词中
    -- 2. 依次替换所有敏感词
    if not rep_checks[rep] then
        if not ahocorasick.match(inst, rep) then
            rep_checks[rep] = true
        else
            error(("%s itself be a sensitive word!"):format(rep))
        end
    end
    local k = 0
    repeat
        k = k + 1
        if k > 10 then
            return string.rep(rep,10)
        end
        local i, j = ahocorasick.match(inst, text)
        if i and j then
            text = ("%s%s%s"):format(text:sub(1, i), rep, text:sub(j + 2))
        end
    until not (i and j)
    return text
end

-- 替换敏感词
function CMD.replace(text, rep)
    return replace_text(acinst, text or "", rep or "*")
end

skynet.init(function()
    sensitive_words = sharestorage "tbsensitivethesaurus"
end)


skynet.start(function()
	skynet.dispatch("lua", function(session,source,cmd, ...)
		local f = CMD[cmd]
        if not f then
            error(string.format("Unknonw CMD %s", tostring(cmd)))
        end

        local start_time = skynet.time()
        profile.start()
        local ok, err = xpcall(snutil.lua_docmd, snutil.handle_err, session, CMD, cmd, ...)
        if not ok then
            _cmdstat:stat(cmd, start_time, skynet.time(), profile.stop(), source)
            skynet.error(string.format("%s error, cmd=%s, session=%s, source=%s, args=%s", 
                    ".ssw", cmd, session, source, table.tostring({...})))
            error(err)
        end
        _cmdstat:stat(cmd, start_time, skynet.time(), profile.stop(), source)
	end)
    skynet.info_func(function ()
        return _cmdstat:str()
    end)
    skynet.register ".ssw"
    _load_ssw()
end)