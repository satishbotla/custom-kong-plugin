package = "kong-jwt-validate"
version = "0.1.0-1"
source = {
  url = "https://github.com/satishbotla/custom-kong-plugin.git"
}

description = {
  summary = "Custom JWT validation plugin for Kong",
  detailed = [[
    Provides custom JWT token validation for Kong.
  ]],
  license = "MIT",
  homepage = "https://github.com/myuser/kong-jwt-validate"
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