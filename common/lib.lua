local Config = require("config")
local Option = Config.option
local Flag = Config.flag
local Key = Config.key
local Utils = require("utils")
local Libinjection = require "libinjection"

local function getIp(re)
    -- 由于waf是直接暴露在公网中的 因此只需要采用remote_addr即可
    -- 而使用 X-Real-IP  X_Forwarded_For会给攻击者伪造ip的机会
    -- local client_IP = ngx.req.get_headers()["X-Real-IP"]
    -- if client_IP == nil then
    --     client_IP = ngx.req.get_headers()["X_Forwarded_For"]
    -- end
    if client_IP == nil then
        client_IP = ngx.var.remote_addr
    end
    return client_IP
end

local function cookieCheck(flag,red)
    local cookies =  ngx.var.http_cookie
    local set,err
    if flag==Flag.base then
        set ,err = red:ZRANGE(Utils.base_key_gen("COOKIE"),0,-1)
    elseif flag==Flag.custom then
        set, err = red:ZRANGE(Utils.custom_key_gen("COOKIE"),0,-1)
    end
    
    for _,line in ipairs(set) do
        if ngx.re.match(cookies,line,"jo") ~= nil then
            return false
        end
    end
    return true
end


local function postArgsCheck(flag,red)
    ngx.req.read_body()
    local post_args = ngx.req.get_post_args()
    local set,err
    if flag==Flag.base then
        set ,err = red:zrange(Utils.base_key_gen("POST"),0,-1)
    elseif flag==Flag.custom then
        set,err = red:zrange(Utils.custom_key_gen("POST"),0,-1)
    end
    if err~=nil then ngx.log(ngx.ERR,"Failed to retrive Data in postArgsCheck err: ",err) end
    for _,line in ipairs(set) do
        for _,item in pairs(post_args) do
            if ngx.re.match(item,line,"jo") ~= nil then return false end
        end
    end
    return true
end

local function headerCheck(flag,red)
    local headers = ngx.req.get_headers()
    local set,err
    if flag==Flag.base then
        set ,err = red:zrange(Utils.base_key_gen("HEADER"),0,-1)
    elseif flag==Flag.custom then
        set,err = red:zrange(Utils.custom_key_gen("HEADER"),0,-1)
    end
    if err~=nil then ngx.log(ngx.ERR,"Failed to retrive Data in headerCheck err: ",err) end
    for _,line in ipairs(set) do
        for _ ,item in pairs(headers) do
            if ngx.re.match(item,line,"jo") ~= nil then return false end
        end
    end
    return true
end


-- 对于redis:get此类查询 若不存在会返回一个ngx.null
-- 而它参与逻辑运算为true,因此要判断一哈
-- debug,然后把自己ban了，很气 就pass了本地 127.0.01
-- TODO:可能存在时间到了不会释放的问题。
local function ccDefense(flag,red)
    local attackURI = ngx.var.uri
    local host = ngx.var.host
    if getIp()=="127.0.0.1" then return true end
    local ccToken = getIp()..host..attackURI
    local ccConfig =Option.cc_rate
    local limit = ngx.shared.limit
    if flag == Flag.base then
        local data = red:get(Utils.base_key_gen("CC"))
        if type(data)==type("233") then
            ccConfig = data
        end
    elseif flag == Flag.custom then
        local data = red:get(Utils.custom_key_gen("CC"))
        if type(data)==type("233") then
            ccConfig = data
        end
    end
    ccCount = tonumber(string.match(ccConfig,'(.*)/'))
    ccSeconds=tonumber(string.match(ccConfig,'/(.*)'))
    local req,_ = limit:get(ccToken)
    if req then
        if req > ccCount 
        then
            return false
        else
            limit:incr(ccToken,1)
        end
    else
        limit:set(ccToken,1,ccSeconds)
    end
    return true
end

local function getArgsCheck(flag,red)
    local get_args = ngx.req.get_uri_args()
    local set,err
    if flag==Flag.base then
        set ,err = red:zrange(Utils.base_key_gen("GET"),0,-1)
    elseif flag==Flag.custom then
        set,err = red:zrange(Utils.custom_key_gen("GET"),0,-1)
    end
    if err~=nil then ngx.log(ngx.ERR,"Failed to retrive Data in getArgsCheck: ",err) end
    for _,line in ipairs(set) do
        for _,item in pairs(get_args)do
            local m =ngx.re.match(item,line,"jo")
            if m ~= nil then return false end
        end
    end
    return true
end

local function blackIpCheck(flag,red)
    local clientIp = getIp()
    local set,err
    if flag==Flag.base then
        set ,err = red:zrange(Utils.base_key_gen("BLACKIP"),0,-1)
    elseif flag==Flag.custom then
        set,err = red:zrange(Utils.custom_key_gen("BLACKIP"),0,-1)
    end
    if err~=nil then ngx.log(ngx.ERR,"Failed to retrive Data in blackIpCheck err: ",err) end
    for _,item in ipairs(set) do 
        if clientIp == item then
            return false
        end
    end
    return true
end

local function uaCheck(flag,red)
    local ua = ngx.var.user_agent
    local set ,err
    if flag==Flag.base then
        set ,err = red:zrange(Utils.base_key_gen("UA"),0,-1)
    elseif flag==Flag.custom then
        set,err = red:zrange(Utils.custom_key_gen("UA"),0,-1)
    end
    if err~=nil then ngx.log(ngx.ERR,"Failed to retrive Data in uaCheck err: ",err) end
    for _,item in ipairs(set) do
        if ngx.re.match(ua,item,"jo")~=nil then return false end
    end
    return true
end


local function whiteIpCheck(flag,red)
    local set ,err
    if flag == Flag.base then
        set, err = red:SMEMBERS(Utils.base_key_gen("WHITEIP"))
    elseif flag == Flag.custom then
        set ,err = red:SMEMBERS(Utils.custom_key_gen("WHITEIP"))
    end
    if err~=nil then ngx.log(ngx.ERR,"DEBUGINFO error when retrive data in whiteIpCheck") end
    local clientIp = getIp()
    for key, item in ipairs(set) do
        if clientIp == item then
            return true
        else
            return false
        end
    end
end

local function libsqli_cookie_check()
    local cookies =  ngx.var.http_cookie
    local sqli,_ = Libinjection.sqli(cookies)
    if (sqli==true) then
        return false
    else
        return true
    end
end

local function libsqli_get_check()
    local args =  ngx.req.get_uri_args()
    local sqli
    for _,item in pairs(args)do
        sqli = Libinjection.sqli(item)
        if (sqli==true) then
            return false
        end
    end
    return true
end

local function libsqli_post_check()
    local args =  ngx.req.get_post_args()
    local sqli
    for _,item in pairs(args)do
        sqli = Libinjection.sqli(item)
        if (sqli==true) then
            return false
        end
    end
    return true
end

local function libsqli_header_check()
    local headers = ngx.req.get_headers()
    local sqli
    for _,item in pairs(headers)do
        sqli = Libinjection.sqli(item)
        if (sqli==true) then
            return false
        end
    end
    return true
end


local lib = {
    cookie_check = cookieCheck,
    post_args_check = postArgsCheck,
    get_args_check = getArgsCheck,
    header_check = headerCheck,
    ip_blacklist = blackIpCheck,
    ip_whitelist = whiteIpCheck,
    cc_defense = ccDefense,
    ua_check = uaCheck,
    libsqli_header_check=libsqli_header_check,
    libsqli_post_check = libsqli_header_check,
    libsqli_get_check = libsqli_get_check,
    libsqli_cookie_check = libsqli_cookie_check
}

return lib

