# Name

some modify  for the lua-resty-upstream-healthcheck.

简约的自动检查所有upstream，添加了exclude_lists排除列表，用于排除特定upstream的检查

# Status

This library is still under early development but is already production ready.

# Synopsis

```nginx
http {
    lua_package_path "/path/to/lua-resty-upstream-healthcheck/lib/?.lua;;";

    # sample upstream block:
    upstream foo.com {
        server 127.0.0.1:12354;
        server 127.0.0.1:12355;
        server 127.0.0.1:12356 backup;
    }

    # the size depends on the number of servers in upstream {}:
    lua_shared_dict healthcheck 1m;

    lua_socket_log_errors off;

    init_worker_by_lua_block {
        local hc = require "resty.uh"

        local ok, err = hc.checker{
            shm = "healthcheck",  -- defined by "lua_shared_dict"
            exclude_lists = {"a.b.com","b.c.com",}, -- 排除清单，在排除清单中upstream，不会进行检查
            type = "http",

            http_req = "GET /status HTTP/1.0\r\nHost: foo.com\r\n\r\n",
                    -- raw HTTP request for checking

            interval = 2000,  -- run the check cycle every 2 sec
            timeout = 1000,   -- 1 sec is the timeout for network operations
            fall = 3,  -- # of successive failures before turning a peer down
            rise = 2,  -- # of successive successes before turning a peer up
            valid_statuses = {200, 302},  -- a list valid HTTP status code
            concurrency = 10,  -- concurrency level for test requests
        }
        if not ok then
            ngx.log(ngx.ERR, "failed to spawn health checker: ", err)
            return
        end


    }


}
```

# Install

`luarocks install lua-resty-uh`



# Methods

## checker

**syntax:** `ok, err = healthcheck.checker(options)`

**context:** *init_worker_by_lua*

Healthchecker for all the upstreams,exlude the record in the "exclude_lists".

Remove the the spawn_checker‘s option "upstream",Add new option "exclude_lists",if not exclude_lists given then all the upstreams will check.

默认检查所有的upstream后端，除非给定的options参数中，包含`exclude_lists`排除列表

注意：

- 原 `spawn_checker()`函数参数*options.upstream*不在生效，该参数无需给予。(即便给了，也不会生效)

- `exclude_lists`参数类型必须为*array-table*，每个在列表中的值都**不会**加入检查目标

  例:

  ```
  exclude_lists = {"a.b.com","b.c.com",}, 
  ```

- 核心实现为原模块的`spawn_checker()`，每个upstream会调用一次，所以可能会有多次返回



## status_page

**syntax:** `str, err = healthcheck.status_page()`

**context:** *any*

Generates a detailed status report for all the upstreams defined in the current NGINX server.

One typical output is

```
Upstream foo.com
    Primary Peers
        127.0.0.1:12354 up
        127.0.0.1:12355 DOWN
    Backup Peers
        127.0.0.1:12356 up

Upstream bar.com
    Primary Peers
        127.0.0.1:12354 up
        127.0.0.1:12355 DOWN
        127.0.0.1:12357 DOWN
    Backup Peers
        127.0.0.1:12356 up
```

If an upstream has no health checkers, then it will be marked by `(NO checkers)`, as in

```
Upstream foo.com (NO checkers)
    Primary Peers
        127.0.0.1:12354 up
        127.0.0.1:12355 up
    Backup Peers
        127.0.0.1:12356 up
```

If you indeed have spawned a healthchecker in `init_worker_by_lua*`, then you should really
check out the NGINX error log file to see if there is any fatal errors aborting the healthchecker threads.