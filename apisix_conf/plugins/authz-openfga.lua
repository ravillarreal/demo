--Copyright 2024 TwoGenIdentity. All Rights Reserved.
--
--Licensed under the Apache License, Version 2.0 (the "License");
--you may not use this file except in compliance with the License.
--You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
--Unless required by applicable law or agreed to in writing, software
--distributed under the License is distributed on an "AS IS" BASIS,
--WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--See the License for the specific language governing permissions and
--limitations under the License.

local core     = require("apisix.core")
local http     = require("resty.http")
local uuid     = require("resty.jit-uuid")
local ngx      = ngx

local plugin_name = "authz-openfga"
local plugin_cache_name = "authz_openfga_authorization_model"

local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        store_id = {type = "string"},
        authorization_model_id = {type = "string"},
        ssl_verify = {type = "boolean", default = false},
        -- Soporte para mTLS
        client_cert = {type = "string", description = "Certificado del cliente para mTLS"},
        client_key  = {type = "string", description = "Llave privada para mTLS"},
        timeout = {type = "integer", minimum = 1, default = 3000},
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", default = 60000},
        keepalive_pool = {type = "integer", default = 5},
        check = {
            type = "object",
            properties = {
                condition = {type = "string", enum = {"AND", "OR"}, default = "AND"},
                tuples = {
                    type = "array",
                    items = {
                        type = "object",
                        properties = {
                            user_id = {type = "string"},
                            user_type = {
                                description = "User Type",
                                type = "string",
                                default = "user",
                            }, -- e.g., "claim::sub"
                            relation = {type = "string", default = "assignee"},
                            object_type = {type = "string", default = "role"},
                            object_id = {type = "string"}, -- soporta variables como $remote_addr o $route_id
                        },
                        required = {"user_id", "object_type", "object_id"},
                    }
                }
            },
            required = {"condition", "tuples"},
        },
    },
    required = {"host", "check"},
}

local _M = {
    version = 0.3,
    priority = 2599,
    name = plugin_name,
    schema = schema
}

-- Helper para peticiones HTTP centralizado (Maneja mTLS y errores)
local function request_fga(conf, endpoint, method, body)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)
    
    local params = {
        method = method,
        body = body and core.json.encode(body) or nil,
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = conf.auth_header, -- Enviamos el JWT de Zitadel
        },
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        -- Configuración mTLS si existe
        ssl_client_cert = conf.client_cert,
        ssl_client_key = conf.client_key,
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    local res, err = httpc:request_uri(conf.host .. endpoint, params)
    if not res then return nil, err end
    if res.status >= 400 then return nil, "FGA returned " .. res.status end

    return core.json.decode(res.body)
end

-- Descubrimiento automático del Store y Model (con Cache)
local function get_authz_model(conf)
    local dict = ngx.shared[plugin_cache_name]
    local cache_key = conf.host .. (conf.store_id or "default")
    
    if dict then
        local cached = dict:get(cache_key)
        if cached then return core.json.decode(cached) end
    end

    -- 1. Obtener Store si no se provee
    local store_id = conf.store_id
    if not store_id then
        local stores_data, err = request_fga(conf, "/stores", "GET")
        if not stores_data or not stores_data.stores then return nil, err or "no stores" end
        store_id = stores_data.stores[1].id
    end

    -- 2. Obtener último modelo del store
    local model_data, err = request_fga(conf, "/stores/" .. store_id .. "/authorization-models", "GET")
    if not model_data then return nil, err end
    
    local model_id = model_data.authorization_models[1].id
    local result = { store_id = store_id, model_id = model_id }

    if dict then
        dict:set(cache_key, core.json.encode(result), 600) -- Cache por 10 min
    end

    return result
end

-- Extraer sub o claim de X-Userinfo (Base64 JSON)
local function get_user_from_header(ctx)
    local val = core.request.header(ctx, "X-Userinfo")
    if not val then return nil end
    
    local decoded = ngx.decode_base64(val)
    if not decoded then return nil end
    
    local data = core.json.decode(decoded)
    return data and (data.sub or data.id)
end

function _M.access(conf, ctx)
    local auth_header = core.request.header(ctx, "authorization")
    core.log.error("AUTH HEADER: " .. auth_header)

    local headers = core.request.headers(ctx)

    for name, value in pairs(headers) do
        -- Using APISIX core logger to print to error.log
        core.log.error("Header: " .. name .. " = " .. value)
    end

    if not auth_header then
        core.log.error("No se encontró token de tu Idp en el header Authorization")
        return 401, {message = "Unauthenticated: Missing Token"}
    end

    conf.auth_header = auth_header

    local authz, err = get_authz_model(conf)
    if not authz then
        core.log.error("FGA model discovery failed: ", err)
        return 503, {message = "Authz service unavailable"}
    end

    local user_id = get_user_from_header(ctx)
    core.log.error("USER_ID: " .. user_id)
    if not user_id then
        return 401, {message = "User info missing"}
    end

    local is_batch = #conf.check.tuples > 1
    local checks = {}

    for _, tuple in ipairs(conf.check.tuples) do
        local obj_id = core.utils.resolve_var(tuple.object_id, ctx.var)
        local t_key = {
            user = tuple.user_type .. ":" .. user_id,
            relation = tuple.relation,
            object = tuple.object_type .. ":" .. obj_id
        }

        if is_batch then
            core.table.insert(checks, { tuple_key = t_key, correlation_id = uuid() })
        else
            core.table.insert(checks, { tuple_key = t_key })
        end
    end

    -- Preparar Body según tipo de check
    local endpoint = "/stores/" .. authz.store_id .. (is_batch and "/batch-check" or "/check")
    local payload = {
        authorization_model_id = authz.model_id,
        [is_batch and "checks" or "tuple_key"] = is_batch and checks or checks[1].tuple_key
    }

    local data, err = request_fga(conf, endpoint, "POST", payload)
    if not data then
        core.log.error("FGA check failed: ", err)
        return 403
    end

    -- Evaluación de resultados
    local allowed = false
    if is_batch then
        local success_count = 0
        for _, res in ipairs(data.result or {}) do
            if res.allowed then success_count = success_count + 1 end
        end
        
        if conf.check.condition == "AND" then
            allowed = (success_count == #checks)
        else
            allowed = (success_count > 0)
        end
    else
        allowed = data.allowed
    end

    if not allowed then
        return 403, {message = "Forbidden by OpenFGA"}
    end
end

return _M