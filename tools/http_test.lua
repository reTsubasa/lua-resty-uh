--- 一个简单的通过cosocket验证upstream health模块的脚本
-- 使用：shell中
-- resty http_test.lua

-- 参数调整：
-- 测试对象：test_target
-- http请求：req
-- socket超时：timeout

local stream_sock = ngx.socket.tcp
local fmt = string.format
local re_find = ngx.re.find
local sub = string.sub
local log = ngx.log
local ERR = ngx.ERR

-- 请求参数
local test_target = "10.10.100.70:9638"
local req = "GET /status HTTP/1.1\r\nHost: foo.com\r\n\r\n"
local timeout = 2000

local stages = {
    s0 = "解析对象",
    s1 = "初始化socket",
    s2 = "连接远端",
    s3 = "发送http请求",
    s4 = "接收响应"
}

local function do_log(args)
    local str = "\n"
    if args.stage then
        str = str .. "(" .. args.stage .. ")[" .. stages[args.stage] .. "]"
    end
    if args.status then
        str = str .. " 状态：" .. args.status
    end
    if args.err then
        str = str .. " 错误信息：" .. args.err
    end
    if args.extra then
        str = str .. " 描述：" .. args.extra
    end
    log(ERR, str)
end

local function http_test(name)
    -- s0
    local ip, port
    local from, to, err = re_find(name, [[^(.*):\d+$]], "jo", nil, 1)
    if not from then
        do_log({stage = "s0", status = "err", extra = "解析ip端口失败", err = err})
        return
    end

    ip = sub(name, 1, to)
    port = tonumber(sub(name, to + 2))

    do_log({stage = "s0", status = "ok", extra = fmt("IP:%s,PORT:%s", ip, port), err = err})

    local res = {}

    -- s1
    local sock, err = stream_sock()
    local s1 = {status = "", err = "", extra = "", stage = "s1"}
    if err then
        s1.status = "error"
        s1.err = err
        s1.extra = "初始化tcp socket失败"
        do_log(s1)
        return
    end
    s1.status = "ok"
    s1.err = nil
    s1.extra = nil
    -- log(ERR,fmt("\n%s:状态:%s,错误:%s,描述:%s",stages.s1,s1.status,s1.err,s1.extra))
    do_log(s1)

    sock:settimeout(timeout)

    -- s2
    local ok, err = sock:connect(ip, port)
    local s2 = {status = "", err = "", extra = "", stage = "s2"}
    if err then
        s2.status = "error"
        s2.err = err
        s2.extra = fmt("连接到IP:%s PORT:%s 失败", ip, port)
        do_log(s2)
        return
    end

    s2.status = "ok"
    s2.err = nil
    s2.extra = nil
    do_log(s2)

    -- s3
    local bytes, err = sock:send(req)
    local s3 = {status = "", err = "", extra = "", stage = "s3"}
    if err then
        s3.status = "error"
        s3.err = err
        s3.extra = fmt("发起http请求失败:请求URL:%s,返回字节：%s", req, bytes)
        do_log(s3)
        return
    end
    s3.status = "ok"
    s3.err = nil
    s3.extra = bytes
    do_log(s3)

    -- s4
    local status_line, err = sock:receive("*a")
    --log(ERR,status_line)
    local s4 = {status = "", err = "", extra = "", stage = "s4"}
    if err then
        s4.status = "error"
        s4.err = err
        s4.extra = fmt("接收http响应错误:%s", status_line or "")
        do_log(s4)
        return
    end

    local from, to, err = re_find(status_line, [[^HTTP/\d+\.\d+\s+(\d+)]], "joi", nil, 1)
    if err then
        s4.status = "error"
        s4.err = err
        s4.extra = fmt("解析响应体失败:%s", status_line)
        do_log(s4)
        return
    else
        local status = tonumber(sub(status_line, from, to))
        s4.status = "ok"
        s4.err = nil
        s4.extra = fmt("解析响应码:%s", status)
    end
    do_log(s4)

    sock:close()
    -- return res
end

http_test(test_target)
