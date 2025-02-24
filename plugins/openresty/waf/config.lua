local file_utils = require "file"
local lfs = require "lfs"
local utils = require "utils"
local cjson = require "cjson"

local read_rule = file_utils.read_rule
local read_file2string = file_utils.read_file2string
local read_file2table = file_utils.read_file2table
local set_content_to_file = file_utils.set_content_to_file
local read_list2table = file_utils.read_list2table
local list_dir = lfs.dir
local attributes = lfs.attributes
local match_str = string.match

local waf_dir = "/usr/local/openresty/1pwaf/"
local config_dir = waf_dir .. 'conf/'
local global_rule_dir = waf_dir .. 'rules/'
local site_dir = waf_dir .. 'sites/'
local ip_group_dir = global_rule_dir .. 'ip_group/'

local _M = {}
local config = {}
local global_config = {}

local function init_sites_config()
    local site_config = {}
    local site_rules = {}
    for entry in list_dir(site_dir) do
        if entry ~= "." and entry ~= ".." then
            local site_path = site_dir .. entry .. "/"
            if attributes(site_path, "mode") == "directory" then
                local site_key = entry
                for s_entry in list_dir(site_path) do
                    local s_entry_path = site_path .. s_entry
                    if attributes(s_entry_path, "mode") == "file" and s_entry == "config.json" then
                        local s_config = read_file2table(s_entry_path)
                        site_config[site_key] = s_config
                    end
                    if attributes(s_entry_path, "mode") == "directory" and s_entry == "rules" then
                        local s_rules = {}
                        local rule_dir = s_entry_path .. "/"
                        for r_file in list_dir(rule_dir) do
                            if r_file ~= "." and r_file ~= ".." then
                                local rule_path = rule_dir .. r_file
                                local rule_type = match_str(r_file, "(.-)%.json$")
                                if attributes(rule_path, "mode") == "file" then
                                    local s_rule = nil
                                    if rule_type == "methodWhite" then
                                        s_rule = read_rule(rule_dir, rule_type, true)
                                        
                                    else
                                        s_rule = read_rule(rule_dir, rule_type)
                                    end
                                    s_rules[rule_type] = s_rule
                                end
                            end
                        end
                        site_rules[site_key] = s_rules
                    end
                end
            end
        end
    end
    config.site_config = site_config
    config.site_rules = site_rules
end

local function ini_waf_info()
    local waf_info = read_file2table(waf_dir .. 'waf.json')
    if waf_info then
        ngx.log(ngx.NOTICE, "Load " .. waf_info.name .. " Version:" .. waf_info.version)
    end
end

local function load_ip_group()
    local ip_group_list = {}
    for entry in list_dir(ip_group_dir) do
        if entry ~= "." and entry ~= ".." then
            local group_path = ip_group_dir .. entry
            local group_value = read_list2table(group_path)
            ip_group_list[entry] = group_value
        end
    end
    local waf_dict = ngx.shared.waf
    local ok , err =  waf_dict:set("ip_group_list",  cjson.encode(ip_group_list))
    if not ok then 
        ngx.log(ngx.ERR, "Failed to set ip_group_list",err)
    end
end

local function init_global_config()
    local global_config_file = config_dir .. 'global.json'
    global_config = file_utils.read_file2table(global_config_file)
    config.global_config = global_config
    config.isProtectionMode = global_config["mode"] == "protection" and true or false

    _M.get_token()
    
    local rules = {}
    rules.uaBlack = read_rule(global_rule_dir, "uaBlack")
    rules.uaWhite = read_rule(global_rule_dir, "uaWhite")
    rules.urlBlack = read_rule(global_rule_dir, "urlBlack")
    rules.urlWhite = read_rule(global_rule_dir, "urlWhite")
    rules.ipWhite = read_rule(global_rule_dir, "ipWhite")
    rules.args = read_rule(global_rule_dir, "args")
    rules.cookie = read_rule(global_rule_dir, "cookie")
    rules.defaultUaBlack = read_rule(global_rule_dir, "defaultUaBlack")
    rules.defaultUrlBlack = read_rule(global_rule_dir, "defaultUrlBlack")
    rules.header = read_rule(global_rule_dir, "header")
    rules.ipBlack = read_rule(global_rule_dir, "ipBlack")
    
    config.global_rules = rules

    local html_res = {}
    local htmDir = waf_dir .. "html/"
    html_res.slide = read_file2string(htmDir .. "slide.html")
    html_res.slide_js = read_file2string(htmDir .. "slide.js")
    html_res.five_second = read_file2string(htmDir .. "5s.html")
    html_res.five_second_js = read_file2string(htmDir .. "5s.js")
    html_res.redirect = read_file2string(htmDir .. "redirect.html")
    html_res.ip = read_file2string(htmDir .. "ip.html")

    config.html_res = html_res

    _M.waf_dir = waf_dir
    _M.waf_db_dir = waf_dir .. "db/"
    _M.waf_db_path =  _M.waf_db_dir .. "1pwaf.db"
    _M.waf_log_db_path =  _M.waf_db_dir .. "req_log.db"
    _M.config_dir = config_dir

end

function _M.load_config_file()
    ini_waf_info()
    init_global_config()
    init_sites_config()
    load_ip_group()
    
    local waf_dict = ngx.shared.waf
    local ok,err = waf_dict:set("config", cjson.encode(config))
    if not ok then 
        ngx.log(ngx.ERR, "Failed to set config",err)
    end
end

local function get_config()
    local waf_dict = ngx.shared.waf
    local cache_config = waf_dict:get("config")
    if not cache_config then
        return config
    end
    return cjson.decode(cache_config) 
end

function _M.get_site_config(website_key)
    return get_config().site_config[website_key]
end

function _M.get_site_rules(website_key)
    return get_config().site_rules[website_key]
end

function _M.get_global_config(name)
    return get_config().global_config[name]
end

function _M.get_global_rules(name)
    return get_config().global_rules[name]
end

function _M.is_global_state_on(name)
    return get_config().global_config[name]["state"] == "on" and true or false
end

function _M.is_site_state_on(name)
    return get_config().site_config[name]["state"] == "on" and true or false
end

function _M.get_redis_config()
    return get_config().global_config["redis"]
end

function _M.get_html_res(name)
    return get_config().html_res[name]
end

function _M.is_waf_on()
    return _M.is_global_state_on("waf")
end

function _M.is_redis_on()
    return _M.is_global_state_on("redis")
end

function _M.get_secret()
    return get_config().global_config["waf"]["secret"]
end

function _M.get_token()
    local waf_dict = ngx.shared.waf
    local token = waf_dict:get("token")
    if not token then
        token = utils.random_string(20)
        waf_dict:set("token", token, 86400)
        local token_path = config_dir .. 'token'
        set_content_to_file(token,token_path)
    end    
    return token
end

return _M