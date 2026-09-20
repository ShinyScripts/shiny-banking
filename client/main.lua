local open = false
local atmPin
local uiLocale, uiCode
local blips = {}
local zones = {}

local function nui(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function notify(message, nType)
    if GetResourceState('lation_ui') == 'started' then
        exports.lation_ui:notify({
            title = L('notify_title'),
            message = message,
            type = nType or 'info',
            duration = 5000,
        })
        return
    end
    if lib then
        lib.notify({
            title = L('notify_title'),
            description = message,
            type = nType == 'error' and 'error' or 'inform',
        })
        return
    end
    ESX.ShowNotification(message)
end

local function closeUi()
    if not open then
        nui('close')
        return
    end
    open = false
    atmPin = nil
    SetNuiFocus(false, false)
    nui('close')
    TriggerServerEvent('shiny-banking:close')
end

local function uiData(extra)
    extra = extra or {}
    extra.locale = uiCode or LocaleCode()
    extra.ui = uiLocale or LocaleUI()
    return extra
end

local function openBank()
    if open then return end
    if IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    ESX.TriggerServerCallback('shiny-banking:open', function(payload)
        if not payload then return end
        open = true
        SetNuiFocus(true, true)
        nui('open', uiData({ atm = false, account = payload }))
    end, 'bank')
end

local function openAtm()
    if open then return end
    if IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    ESX.TriggerServerCallback('shiny-banking:open', function(payload)
        if not payload then return end
        open = true
        atmPin = tostring(payload.pin or '')
        SetNuiFocus(true, true)
        nui('pin', uiData({}))
    end, 'atm')
end

local function wrap(name, event)
    RegisterNUICallback(name, function(data, cb)
        ESX.TriggerServerCallback(event, function(result)
            cb(result)
        end, data)
    end)
end

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb(1)
end)

RegisterNUICallback('unlockAtm', function(data, cb)
    local pin = type(data) == 'table' and tostring(data.pin or '') or ''
    if pin ~= atmPin then
        notify(L('pin_wrong'), 'error')
        cb(false)
        return
    end
    ESX.TriggerServerCallback('shiny-banking:atm', function(payload)
        if not payload then
            cb(false)
            return
        end
        nui('open', uiData({ atm = true, account = payload }))
        cb(true)
    end, pin)
end)

wrap('deposit', 'shiny-banking:deposit')
wrap('withdraw', 'shiny-banking:withdraw')
wrap('transfer', 'shiny-banking:transfer')
wrap('transactions', 'shiny-banking:transactions')
wrap('settings', 'shiny-banking:settings')
wrap('refresh', 'shiny-banking:refresh')
wrap('invoices', 'shiny-banking:invoices')
wrap('payInvoice', 'shiny-banking:payInvoice')
wrap('payAllInvoices', 'shiny-banking:payAllInvoices')

RegisterNetEvent('shiny-banking:notify', notify)

local function addBlips()
    if not Config.ShowBankBlips then return end
    for i = 1, #Config.BankLocations do
        local loc = Config.BankLocations[i]
        local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
        SetBlipSprite(blip, loc.blip or 108)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, loc.scale or 0.9)
        SetBlipColour(blip, loc.color or 2)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(loc.label or 'Banka')
        EndTextCommandSetBlipName(blip)
        blips[#blips + 1] = blip
    end
end

local function addTargets()
    if GetResourceState('ox_target') ~= 'started' then return false end
    for i = 1, #Config.BankLocations do
        local loc = Config.BankLocations[i]
        zones[#zones + 1] = exports.ox_target:addSphereZone({
            coords = loc.coords,
            radius = Config.TargetDistance or 1.5,
            options = {
                {
                    name = 'shiny-banking:bank:' .. i,
                    icon = 'fa-solid fa-building-columns',
                    label = L('target_bank'),
                    onSelect = openBank,
                    canInteract = function()
                        return not IsEntityDead(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId(), false)
                    end,
                },
            },
        })
    end
    exports.ox_target:addModel(Config.ATMModels, {
        {
            name = 'shiny-banking:atm',
            icon = 'fa-solid fa-credit-card',
            label = L('target_atm'),
            distance = Config.ATMDistance or 1.5,
            onSelect = openAtm,
            canInteract = function()
                return not IsEntityDead(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId(), false)
            end,
        },
    })
    return true
end

addBlips()
CreateThread(function()
    local n = 0
    while GetResourceState('ox_target') ~= 'started' and n < 50 do
        Wait(200)
        n = n + 1
    end
    if not addTargets() and lib and lib.points then
        for i = 1, #Config.BankLocations do
            local loc = Config.BankLocations[i]
            lib.points.new({
                coords = loc.coords,
                distance = 3.0,
                nearby = function()
                    if IsControlJustReleased(0, 38) then openBank() end
                end,
            })
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    for i = 1, #blips do
        RemoveBlip(blips[i])
    end
    if GetResourceState('ox_target') == 'started' then
        for i = 1, #zones do
            exports.ox_target:removeZone(zones[i])
        end
        exports.ox_target:removeModel(Config.ATMModels, 'shiny-banking:atm')
    end
end)

uiLocale = LocaleUI()
uiCode = LocaleCode()