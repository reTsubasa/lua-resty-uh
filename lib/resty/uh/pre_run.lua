-- A pre run self test list

-- do OR version check
if not ngx.config or not ngx.config.ngx_lua_version or ngx.config.ngx_lua_version < 9005 then
    error("ngx_lua 0.9.5+ required", 2) 
end

-- do ngx.upstream module check
local ok, upstream = pcall(require, "ngx.upstream")
if not ok then
    error("ngx_upstream_lua module required", 2)
end