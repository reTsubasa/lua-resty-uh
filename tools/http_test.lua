local lapp = require("pl.lapp")
local stream_sock = ngx.socket.tcp
local re_find = ngx.re.find
local log = ngx.log
local ERR = ngx.ERR

local sub = string.sub
local fmt = string.format

local version = "0.1.2"

local function std_out(opts, process, total, pro_name)
    local mode = opts.verbose or false
    local flag = false

    if opts.status == "error" or mode then
        flag = true
    end

    if process == total then
        flag = true
    end

    if flag then
        local str = ""
        local header = "(" .. process .. "/" .. total .. ")" .. [[\033[1;34;40m]] .. pro_name .. [[\033[0m]] .. " "
        str = str .. header

        if opts.status then
            local color_f
            local color_b = [[\033[0m]]
            if opts.status == "ok" then
                color_f = [[\033[1;32;40m   ]]
            else
                color_f = [[\033[1;31;40m]]
            end
            str = str .. color_f .. string.upper(opts.status) .. color_b .. " "
        end

        if opts.err then
            str = str .. " 错误信息：" .. opts.err
        end

        if opts.des then
            str = str .. " 描述：" .. opts.des
        end

        -- str = str .."\n"
        -- io.write(str)
        local cmd = "echo -e " .. '"' .. str .. '"'
        os.execute(cmd)
    end
end

local function msg_encode(opts, status, err, des)
    if status == "ok" or ("error") then
        opts.status = status
    else
        log(ERR, "status error")
    end

    if err then
        opts.err = err
    end
    if des then
        opts.des = des
    end
end

local function phase_name(opts, process, total, pro_name)
    local name = opts.name
    local ip, port
    local from, to, err = re_find(name, [[^(.*):\d+$]], "jo", nil, 1)
    if not from then
        msg_encode(opts, "error", err, "解析ip端口失败")
        std_out(opts, process, total, pro_name)
        return nil, opts.des
    end

    ip = sub(name, 1, to)
    port = tonumber(sub(name, to + 2))

    opts["ip"] = ip
    opts["port"] = port

    msg_encode(opts, "ok", nil, fmt("IP:%s, 端口:%s", ip, port))
    std_out(opts, process, total, pro_name)

    return true
end

local function init_socket(opts, process, total, pro_name)
    local sock, err = stream_sock()
    if err then
        msg_encode(opts, "error", err, "初始化socket失败")
        std_out(opts, process, total, pro_name)
        return nil, opts.des
    end

    opts.exectime = ngx.now()
    sock:settimeout(opts.timeout)

    opts["sock"] = sock

    msg_encode(opts, "ok")
    std_out(opts, process, total, pro_name)

    return true
end

local function con_sock(opts, process, total, pro_name)
    local sock = opts.sock
    local ok, err = sock:connect(opts.ip, opts.port)
    if err == "timeout" then
        local exec_time = ngx.now() - opts.exectime
        msg_encode(opts, "error", err, "执行时间:" .. exec_time)
        std_out(opts, process, total, pro_name)
        sock:close()
        return nil, opts.des
    end

    if err then
        msg_encode(opts, "error", err, fmt("连接失败: IP:%s,PORT:%s", opts.ip, opts.port))
        std_out(opts, process, total, pro_name)
        return nil, opts.des
    end

    msg_encode(opts, "ok", nil, fmt("连接成功:%s", opts.name))
    std_out(opts, process, total, pro_name)
    return true
end

local function send_req(opts, process, total, pro_name)
    local sock = opts.sock
    local bytes, err = sock:send(opts.req)
    if err == "timeout" then
        local exec_time = ngx.now() - opts.exectime
        msg_encode(opts, "error", err, "执行时间:" .. exec_time)
        std_out(opts, process, total, pro_name)
        sock:close()
        return nil, opts.des
    end

    if err then
        msg_encode(opts, "error", err, "发送请求失败")
        std_out(opts, process, total, pro_name)
        return nil, opts.des
    end

    msg_encode(opts, "ok", nil, fmt("发送请求:%s", opts.req))
    std_out(opts, process, total, pro_name)
    return true
end

local function wait_resp(opts, process, total, pro_name)
    local sock = opts.sock
    local status_line, err = sock:receive()
    if err == "timeout" then
        local exec_time = ngx.now() - opts.exectime
        msg_encode(opts, "error", err, "执行时间:" .. exec_time)
        std_out(opts, process, total, pro_name)
        sock:close()
        return nil, opts.des
    end

    if not status_line then
        local exec_time = ngx.now() - opts.exectime
        msg_encode(opts, "error", err, "没有获取响应." .. "执行时间:" .. exec_time)
        std_out(opts, process, total, pro_name)
        sock:close()
        return nil, opts.des
    end

    local from, to, err = re_find(status_line, [[^HTTP/\d+\.\d+\s+(\d+)]], "joi", nil, 1)
    if err or (not from) then
        local exec_time = ngx.now() - opts.exectime

        msg_encode(opts, "error", err, fmt("没有获取到响应码.响应内容:%s ", status_line) .. "执行时间:" .. exec_time)
        std_out(opts, process, total, pro_name)
        sock:close()
        return nil, opts.des
    end

    local code = tonumber(sub(status_line, from, to))
    local exec_time = ngx.now() - opts.exectime
    msg_encode(opts, "ok", nil, fmt("响应码:%s ", code) .. "执行时间:" .. exec_time)
    std_out(opts, process, total, pro_name)

    sock:close()
    return true
end

local process_arr = {
    {
        name = "解析对象    ",
        func = phase_name
    },
    {
        name = "初始化socket",
        func = init_socket
    },
    {
        name = "连接远端    ",
        func = con_sock
    },
    {
        name = "发送http请求",
        func = send_req
    },
    {
        name = "接收响应    ",
        func = wait_resp
    }
}

local function http_req(opts)
    local process_num = #process_arr
    for i, v in ipairs(process_arr) do
        opts["err"] = false
        opts["status"] = ""
        opts["des"] = false
        if v.func then
            local _, err = v.func(opts, i, process_num, v.name)
            if err then
                return
            end
        end
    end
end

local str =
    [[


Upstream Health Test tool                      v:%s

  必须使用 resty-cli (Openresty-Resty) 执行本工具

  -t (string)  需要测试的目标.如果有端口使用"HOST:PORT"形式
  -o (number default 2000) sockect超时时间,单位:ms,默认值：2000
  -v (boolean default true ) verbose mode
  -n (string default foo.com) http请求中的HOST名称
  -l (string default /) http请求中的接口名称

  ex:
  1. bash$ resty http_test -t 192.168.1.1:2222
  2. bash$ resty http_test -t 192.168.1.1:2222 -o 5000
  3. bash$ resty http_test -t 192.168.1.1:2222 -l test -n domain.com


  ]]

local help = fmt(str,version)

local args = lapp(help)

local opts = {}

if not args.t then
    lapp(help)
    lapp.quit()
    return
end

opts["name"] = args.t
opts["timeout"] = args.o

local host = args.n

local location = args.l
if sub(location, 1, 2) ~= "/" then
    location = "/" .. location
end
opts["req"] = fmt("GET %s HTTP/1.1\r\nHost: %s\r\n\r\n", location, host)

opts["verbose"] = args.v or false

http_req(opts)
