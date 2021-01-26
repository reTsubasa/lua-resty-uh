local _M = {}


-- define the default settings's format 
local  default_settings_format= {
    node = {
        dict = {"string", "len", 1, 20},
        rules_file = {"string", "len", 1, 100},
        mode = {"string", "option", {"full", "debug", "bypass"}}
    },
    checker = {
        type = {"string", "option", {"http", "tcp"}},
        timeout = {"number", "len", 1, 1000 * 10},
        interval = {"number", "len", 1, 1000 * 60 * 60},
        fall = {"number", "len", 0, 100},
        rise = {"number", "len", 0, 100},
        statuses = {"table", "regex", [[^\d\d\d$]]},
        concurrency = {"number", "len", 0, 100},
        enable = {"boolean"}
    }
}
-- @table rules the rule table hold all the init settings
-- @table config_valid_def format defined
-- @return table rule if valid else return nil with error message
local function config_valid(rules,config_valid_def)
    if type(rules) ~= "table" then
        return nil, "valid rules failed"
    end
    for k, v in pairs(rules) do
        defs = config_valid_def[k]
        if not defs then
            -- the key not_pre_defined
            v = "not_pre_defined"
        else
            if type(v) ~= defs[1] then
                return nil, fmt("rules key:%s format error.expected:%s", k, defs[1])
            end
            if defs[2] then
                if defs[2] == "len" then
                    if len(v) < defs[3] or len(v) > defs[4] then
                        return nil, fmt("rules key:%s length error,expected at %s-%s", k, defs[3], defs[4])
                    end
                end
                if defs[2] == "option" then
                    local flag
                    for _, opt in ipairs(defs[3]) do
                        if opt == v then
                            flag = true
                        end
                    end
                    if not flag then
                        return nil, fmt("rule key:%s value error,expected %s", k, concat(defs[3]))
                    end
                end
                if defs[2] == "regex" then
                    for _, value in ipairs(v) do
                        local h, sp, err = re_find(value, defs[3], "imjo")
                        if not h then
                            return nil, fmt("rule key:%s value: %s not as expected.", k, value)
                        end
                    end
                end
            end
        end
    end
    return true
end

function _M.default_settings(rules)
    -- node
    local ok,err = config_valid(rules.node, default_settings_format.node)
    if not ok then
        return nil,err
    end
    -- checker
    local ok,err = config_valid(rules.checker, default_settings_format.checker)
    if not ok then
        return nil,err
    end
    return true
end


function _M.rules(rules)
    -- TODO: valid rules value and format
    return false
end

return _M