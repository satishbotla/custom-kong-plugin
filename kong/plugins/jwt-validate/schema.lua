local typedefs = require "kong.db.schema.typedefs"

-- Schema with issuer attribute
local schema = {
  name = "jwt-validate",
  fields = {
    issuer = {required = true, type = "string"}
  }
}

return schema