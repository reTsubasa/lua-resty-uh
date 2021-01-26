local uuid = require("resty.jit-uuid")
local pl_utils = require("pl.utils")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local valid = require("resty.uh.valid")

local log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local fmt = string.format

local host_name = ngx.var.hostname

local _M = {}

-- gen a uuid v4 format id by given seed
-- if seed not provided the host_name will be the default
local function gen_id(seed)
    seed = seed or host_name
    uuid.seed(seed)
    return uuid()
end

-- write then content to the position
-- @string position the abs_path of file
-- @param content the info write to file,if content type is a table,this will auto translate to json file
-- @table opts control the write behavior,like mode,pp(pretty_print),etc)
local function write(position, content, opts)
    if not opts then
        opts = {}
    end

    local mode = opts.mode or "w+"
    local file = io.open(position, mode)
    if not file then
        return nil, fmt("Write file failed,path: %s", position)
    else
        if type(content) == "table" then
            if opts.pp then
                content = dkjson.encode(content, {indent = true})
            else
                content = cjson.encode(content)
            end
        end

        file:write(content)
        file:close()
    end
    return true
end

-- read file by given path from local disk
-- @string postion abs_path of the file
local function read(position)
    local file = io.open(position, "r")
    if file then
        local text = file:read("*a")
        file:close()
        return text
    end
    return nil, "file not exist"
end

-- read json file,by given path,return a table on succ
-- nil,with err message if failed
-- todo:return the read file's md5 as second return
local function read_json(p)
    local t, e = read(p)
    if not t or #t == 0 then
        return nil, e
    end
    local r, e = cjson.decode(t)
    if not r then
        return nil, e
    end
    return r
end

function _M.load_init_config(default_settings)
    log(DEBUG, "start init config load")

    local id, err = gen_id()
    if not id then
        return nil, err
    end

    local path = pl_path.normpath(default_settings.node.path) .. pl_path.sep .. default_settings.node.config_name
    local ok, err = pl_path.exists(path)
    if not ok then
        log(DEBUG, fmt("path:%s not exist,create it"))
        local ok, err = write(path, default_settings, {pp = true})
        if not ok then
            log(ERR, fmt("write default settings to file %s failed.due %s", path, err))
            log(ERR, "init from hard code settings")
        -- return default_settings
        end
    end

    local rules, err = read_json(path)
    if not rules then
        log(DEBUG, fmt("read file at %s error,overwrite with default settings", path))
        local ok, err = write(path, default_settings, {pp = true})
        if not ok then
            log(ERR, fmt("write default settings to file %s failed.due %s", path, err))
            log(ERR, "init from hard code settings")
        -- return default_settings
        end
    end

    rules = rules or default_settings
    rules.node_id = id

    local ok, err = valid.default(rules)
    if not ok then
        log(ERR, err)
        return nil, err
    end
end


-- load the checker's rules
-- checker's rules 
function _M.load_upstream_rules(node_settings)
    log(DEBUG, "start load upstream rules")
    if node_settings.rules_url then
    -- TODO: load rules from url
    end

    local path = pl_path.normpath(node_settings.path) .. pl_path.sep .. node_settings.rules_name
    local ok, err = pl_path.exists(path)
    if not ok then
        return nil
    end

    local rules, err = read_json(path)
    if not rules then
        log(DEBUG, fmt("read file at %s error,overwrite with blank settings", path))
        local ok, err = write(path, {})
        if not ok then
            log(ERR, fmt("write default settings to file %s failed.due %s", path, err))
            log(ERR, "init from hard code settings")
        -- return default_settings
        end
        return {}
    else
        local ok, err = valid.rules(rules)
        if not ok then
            log(ERR, err)
            return {}
        end
        return rules
    end
end

return _M
