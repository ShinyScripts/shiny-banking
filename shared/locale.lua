Locales = Locales or {}

local code = Config.Locale or GetConvar('esx:locale', 'en')
if not Locales[code] then
    code = 'en'
end

local pack = Locales[code] or {}
local ui = pack.ui or {}

function L(key, ...)
    local str = pack[key]
    if type(str) ~= 'string' then
        return key
    end
    if select('#', ...) > 0 then
        return str:format(...)
    end
    return str
end

function LocaleUI()
    return ui
end

function LocaleCode()
    return code
end
