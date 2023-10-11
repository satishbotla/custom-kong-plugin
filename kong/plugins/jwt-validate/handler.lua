local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

local JwtValidator = {
  PRIORITY = 1000,
  VERSION = "0.1.0",
}

function JwtValidator:access(conf)
  local jwt, err = jwt_decoder:new(conf)
  if err then
    return kong.response.exit(401, {message=err})
  end
  -- Get configured issuer
  local issuer = conf.issuer

  local claims, err = jwt:verify()
  if err then
    return kong.response.exit(401, {message="Invalid token"})
  end

  -- Validate claims like exp, iss etc
  if claims.exp < ngx.time() then
    return kong.response.exit(401, {message="Token expired"})
  end

  -- Validate issuer 
  if claims.iss ~= issuer then
    return kong.response.exit(401, {message="Invalid issuer"})
  end

  -- Add claims to request context
  kong.ctx.shared.jwt_claims = claims
end

return JwtValidator