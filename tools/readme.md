## 测试工具

因为健康度检查运行在nginx中，如果有部分节点不如预期运行，排错难度还是很大。

所以提供了本工具。

## 依赖

- `luarocks install penlight`

- `resty-cli` 如果使用openresty源码安装，默认会在`/usr/local/openresty/bin`路径下。如果使用官方的二进制包安装，则可通过安装名为`openresty-resty`的包

## 安装

下载`http_test.lua`到任意路径下即可。

## 使用

```shell
bash: resty http_test.lua -t 192.168.1.1:2222
```



## 参数

- `-t`  (必填) 需要测试的目标.如果有端口使用"HOST:PORT"形式。

  如  `-t 192.168.1.1:80`即检查upstream 192.168.1.1的80端口



以下参数均为**可选**参数

- `-o`  sockect超时时间,单位:ms,默认值：2000

  如`-o 5000`，即socket超时时间为5秒。注意该超时时间从socket初始化成功后即开始计时

-  `-v`   verbose mode 详细输出模式，默认为启用

- `-n`  http请求中的HOST名称，默认值：`foo.com`

  指定向后端发起的http请求的HOST名称，注意该HOST名称不影响检查对象

- ` -l ` http请求中的接口名称，默认值：`/`

  指定向后端发起的http请求的接口名称



## 例子

- ex1
```bash
# resty /home/admin/t.lua -t 1.1.1.1:80 -n "h.com" -o 10000

(1/5)解析对象        OK  描述：IP:1.1.1.1, 端口:80
(2/5)初始化socket    OK
(3/5)连接远端        OK  描述：连接成功:1.1.1.1:80
(4/5)发送http请求    OK  描述：发送请求:GET / HTTP/1.1
Host: h.com


(5/5)接收响应        OK  描述：响应码:302 执行时间:0.01800012588501
```



- ex2

```bash
# resty /home/admin/t.lua -t 2.2.2.2:100 -l status

(1/5)解析对象        OK  描述：IP:2.2.2.2, 端口:100
(2/5)初始化socket    OK
(3/5)连接远端     ERROR  错误信息：timeout 描述：执行时间:2.0019998550415
```



- ex3

```bash
# resty /home/admin/t.lua -t 127.0.0.1:80
(1/5)解析对象        OK  描述：IP:127.0.0.1, 端口:80
(2/5)初始化socket    OK
(3/5)连接远端        OK  描述：连接成功:127.0.0.1:80
(4/5)发送http请求    OK  描述：发送请求:GET / HTTP/1.1
Host: foo.com


(5/5)接收响应        OK  描述：响应码:403 执行时间:0.015000104904175
```



## Todo

- 由于原函数中网络部分函数和部分逻辑有耦合，导致测试工具无法直接调用库函数仿真