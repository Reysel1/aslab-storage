function LocaleText(key)
    return lib.getLocales()[key]
end

function FormatMoney(n)
    local sep = LocaleText('_thousands') or ','
    local digits = tostring(math.floor((tonumber(n) or 0) + 0.5))
    local neg = digits:sub(1, 1) == '-'
    if neg then digits = digits:sub(2) end
    local s = (digits:reverse():gsub('(%d%d%d)', '%1' .. sep)):reverse()
    if s:sub(1, #sep) == sep then s = s:sub(#sep + 1) end
    return (neg and '-' or '') .. (LocaleText('_money') or '$%s'):format(s)
end

function FormatKg(g) return locale('kg', math.floor((g or 0) / 1000 + 0.5)) end

function SizeLabel(key)
    local s = Config.Sizes[key]
    return s and s.label or LocaleText('size_' .. tostring(key)) or tostring(key)
end

function FurnitureLabel(f) return f.label or LocaleText('furniture_' .. f.key) or f.key end
function FurnitureDesc(f) return f.desc or LocaleText('furniture_' .. f.key .. '_desc') or '' end
function UpgradeLabel(u, i) return u.label or LocaleText('upgrade_' .. tostring(u.key or i)) or tostring(u.key or i) end
