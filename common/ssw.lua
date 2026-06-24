local skynet = require "skynet"
require "skynet.manager"
local sharedata = require "skynet.sharedata"
local snutil = require "common.snutil"
local logger = require "common.logger"

local SENSITIVE_WORDS_NAME = "sensitive_words"

local words_list = {}
local CMD = {}
local rep_checks = {}
local loading

local function build_words_list(words)
    local list = {}
    if type(words) == "table" then
        for _, w in pairs(words) do
            if type(w) == "string" and w ~= "" then
                list[#list + 1] = w
            end
        end
    end
    table.sort(list, function(a, b)
        return #a > #b
    end)
    return list
end

local function ac_match(text)
    for _, word in ipairs(words_list) do
        local s, e = text:find(word, 1, true)
        if s then
            return s - 1, e - 1
        end
    end
end

local function _load_ssw()
    local words = sharedata.deepcopy(SENSITIVE_WORDS_NAME)
    words_list = build_words_list(words)
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

function CMD.validate(text)
    if not text or text == "" then
        return true
    end
    if #text > 500 then
        return
    end

    local i1, i2 = ac_match(text)
    if i1 and i2 then
        logger.info("sensitive word %s", string.sub(text, i1 + 1, i2 + 1))
        return nil, i1, i2
    end
    return true
end

local function replace_text(text, rep)
    if not rep_checks[rep] then
        if not ac_match(rep) then
            rep_checks[rep] = true
        else
            error(("%s itself be a sensitive word!"):format(rep))
        end
    end
    local k = 0
    local i, j
    repeat
        k = k + 1
        if k > 10 then
            return string.rep(rep, 10)
        end
        i, j = ac_match(text)
        if i and j then
            text = ("%s%s%s"):format(text:sub(1, i), rep, text:sub(j + 2))
        end
    until not (i and j)
    return text
end

function CMD.replace(text, rep)
    return replace_text(text or "", rep or "*")
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = CMD[cmd]
        if not f then
            error(string.format("Unknonw CMD %s", tostring(cmd)))
        end

        local ok, err = xpcall(snutil.lua_docmd, snutil.handle_err, session, CMD, cmd, ...)
        if not ok then
            logger.info("%s error, cmd=%s, session=%s, source=%s, args=%s",
                ".ssw", cmd, session, source, tostring({...}))
            error(err)
        end
    end)
    skynet.register ".ssw"
    skynet.uniqueservice("config_mgr")
    _load_ssw()
end)
