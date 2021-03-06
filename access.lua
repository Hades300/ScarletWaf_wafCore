local Config = require("config")
local Switch = Config.switch
local Option = Config.option
local Flag = Config.flag
local Utils = require("utils")
local Lib = require("lib")
local Log = require("log")
local red = ngx.ctx.red
local page = require "page"

local hostConfig = Utils.get_config(Flag.base,red)
local uriConfig = Utils.get_config(Flag.custom,red)

-- 设置反代目标
ngx.var.client = hostConfig.client
ngx.var.domain = hostConfig.domain
-- debug
if Config.develop then ngx.say("设置反代目标完成 IP"..hostConfig.client.." 域名："..hostConfig.domain.."</br>") end

local accessConfig ={
    	["waf_status"] = Switch.waf_status,        -- 特判
        ["ip_whitelist"] = Switch.ip_whitelist,    -- 特判
      }

--------------------------- 准入特判
-- host设置覆盖默认
Utils.sync_config(accessConfig,hostConfig)

if accessConfig["waf_status"]==false then return
	elseif accessConfig["ip_whitelist"]==true 
		then
			if Lib.ip_whitelist(Flag.base,red)==true then return
				else page.black_page({403,"Forbiddened By ScarletWAF","_"})
			end
		end

-- uri层覆盖host层
Utils.sync_config(accessConfig,uriConfig)

if accessConfig["waf_status"]==false then return
	elseif accessConfig["ip_whitelist"]==true 
		then
			if Lib.ip_whitelist(Flag.base,red)==true then return
				else page.black_page({403,"Forbiddened By ScarletWAF","_"})
			end
		end

--------------------------- 准入判断

local checkConfig = {
	["ip_blacklist"] = Switch.ip_blacklist,
    ["get_args_check"] = Switch.get_args_check,
    ["post_args_check"] = Switch.post_args_check,
    ["cookie_check"] = Switch.cookie_check,
    ["ua_check"] = Switch.ua_check,
    ["cc_defense"] = Switch.cc_defense,
}

local checkFuncs = {
	["ip_blacklist"] = Lib.ip_blacklist,
    ["get_args_check"] = Lib.get_args_check,
    ["post_args_check"] = Lib.post_args_check,
    ["cookie_check"] = Lib.cookie_check,
    ["ua_check"] = Lib.ua_check,
    ["cc_defense"] = Lib.cc_defense,
}

-- host设置覆盖默认
Utils.sync_config(checkConfig,hostConfig)

-- 如果开启了sql语义化检测 ...
-- 由于代码结构问题产生的屎山
-- 目前放在hostConfig里 也就是要么都启用 要么都不用
if Config.develop then ngx.say("BASE>当前检查项","libsqli_token_check","状态:",hostConfig.libsqli_token_check,"<br>") end
if (hostConfig.libsqli_token_check==true) then
	-- if (hostConfig.get_args_check==true) then
	-- 	if (Lib.libsqli_get_check()~=true) then
	-- 		Log.record(Utils.log_gen("libsqli_get_check"),red)
	-- 		page.black_page({403,"Forbiddened By ScarletWAF","_"})
	-- 		return
	-- 	end
	-- end
	-- if (hostConfig.post_args_check==true) then
	-- 	if (Lib.libsqli_post_check()~=true) then
	-- 		Log.record(Utils.log_gen("libsqli_post_check"),red)
	-- 		page.black_page({403,"Forbiddened By ScarletWAF","_"})
	-- 		return
	-- 	end
	-- end
	-- if (hostConfig.header_check==true) then
	-- 	if (Lib.libsqli_header_check()~=true) then
	-- 		Log.record(Utils.log_gen("libsqli_header_check"),red)
	-- 		page.black_page({403,"Forbiddened By ScarletWAF","_"})
	-- 		return
	-- 	end
	-- end
	-- if (hostConfig.cookie_check==true) then
	-- 	if (Lib.libsqli_cookie_check()~=true) then
	-- 		Log.record(Utils.log_gen("libsqli_cookie_check"),red)
	-- 		page.black_page({403,"Forbiddened By ScarletWAF","_"})
	-- 		return
	-- 	end
	-- end
	-- 使得lib Check独立于其他开关，也就是开启SQL检测会默认检测GET POST COOKIE HEADER中的数据
	if (Lib.libsqli_get_check()~=true) then
		Log.record(Utils.log_gen("libsqli_get_check"),red)
		page.black_page({403,"Forbiddened By ScarletWAF","_"})
		return
	end
	if (Lib.libsqli_post_check()~=true) then
		Log.record(Utils.log_gen("libsqli_post_check"),red)
		page.black_page({403,"Forbiddened By ScarletWAF","_"})
		return
	end
	if (Lib.libsqli_header_check()~=true) then
		Log.record(Utils.log_gen("libsqli_header_check"),red)
		page.black_page({403,"Forbiddened By ScarletWAF","_"})
		return
	end
	if (Lib.libsqli_cookie_check()~=true) then
		Log.record(Utils.log_gen("libsqli_cookie_check"),red)
		page.black_page({403,"Forbiddened By ScarletWAF","_"})
		return
	end
end


for configName , configValue in pairs(checkConfig) do
	if Config.develop then ngx.say("BASE>当前检查项",configName,"状态:",configValue,"<br>")end
	if configValue==true then
		if Config.develop then ngx.log(ngx.ERR,"即将测试",configName) end
		local status = checkFuncs[configName](Flag.base,red)
		if status~=true then
			-- require("log")
			-- 此处Rewrite
			Log.record(Utils.log_gen(configName),red)
			page.black_page({403,"Forbiddened By ScarletWAF","_"})
			if Config.develop then ngx.say("非法Access ,在base中触发 ",configName) end
			return
		end
	end
end

-- uri层覆盖host层
Utils.sync_config(checkConfig,uriConfig)
for configName , configValue in pairs(checkConfig) do
	if Config.develop then ngx.say("CUSTOM>当前检查项",configName,"状态:",configValue,"<br>") end
	if configValue==true then
		if Config.develop then ngx.log(ngx.ERR,"即将测试",configName) end
		local status = checkFuncs[configName](Flag.custom,red)
		if status~=true then
			-- require("log")
			-- 此处Rewrite
			Log.record(Utils.log_gen(configName),red)
			page.black_page({403,"Forbiddened By ScarletWAF","_"})
			return
		end
	end
end



