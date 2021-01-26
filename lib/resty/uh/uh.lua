require("uh.pre_run")

local loader = require("uh.core")
local pl_utils = require("pl.utils")
local pl_path = require("pl.path")
local pl_file = require("pl.file")


local log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG

local dfs_settings = require("uh.settings")


-- Upstream health checker start point
-- The checker's default behavior can be change by the given ops tables
-- This options should be carefully setted.Due the this setting will only be
-- set at the time of checkers created.If options had been modified,the Nginx
-- need do a HUP reload or service Stop/Start to get this changed effected.
function _M.run()
    if worker_id() ~= 0 then
        return
    end

    -- pre init self check
    local ok, err = self_check()
    if not ok then
        log(ERR, err)
        error(err)
    end
    debug("pre init self check:ok")

    local ctx = {}

    -- load node init config
    local rules, err = loader.load_init_config(dfs_settings)
    if not rules then
        log(ERR,err)
    end

    ctx.node = rules.node
    ctx.checker = rules.checker

    debug("load node init config:ok")

    -- load upstream checker rules
    local rules, err = loader.load_upstream_rules(ctx.node)
    if not rules then
        errlog("init upstream health checker failed:", err)
        error(err)
    end
    ctx.upstreams = rules

    debug("load upstream rules ok")

    -- load running-time vars like upstreams,peers,upstream's rule
    -- collect_checkers(rules)

    debug(dkjson.encode(ctx,{indent = true}))
    -- spawn checkers
    -- spawn_checkers(ctx)
    return true
end
