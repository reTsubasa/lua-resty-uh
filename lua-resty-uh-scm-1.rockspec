package = "lua-resty-uh"
version = "scm-1"

description = {
  summary  = "Some modify  for the lua-resty-upstream-healthcheck",
  homepage = "https://github.com/reTsubasa/lua-resty-uh",
  license  = "MIT"
}

source = {
  url    = "git://github.com/reTsubasa/lua-resty-uh",
  branch = "scm"
}
dependencies = {
  "penlight",
  "dkjson",
  "lua-resty-jit-uuid",
}


build = {
  type    = "builtin",
  modules = {
    ["resty.uh"]    = "lib/resty/uh/uh.lua",
    ["resty.core"]    = "lib/resty/uh/core.lua",
    ["resty.pre_run"]    = "lib/resty/uh/pre_run.lua",
    ["resty.settings"]    = "lib/resty/uh/settings.lua",
    ["resty.valid"]    = "lib/resty/uh/valid.lua",
  }
}
