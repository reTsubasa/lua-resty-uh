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
            ha_interval = 20， -- ha模式检查周期，单位秒
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

# New Feature
- 默认检查所有upstream *version 0.0.2*
- 在Nginx HA部署下，排除备机向upstream发起检查的简单过滤 *version 0.0.4*
- 


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

**opts：**

- shm ：通过**lua_shared_dict**指令分配的缓存名称
- type：检查协议，目前只支持**http**
- http_req：http请求原始信息
- interval：每一个upstream检查的间隔时间
- timeout：检查网络超时时间
- fall：失败次数，检查失败大于该失败次数后，节点下线
- rise：成功次数，检查成功大于成功次数后，节点上线
- valid_statuses ：节点健康的http 响应码列表
- concurrency：同一个upstream组中，同时并发检查后端的轻线程数

*new opts:*

- exclude_lists：(optional)。 *version 0.0.2* 

  显示申明的一个列表，指明不检查指定后端upstream名称。 它是一个`array-table`类型的值。

- ha_interval: (optional)。 *version 0.0.4* 

  用于在HA部署模式下，使备用Nginx不发起向后端的检查，以降低节点检查的总请求量。

  它的输入类型是一个**数字**，单位：**秒**,最小值：**10**，用于声明是否需要HA部署模式下的主/备状态检查得定时器的**时间间隔**。

  检查的本质是通过检查`eth0`或`bond0`接口下，`ipv4` `inet`条目数实现的。默认场景下`eth0`或`bond0`接口下`inet`条目数大于**1**条时，认为该节点是主节点。

  虽然该实现上不足之处明显，不过总的来说，大多数场景下并不会造成更坏的情况。**除非你的网络不在`eth0`或`bond0`接口下提供服务的情况下，同时启用了该配置，那么健康度检查功能将会失效。**





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