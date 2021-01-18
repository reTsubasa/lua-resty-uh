local pl_utils = require("pl.utils")
local pl_path = require("pl.path")
local pl_file = require("pl.file")
local json = require("cjson.safe")
local dkjson = require("dkjson")
local stream_sock = ngx.socket.tcp
local log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local sub = string.sub
local fmt = string.format
local find = string.find
local re_find = ngx.re.find
local re_gmatch = ngx.re.gmatch
local new_timer = ngx.timer.at
local shared = ngx.shared
local debug_mode = ngx.config.debug
local concat = table.concat
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local ceil = math.ceil
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local pcall = pcall

local _M = {
    _VERSION = "0.1.0"
}

-- do OR version check
if not ngx.config or not ngx.config.ngx_lua_version or ngx.config.ngx_lua_version < 9005 then
    return nil, "ngx_lua 0.9.5+ required"
end

-- do ngx.upstream module check
local ok, upstream = pcall(require, "ngx.upstream")
if not ok then
    return nil, "ngx_upstream_lua module required"
end

local set_peer_down = upstream.set_peer_down
local get_primary_peers = upstream.get_primary_peers
local get_backup_peers = upstream.get_backup_peers
local get_upstreams = upstream.get_upstreams

local function warn(...)
    log(WARN, "healthcheck: ", ...)
end

local function errlog(...)
    log(ERR, "healthcheck: ", ...)
end

local function debug(...)
    -- print("debug mode: ", debug_mode)
    if debug_mode then
        log(DEBUG, "healthcheck: ", ...)
    end
end

-- Tool functions

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
    if not t then
        return nil, e
    end
    local r, e = cjson.decode(t)
    if not r then
        return nil, e
    end
    return r
end

-- module layer default settings
local pkg_dfs = {
    -- the default share dict for this package used
    dict = "healthcheck", -- required
    -- the path where config file stored
    rules_file = "/etc/healthcheck/rules.json",
    -- set default run mode "full"
    -- all run mode canbe "full","debug","bypass"
    mode = "full",
    -- for the default checker's behavior,if "config.json"lost
    type = "http",
    http_req = "GET /status HTTP/1.0\r\nHost: foo.com\r\n\r\n",
    timeout = 1000, -- 1sec
    interval = 1000 * 2, -- 2secs
    fall = 3,
    rise = 2,
    statuses = {200, 301, 302},
    concurrency = 1,
}

-- a key:{value_type,check_type,arg1,arg2,} nest-table for valid init settings
-- value_type : string,number,boolean,table,etc
-- check_type : 
        -- option:{choice1,choice2,...}
        -- len:(min,max)

local config_valid_def = {
    dict = {"string","len",1,20},
    rules_file = {"string","len",1,100},
    mode = {"string","option",{"full","debug","bypass"}},
    type = {"string","option",{"http","tcp"}},
    timeout = {"number","len",1,1000*10},
    interval = {"number","len",1,1000*60*60},
    fall = {"number","len",0,100},
    rise = {"number","len",0,100},
    statuses = {"table","regex",[[^\d\d\d$]]},
    concurrency = {"number","len",0,100},  

}

-- @table rule the rule table hold all the init settings
-- @return table rule if valid else return nil with error message
local function config_valid(rules)
    if type(rules) ~= "table" then
        return nil,"valid rules failed"
    end
    for k, v in pairs(rules) do
        defs = config_valid_def[k]
        if not defs then
            -- the key not_pre_defined
            v = "not_pre_defined"
        end
        if type(v) ~= defs[1] then
            return nil,fmt("rules key:%s format error.expected:%s",k,defs[1])
        end
        if defs[2] == "len" then
            if len(v)<def[3] or len(v)>def[4] then
                return nil,fmt("rules key:%s length error,expected at %s-%s",k,defs[3],defs[4])
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
                return nil,fmt("rule key:%s value error,expected %s",k,concat(defs[3]))
            end
        end
        if defs[2] == "regex" then
            local h = re_find(v,defs[3],"imjo")
            if not h then
                return nil,fmt("rule key:%s not as expected.",k)
            end
        end
    end
    return rules
end


-- load rule.json file from the give path and name args
-- @string path absolute path of the directory
-- @string name  full name of the file(with suffix)
-- @table rule table itself
local function load_config(path, name)
    if not path or not name then
        return nil, "file path and file name mustbe given"
    end

    local filepath = pl_path.normpath(path) .. pl_path.sep .. name
    local ok = pl_path.exists(filepath)
    if not ok then
        local ok, err = pl_file.write(filepath, pkg_dfs)
        if not ok then
            return nil, err
        end
        return pkg_dfs
    end
    local rule, err = read_json(filepath)
    if err then
        return nil, err
    end
    return config_valid(rule)
end

-- -- do the basic running env requirement checks
-- local function init_env_args(opts, ctx)

--     -- do check config path,
--     -- if not exist dump the default config to the config.json file
--     -- else load the local config,and set it into ctx
--     if opts.path then
--         local path = opts.path
--         local ok = pl_path.isdir(path)
--         if not ok then
--             ok = pl_path.isabs(pl_path.normpath(path))
--             if not ok then
--                 return nil, "config path arg error,please recheck"
--             else
--                 -- create the path
--                 ok = pl_path.mkdir(path)
--                 if not ok then
--                     return nil, fmt("create directory failed,path：%s", path)
--                 end
--             end
--         end
--         ctx.path = path
--     end

--     ctx.path = pkg_dfs.path

--     -- do load config

--     local def_conf, err = load_config(ctx.path, pkg_dfs.default_config_name)
--     if err then
--         return nil, err
--     end

--     ctx.def_conf = def_conf

--     -- finnally

--     return true
-- end

local function preprocess_peers(peers)
    local n = #peers
    for i = 1, n do
        local p = peers[i]
        local name = p.name

        if name then
            local from, to, err = re_find(name, [[^(.*):\d+$]], "jo", nil, 1)
            if from then
                p.host = sub(name, 1, to)
                p.port = tonumber(sub(name, to + 2))
            end
        end
    end
    return peers
end

local function load_upstream_config(ctx)
    local u = ctx.upstream
    local ppeers, err = get_primary_peers(u)
    if not ppeers then
        return nil, u .. "failed to get primary peers: " .. err
    end

    local bpeers, err = get_backup_peers(u)
    if not bpeers then
        return nil,  u .. "failed to get backup peers: " .. err
    end

    ctx.primary_peers = preprocess_peers(ppeers)
    ctx.backup_peers = preprocess_peers(bpeers)
    ctx.version = 0
    return true

end
local function gen_peer_key(prefix, u, is_backup, id)
    if is_backup then
        return prefix .. u .. ":b" .. id
    end
    return prefix .. u .. ":p" .. id
end

local function set_peer_down_globally(ctx, is_backup, id, value)
    local u = ctx.upstream
    local dict = ctx.dict
    local ok, err = set_peer_down(u, is_backup, id, value)
    if not ok then
        errlog("failed to set peer down: ", err)
    end

    if not ctx.new_version then
        ctx.new_version = true
    end

    local key = gen_peer_key("d:", u, is_backup, id)
    local ok, err = dict:set(key, value)
    if not ok then
        errlog("failed to set peer down state: ", err)
    end
end

local function peer_fail(ctx, is_backup, id, peer)
    debug("peer ", peer.name, " was checked to be not ok")

    local u = ctx.upstream
    local dict = ctx.dict

    local key = gen_peer_key("nok:", u, is_backup, id)
    local fails, err = dict:get(key)
    if not fails then
        if err then
            errlog("failed to get peer nok key: ", err)
            return
        end
        fails = 1

        -- below may have a race condition, but it is fine for our
        -- purpose here.
        local ok, err = dict:set(key, 1)
        if not ok then
            errlog("failed to set peer nok key: ", err)
        end
    else
        fails = fails + 1
        local ok, err = dict:incr(key, 1)
        if not ok then
            errlog("failed to incr peer nok key: ", err)
        end
    end

    if fails == 1 then
        key = gen_peer_key("ok:", u, is_backup, id)
        local succ, err = dict:get(key)
        if not succ or succ == 0 then
            if err then
                errlog("failed to get peer ok key: ", err)
                return
            end
        else
            local ok, err = dict:set(key, 0)
            if not ok then
                errlog("failed to set peer ok key: ", err)
            end
        end
    end

    -- print("ctx fall: ", ctx.fall, ", peer down: ", peer.down,
          -- ", fails: ", fails)

    if not peer.down and fails >= ctx.fall then
        warn("peer ", peer.name, " is turned down after ", fails,
                " failure(s)")
        peer.down = true
        set_peer_down_globally(ctx, is_backup, id, true)
    end
end

local function peer_ok(ctx, is_backup, id, peer)
    debug("peer ", peer.name, " was checked to be ok")

    local u = ctx.upstream
    local dict = ctx.dict

    local key = gen_peer_key("ok:", u, is_backup, id)
    local succ, err = dict:get(key)
    if not succ then
        if err then
            errlog("failed to get peer ok key: ", err)
            return
        end
        succ = 1

        -- below may have a race condition, but it is fine for our
        -- purpose here.
        local ok, err = dict:set(key, 1)
        if not ok then
            errlog("failed to set peer ok key: ", err)
        end
    else
        succ = succ + 1
        local ok, err = dict:incr(key, 1)
        if not ok then
            errlog("failed to incr peer ok key: ", err)
        end
    end

    if succ == 1 then
        key = gen_peer_key("nok:", u, is_backup, id)
        local fails, err = dict:get(key)
        if not fails or fails == 0 then
            if err then
                errlog("failed to get peer nok key: ", err)
                return
            end
        else
            local ok, err = dict:set(key, 0)
            if not ok then
                errlog("failed to set peer nok key: ", err)
            end
        end
    end

    if peer.down and succ >= ctx.rise then
        warn("peer ", peer.name, " is turned up after ", succ,
                " success(es)")
        peer.down = nil
        set_peer_down_globally(ctx, is_backup, id, nil)
    end
end

-- shortcut error function for check_peer()
local function peer_error(ctx, is_backup, id, peer, ...)
    if not peer.down then
        errlog(...)
    end
    peer_fail(ctx, is_backup, id, peer)
end

local function check_peer(ctx, id, peer, is_backup)
    local ok
    local name = peer.name
    local statuses = ctx.statuses
    local req = ctx.http_req

    local sock, err = stream_sock()
    if not sock then
        errlog("failed to create stream socket: ", err)
        return
    end

    sock:settimeout(ctx.timeout)

    if peer.host then
        -- print("peer port: ", peer.port)
        ok, err = sock:connect(peer.host, peer.port)
    else
        ok, err = sock:connect(name)
    end
    if not ok then
        if not peer.down then
            errlog("failed to connect to ", name, ": ", err)
        end
        return peer_fail(ctx, is_backup, id, peer)
    end

    local bytes, err = sock:send(req)
    if not bytes then
        return peer_error(ctx, is_backup, id, peer,
                          "failed to send request to ", name, ": ", err)
    end

    local status_line, err = sock:receive()
    if not status_line then
        peer_error(ctx, is_backup, id, peer,
                   "failed to receive status line from ", name, ": ", err)
        if err == "timeout" then
            sock:close()  -- timeout errors do not close the socket.
        end
        return
    end

    if statuses then
        local from, to, err = re_find(status_line,
                                      [[^HTTP/\d+\.\d+\s+(\d+)]],
                                      "joi", nil, 1)
        if err then
            errlog("failed to parse status line: ", err)
        end

        if not from then
            peer_error(ctx, is_backup, id, peer,
                       "bad status line from ", name, ": ",
                       status_line)
            sock:close()
            return
        end

        local status = tonumber(sub(status_line, from, to))
        if not statuses[status] then
            peer_error(ctx, is_backup, id, peer, "bad status code from ",
                       name, ": ", status)
            sock:close()
            return
        end
    end

    peer_ok(ctx, is_backup, id, peer)
    sock:close()
end

local function check_peer_range(ctx, from, to, peers, is_backup)
    for i = from, to do
        check_peer(ctx, i - 1, peers[i], is_backup)
    end
end

local function check_peers(ctx, peers, is_backup)
    local n = #peers
    if n == 0 then
        return
    end

    local concur = ctx.concurrency
    if concur <= 1 then
        for i = 1, n do
            check_peer(ctx, i - 1, peers[i], is_backup)
        end
    else
        local threads
        local nthr

        if n <= concur then
            nthr = n - 1
            threads = new_tab(nthr, 0)
            for i = 1, nthr do

                if debug_mode then
                    debug("spawn a thread checking ",
                          is_backup and "backup" or "primary", " peer ", i - 1)
                end

                threads[i] = spawn(check_peer, ctx, i - 1, peers[i], is_backup)
            end
            -- use the current "light thread" to run the last task
            if debug_mode then
                debug("check ", is_backup and "backup" or "primary", " peer ",
                      n - 1)
            end
            check_peer(ctx, n - 1, peers[n], is_backup)

        else
            local group_size = ceil(n / concur)
            nthr = ceil(n / group_size) - 1

            threads = new_tab(nthr, 0)
            local from = 1
            local rest = n
            for i = 1, nthr do
                local to
                if rest >= group_size then
                    rest = rest - group_size
                    to = from + group_size - 1
                else
                    rest = 0
                    to = from + rest - 1
                end

                if debug_mode then
                    debug("spawn a thread checking ",
                          is_backup and "backup" or "primary", " peers ",
                          from - 1, " to ", to - 1)
                end

                threads[i] = spawn(check_peer_range, ctx, from, to, peers,
                                   is_backup)
                from = from + group_size
                if rest == 0 then
                    break
                end
            end
            if rest > 0 then
                local to = from + rest - 1

                if debug_mode then
                    debug("check ", is_backup and "backup" or "primary",
                          " peers ", from - 1, " to ", to - 1)
                end

                check_peer_range(ctx, from, to, peers, is_backup)
            end
        end

        if nthr and nthr > 0 then
            for i = 1, nthr do
                local t = threads[i]
                if t then
                    wait(t)
                end
            end
        end
    end
end

local function upgrade_peers_version(ctx, peers, is_backup)
    local dict = ctx.dict
    local u = ctx.upstream
    local n = #peers
    for i = 1, n do
        local peer = peers[i]
        local id = i - 1
        local key = gen_peer_key("d:", u, is_backup, id)
        local down = false
        local res, err = dict:get(key)
        if not res then
            if err then
                errlog("failed to get peer down state: ", err)
            end
        else
            down = true
        end
        if (peer.down and not down) or (not peer.down and down) then
            local ok, err = set_peer_down(u, is_backup, id, down)
            if not ok then
                errlog("failed to set peer down: ", err)
            else
                -- update our cache too
                peer.down = down
            end
        end
    end
end

local function check_peers_updates(ctx)
    local dict = ctx.dict
    local u = ctx.upstream
    local key = "v:" .. u
    local ver, err = dict:get(key)
    if not ver then
        if err then
            errlog("failed to get peers version: ", err)
            return
        end

        if ctx.version > 0 then
            ctx.new_version = true
        end

    elseif ctx.version < ver then
        debug("upgrading peers version to ", ver)
        upgrade_peers_version(ctx, ctx.primary_peers, false)
        upgrade_peers_version(ctx, ctx.backup_peers, true)
        ctx.version = ver
    end
end

local function get_lock(ctx)
    local dict = ctx.dict
    local key = "l:" .. ctx.upstream

    -- the lock is held for the whole interval to prevent multiple
    -- worker processes from sending the test request simultaneously.
    -- here we substract the lock expiration time by 1ms to prevent
    -- a race condition with the next timer event.
    local ok, err = dict:add(key, true, ctx.interval - 0.001)
    if not ok then
        if err == "exists" then
            return nil
        end
        errlog("failed to add key \"", key, "\": ", err)
        return nil
    end
    return true
end

local function do_check(ctx)
    debug("healthcheck: run a check cycle")

    check_peers_updates(ctx)

    if get_lock(ctx) then
        check_peers(ctx, ctx.primary_peers, false)
        check_peers(ctx, ctx.backup_peers, true)
    end

    if ctx.new_version then
        local key = "v:" .. ctx.upstream
        local dict = ctx.dict

        if debug_mode then
            debug("publishing peers version ", ctx.version + 1)
        end

        dict:add(key, 0)
        local new_ver, err = dict:incr(key, 1)
        if not new_ver then
            errlog("failed to publish new peers version: ", err)
        end

        ctx.version = new_ver
        ctx.new_version = nil
    end
end


local function update_upstream_checker_status(ctx, success)
    local dict = ctx.dict
    local u = ctx.upstream

    if not success then
        cnt = 0
    else
        cnt = 1
    end
    local ok, err = dict:set(u, cnt)
    if not ok then
        errlog("update checker status failed: ", err)
    end
end


local check
check = function(premature, ctx)
    if premature then
        return
    end

    -- check the upstream name in ex_lists or not
    local name = ctx.upstream
    -- local val, err = in_ex_lists(name)

    -- if err then
    --     errlog(err)
    -- end

    -- if not val then
    --     local ok, err = pcall(do_check, ctx)
    --     if not ok then
    --         errlog("failed to run healthcheck cycle: ", err)
    --     end
    --     update_upstream_checker_status(ctx, true)
    -- else
    --     update_upstream_checker_status(ctx, false)
    -- end

    local ok, err = pcall(do_check, ctx)
    if not ok then
        errlog("failed to run healthcheck cycle: ", err)
    end

    local ok, err = new_timer(ctx.interval, check, ctx)
    if not ok then
        if err ~= "process exiting" then
            errlog("failed to create timer: ", err)
        end

        update_upstream_checker_status(ctx, false)
        return
    end
end


-- create the checkers by give options of each upstreams
local function spawn_checkers(ctx)
    local upstreams = get_upstreams()
    for i, upstream in ipairs(upstreams) do
        -- load upstream rule
        local u_rule,err = load_config(ctx.path, upstream..".json")
        if err then
            warn(upstream,":load rule failed,Use default settings.")
        end
        
        -- load upstream settings
        ctx.upstream = upstream

        local ok,err = load_upstream_config(ctx)
        if not ok then
            retrun nil,err
        end
        if ctx.mode == "debug" then
            check(nil, ctx)
        else
            local ok, err = new_timer(0, check, ctx)
            if not ok then
                return nil, "failed to create timer: " .. err
            end
        end
    
        return true
            
    end
end


-- a loader load the init configs
-- as the config source,json format file and http request endpoint(API) is supported.
-- type:file will be the default source.and the default file will located at /etc/healthcheck/rules.json
-- if not type specifed and default file is not existed,a new file will be created with default settings
-- if type is "api",the loader will load the config json file first,and send the http request for fetch the new rules
local function loader(ctx)
    debug("start loader...")
    local path = pkg_dfs.rules_file
    local ok = pl_path.exists(path)
    if not ok then
        debug("rule file not exist,create it")
        local ok, err = pl_file.write(path, pkg_dfs)
        if not ok then
            return nil, err
        end
    end
    local rule, err = read_json(filepath)
    if err then
        return nil, err
    end
    debug("load rules.work for valid")
    return config_valid(rule)

end


-- Upstream health checker start point
-- The checker's default behavior can be change by the given ops tables
-- This options should be carefully setted.Due the this setting will only be
-- set at the time of checkers created.If options had been modified,the Nginx
-- need do a HUP reload or service Stop/Start to get this changed effected.
function _M.run(opts)
    local ctx = new_tab(10, 10)

    local ok,err = loader(ctx)
    if not ok then
        errlog("init upstream health checker failed.",err)
        error(err)
    end

    debug("load rules ok")

    -- load running-time vars like upstreams,peers,upstream's rule
    spawn_checkers(ctx)
end

local ctx = {
    upstream = u,
    primary_peers = preprocess_peers(ppeers),
    backup_peers = preprocess_peers(bpeers),
    http_req = http_req,
    timeout = timeout,
    interval = interval,
    dict = shm_hc,
    fall = fall,
    rise = rise,
    statuses = statuses,
    version = 0,
    concurrency = concur
}

return _M
