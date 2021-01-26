-- Module default settings
-- module layer default settings
local defaults = {}

-- for node default settings
defaults.node = {
    -- the default share dict for this package used
    dict = "healthcheck",
    -- the path where config file stored
    path = "/etc/healthcheck",
    config_name = "config.json"
    -- set default run mode "full"
    -- all run mode canbe "full","debug","bypass"
    mode = "full"
    -- target rules
    rules_name = "rules.json"
    rules_url = 
}

-- for checker default settings
defaults.checker = {
    -- for the default checker's behavior,if "config.json"lost
    type = "http",
    http_req = "GET /status HTTP/1.0\r\nHost: foo.com\r\n\r\n",
    timeout = 1000, -- 1sec
    interval = 1000 * 2, -- 2secs
    fall = 3,
    rise = 2,
    statuses = {200, 301, 302},
    concurrency = 1
}

return defaults