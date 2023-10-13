local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

local fmt = string.format
local kong = kong
local type = type
local error = error
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local re_gmatch = ngx.re.gmatch
local ngx_log = ngx.log
local ngx_warn = ngx.WARN
local ngx_err = ngx.ERR

local JwtValidator = {
  PRIORITY = 1000,
  VERSION = "0.1.0",
}

--- Log what is needed
local function send_to_stdlog(ngxlevel, message)
  return ngx_log(ngxlevel, message)  -- this only works with LuaJIT
end

--- Retrieve a JWT in a request.
-- Checks for the JWT in URI parameters, then in cookies, and finally
-- in the configured header_names (defaults to `[Authorization]`).
-- @param conf Plugin configuration
-- @return token JWT token contained in request (can be a table) or nil
-- @return err
local function retrieve_tokens(conf)
  local token_set = {}
  local args = kong.request.get_query()
  for _, v in ipairs(conf.uri_param_names) do
    local token = args[v] -- can be a table
    if token then
      if type(token) == "table" then
        for _, t in ipairs(token) do
          if t ~= "" then
            token_set[t] = true
          end
        end

      elseif token ~= "" then
        token_set[token] = true
      end
    end
  end

  local var = ngx.var
  for _, v in ipairs(conf.cookie_names) do
    local cookie = var["cookie_" .. v]
    if cookie and cookie ~= "" then
      token_set[cookie] = true
    end
  end

  local request_headers = kong.request.get_headers()
  for _, v in ipairs(conf.header_names) do
    local token_header = request_headers[v]
    if token_header then
      if type(token_header) == "table" then
        token_header = token_header[1]
      end
      local iterator, iter_err = re_gmatch(token_header, "\\s*[Bb]earer\\s+(.+)")
      if not iterator then
        kong.log.err(iter_err)
        break
      end

      local m, err = iterator()
      if err then
        kong.log.err(err)
        break
      end

      if m and #m > 0 then
        if m[1] ~= "" then
          token_set[m[1]] = true
        end
      end
    end
  end

  local tokens_n = 0
  local tokens = {}
  for token, _ in pairs(token_set) do
    tokens_n = tokens_n + 1
    tokens[tokens_n] = token
  end

  if tokens_n == 0 then
    return nil
  end

  if tokens_n == 1 then
    return tokens[1]
  end

  return tokens
end

local function load_credential(jwt_secret_key)
  local row, err = kong.db.jwt_secrets:select_by_key(jwt_secret_key)
  if err then
    return nil, err
  end
  return row
end

function JwtValidator:access(conf)

  local token, err = retrieve_tokens(conf)
  kong.log.err("Token collected ", token, err)
  if err then
    return error(err)
  end
  kong.log.err("After token collected ")
  local token_type = type(token)
  if token_type ~= "string" then
    if token_type == "nil" then
      return false, { status = 401, message = "Unauthorized" }
    elseif token_type == "table" then
      return false, { status = 401, message = "Multiple tokens provided" }
    else
      return false, { status = 401, message = "Unrecognizable token" }
    end
  end

  local jwt, err = jwt_decoder:new(token)
  if err then
    return kong.response.exit(401, {message=err})
  end
  -- Get configured issuer
  local issuer = conf.issuer
  local claims = jwt.claims
  local header = jwt.header

  local jwt_secret_key = claims[conf.key_claim_name] or header[conf.key_claim_name]
  if not jwt_secret_key then
    return false, { status = 401, message = "No mandatory '" .. conf.key_claim_name .. "' in claims" }
  elseif jwt_secret_key == "" then
    return false, { status = 401, message = "Invalid '" .. conf.key_claim_name .. "' in claims" }
  end
  kong.log.err("jwt secret key collected ", jwt_secret_key)
  -- Retrieve the secret
  local jwt_secret_cache_key = kong.db.jwt_secrets:cache_key(jwt_secret_key)
  kong.log.err("jwt secret cache key collected ", jwt_secret_cache_key)
  local jwt_secret, err      = kong.cache:get(jwt_secret_cache_key, nil,
                                              load_credential, jwt_secret_key)
  if err then
    return error(err)
  end
  kong.log.err("after jwt secret key collected ", jwt_secret_key)
  if not jwt_secret then
    return false, { status = 401, message = "No credentials found for given '" .. conf.key_claim_name .. "'" }
  end

  local algorithm = jwt_secret.algorithm or "HS256"
  kong.log.err("algorithm collected ", algorithm)
  -- Verify "alg"
  if jwt.header.alg ~= algorithm then
    return false, { status = 401, message = "Invalid algorithm" }
  end
  kong.log.err("after algorithm collected ", algorithm)
  local jwt_secret_value = algorithm ~= nil and algorithm:sub(1, 2) == "HS" and
                           jwt_secret.secret or jwt_secret.rsa_public_key

  if conf.secret_is_base64 then
    jwt_secret_value = jwt:base64_decode(jwt_secret_value)
  end

  if not jwt_secret_value then
    return false, { status = 401, message = "Invalid key/secret" }
  end

  -- Now verify the JWT signature
  if not jwt:verify_signature(jwt_secret_value) then
    return false, { status = 401, message = "Invalid signature" }
  end

  -- Verify the JWT registered claims
  local ok_claims, errors = jwt:verify_registered_claims(conf.claims_to_verify)
  if not ok_claims then
    return false, { status = 401, errors = errors }
  end

  -- Validate issuer 
  if claims.iss ~= issuer then
  --  return kong.response.exit(401, {message="Invalid issuer"})
    kong.log.err("Invalid issuer ", claims.iss)
    return false, { status = 401, message = "Invalid issuer" }
  end

  -- Verify the JWT registered claims
  if conf.maximum_expiration ~= nil and conf.maximum_expiration > 0 then
    local ok, errors = jwt:check_maximum_expiration(conf.maximum_expiration)
    if not ok then
      return false, { status = 401, errors = errors }
    end
  end

  -- Retrieve the consumer
  local consumer_cache_key = kong.db.consumers:cache_key(jwt_secret.consumer.id)
  local consumer, err      = kong.cache:get(consumer_cache_key, nil,
                                            kong.client.load_consumer,
                                            jwt_secret.consumer.id, true)
  if err then
    return error(err)
  end

  -- However this should not happen
  if not consumer then
    return false, {
      status = 401,
      message = fmt("Could not find consumer for '%s=%s'", conf.key_claim_name, jwt_secret_key)
    }
  end

  set_consumer(consumer, jwt_secret, token)

  -- Add claims to request context
  kong.ctx.shared.jwt_claims = claims
end

return JwtValidator