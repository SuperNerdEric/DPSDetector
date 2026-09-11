local _, ns = ...

local defaults = {
    enableUnitTooltips = true,
    enableLFGTooltips = true,
    showSpec = true,
    showSeasonLine = true,
}

local function CopyDefaults(src, dest)
    dest = dest or {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            dest[key] = CopyDefaults(value, dest[key])
        elseif dest[key] == nil then
            dest[key] = value
        end
    end
    return dest
end

function ns.InitConfig()
    DPSDetector_Config = CopyDefaults(defaults, DPSDetector_Config)
    ns.config = DPSDetector_Config
    return ns.config
end

function ns.GetOption(key)
    if not ns.config then
        ns.InitConfig()
    end
    return ns.config[key]
end

function ns.SetOption(key, value)
    if not ns.config then
        ns.InitConfig()
    end
    ns.config[key] = value
end
