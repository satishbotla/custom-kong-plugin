package = "kong-jwt-validate"
version = "0.1.0-1"
source = {
  url = "git://github.com/satishbotla/custom-kong-plugin.git"
}

description = {
  summary = "Custom JWT validation plugin for Kong kong kong more more another asdasdaddsasd ",
  detailed = [[
    Provides custom JWT token validation for Kong kong kong kong more another adad ds.
  ]],
  license = "MIT",
  homepage = "https://github.com/satishbotla/custom-kong-plugin"
}

dependencies = {
  "lua >= 5.1"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.jwt-validate.handler"] = "kong/plugins/jwt-validate/handler.lua",
    ["kong.plugins.jwt-validate.schema"] = "kong/plugins/jwt-validate/schema.lua"
  }
}