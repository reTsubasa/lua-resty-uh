package = "lua-resty-uh"
version = "0.0.1-1"

description = {
  summary  = "Some modify  for the lua-resty-upstream-healthcheck",
  homepage = "https://github.com/reTsubasa/lua-resty-uh",
  license  = "MIT"
}

source = {
  url    = "git://github.com/reTsubasa/lua-resty-uh",
  tag = "master"
}


build = {
  type    = "builtin",
  modules = {
    ["resty.upstream.uh"]    = "lib/resty/upstream/healthcheck.lua",
  }
}
