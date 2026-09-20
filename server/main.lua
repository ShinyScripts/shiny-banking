local Prefix = Config.IBANPrefix or 'SB'
local IbanLen = Config.IBANNumbers or 6
local MaxAmount = Config.MaxAmount or 10000000
local Societies = Config.Societies or {}
local Ranks = Config.SocietyAccessRanks or {}
local IbanCost = Config.IBANChangeCost or 0
local PinCost = Config.PINChangeCost or 0
local CardPrice = Config.CreditCardPrice or 0
local CardItem = Config.CreditCardItem or 'creditcard'
local session = {}

math.randomseed(os.time() % 2147483647)

local function notify(src, key, kind, ...)
    TriggerClientEvent('shiny-banking:notify', src, L(key, ...), kind or 'info')
end

local function trim(s)
    if type(s) ~= 'string' then return '' end
    return s:match('^%s*(.-)%s*$') or ''
end

local function jobName(xPlayer)
    local job = xPlayer and xPlayer.getJob()
    return job and job.name or ''
end

local function jobLabel(xPlayer)
    local job = xPlayer and xPlayer.getJob()
    return job and job.label or ''
end

local function gradeName(xPlayer)
    local job = xPlayer and xPlayer.getJob()
    return job and job.grade_name or ''
end

local function characterName(xPlayer)
    if not xPlayer then return 'Unknown' end
    local name = xPlayer.getName()
    if type(name) == 'string' and name ~= '' then return name end
    return GetPlayerName(xPlayer.source) or 'Unknown'
end

local function dbName(identifier)
    local row = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
    if row and row.firstname then
        return trim((row.firstname or '') .. ' ' .. (row.lastname or ''))
    end
    return 'Unknown'
end

local function societyAccount(name)
    name = tostring(name or ''):gsub('^society_', '')
    if name == '' then return '' end
    return 'society_' .. name
end

local function canSociety(xPlayer)
    local name = jobName(xPlayer)
    if Societies[name] ~= true then return false end
    if not next(Ranks) then return true end
    return Ranks[gradeName(xPlayer)] == true
end

local function cash(xPlayer)
    local account = xPlayer.getAccount('money')
    if account then return tonumber(account.money) or 0 end
    return xPlayer.getMoney() or 0
end

local function bank(xPlayer)
    local account = xPlayer.getAccount('bank')
    return account and tonumber(account.money) or 0
end

local function addCash(xPlayer, amount)
    if xPlayer.addAccountMoney then
        xPlayer.addAccountMoney('money', amount)
        return
    end
    xPlayer.addMoney(amount)
end

local function removeCash(xPlayer, amount)
    if xPlayer.removeAccountMoney then
        xPlayer.removeAccountMoney('money', amount)
        return
    end
    xPlayer.removeMoney(amount)
end

local function addBank(xPlayer, amount)
    xPlayer.addAccountMoney('bank', amount)
end

local function removeBank(xPlayer, amount)
    xPlayer.removeAccountMoney('bank', amount)
end

local function loadOffline(identifier)
    local row = MySQL.single.await('SELECT accounts FROM users WHERE identifier = ?', { identifier })
    if not row or type(row.accounts) ~= 'string' then return end
    local ok, accounts = pcall(json.decode, row.accounts)
    if ok and type(accounts) == 'table' then return accounts end
end

local function saveOffline(identifier, accounts)
    MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', { json.encode(accounts), identifier })
end

local function addOfflineBank(identifier, amount)
    local accounts = loadOffline(identifier)
    if not accounts then return false end
    accounts.bank = (tonumber(accounts.bank) or 0) + amount
    saveOffline(identifier, accounts)
    return true
end

local function getSocietyMoney(account)
    if Config.UseAddonAccount and GetResourceState('esx_addonaccount') == 'started' then
        local sharedAccount
        local done = promise.new()
        local finished = false
        local function finish()
            if finished then return end
            finished = true
            done:resolve(true)
        end
        TriggerEvent('esx_addonaccount:getSharedAccount', account, function(shared)
            sharedAccount = shared
            finish()
        end)
        SetTimeout(1500, finish)
        Citizen.Await(done)
        if sharedAccount and sharedAccount.money then
            return tonumber(sharedAccount.money) or 0
        end
    end
    local row = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
    return row and tonumber(row.money) or 0
end

local function addSocietyMoney(account, amount)
    if amount == 0 or account == '' then return true end
    if Config.UseAddonAccount and GetResourceState('esx_addonaccount') == 'started' then
        local sharedAccount
        local done = promise.new()
        local finished = false
        local function finish()
            if finished then return end
            finished = true
            done:resolve(sharedAccount ~= nil)
        end
        TriggerEvent('esx_addonaccount:getSharedAccount', account, function(shared)
            sharedAccount = shared
            finish()
        end)
        SetTimeout(1500, finish)
        Citizen.Await(done)
        if sharedAccount then
            if amount > 0 then sharedAccount.addMoney(amount) else sharedAccount.removeMoney(-amount) end
            return true
        end
    end
    local row = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ?', { account })
    if not row then return false end
    MySQL.update.await('UPDATE addon_account_data SET money = money + ? WHERE account_name = ?', { amount, account })
    return true
end

local function newIban()
    for _ = 1, 16 do
        local n = ''
        for i = 1, IbanLen do
            n = n .. tostring(math.random(0, 9))
        end
        local iban = Prefix .. n
        if not DB.ibanExists(iban) then return iban end
    end
    return Prefix .. tostring(os.time()):sub(-IbanLen)
end

local function ensureIban(identifier)
    local profile = DB.profile(identifier)
    if profile and type(profile.iban) == 'string' and profile.iban ~= '' then
        return profile.iban:upper(), profile.pincode
    end
    local iban = newIban()
    DB.setIban(identifier, iban)
    return iban, profile and profile.pincode or nil
end

local function ensureSociety(xPlayer)
    local account = societyAccount(jobName(xPlayer))
    if account == '' then return end
    local row = DB.society(account)
    if row then return row end
    local iban = (Prefix .. jobName(xPlayer)):upper()
    if DB.ibanExists(iban) then
        iban = newIban()
    end
    DB.upsertSociety(account, jobLabel(xPlayer), iban)
    return DB.society(account)
end

local function addTransaction(senderIdent, senderName, receiverIdent, receiverName, amount, typ)
    DB.addTransaction({
        sender_identifier = senderIdent,
        sender_name = senderName,
        receiver_identifier = receiverIdent,
        receiver_name = receiverName,
        value = math.floor(tonumber(amount) or 0),
        type = typ or 'transfer',
    })
end

local function nearSpot(src, kind)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    if kind ~= 'bank' then return true end
    local coords = GetEntityCoords(ped)
    for i = 1, #Config.BankLocations do
        if #(coords - Config.BankLocations[i].coords) <= 4.0 then
            return true
        end
    end
    return false
end

local function requireOpen(src, allowAtm)
    local kind = session[src]
    if kind ~= 'bank' and kind ~= 'atm' then return false end
    if kind == 'atm' and not allowAtm then
        notify(src, 'no_permission', 'error')
        return false
    end
    if not nearSpot(src, kind) then
        notify(src, 'too_far', 'error')
        return false
    end
    return kind
end

local function hasCard(xPlayer)
    if GetResourceState('ox_inventory') == 'started' then
        return (exports.ox_inventory:Search(xPlayer.source, 'count', CardItem) or 0) > 0
    end
    local item = xPlayer.getInventoryItem(CardItem)
    return item and (item.count or 0) > 0
end

local function giveCard(xPlayer)
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:AddItem(xPlayer.source, CardItem, 1) == true
    end
    xPlayer.addInventoryItem(CardItem, 1)
    return true
end

local function snapshot(xPlayer)
    local iban, pin = ensureIban(xPlayer.identifier)
    local payload = {
        name = characterName(xPlayer),
        cash = cash(xPlayer),
        bank = bank(xPlayer),
        iban = iban,
        hasPin = pin ~= nil and tostring(pin) ~= '',
        society = false,
        ibanCost = IbanCost,
        pinCost = PinCost,
        cardPrice = CardPrice,
        hasCard = hasCard(xPlayer),
        hasBilling = GetResourceState('shiny-billing') == 'started',
    }
    if canSociety(xPlayer) then
        local info = ensureSociety(xPlayer)
        payload.society = {
            name = jobLabel(xPlayer),
            account = societyAccount(jobName(xPlayer)),
            iban = info and info.iban or '',
            money = getSocietyMoney(societyAccount(jobName(xPlayer))),
        }
    end
    return payload
end

MySQL.ready(function()
    DB.ensure()
end)

ESX.RegisterServerCallback('shiny-banking:open', function(source, cb, kind)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        cb(false)
        return
    end
    kind = kind == 'atm' and 'atm' or 'bank'
    if kind == 'atm' and Config.RequireCreditCardForATM and not hasCard(xPlayer) then
        notify(source, 'no_creditcard', 'error')
        cb(false)
        return
    end
    if kind == 'atm' then
        local profile = DB.profile(xPlayer.identifier)
        local pin = profile and tostring(profile.pincode or '')
        if pin == '' then
            notify(source, 'no_pin', 'error')
            cb(false)
            return
        end
        cb({ atm = true, pin = pin })
        return
    end
    session[source] = 'bank'
    cb(snapshot(xPlayer))
end)

ESX.RegisterServerCallback('shiny-banking:atm', function(source, cb, pin)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        cb(false)
        return
    end
    local profile = DB.profile(xPlayer.identifier)
    if not profile or tostring(profile.pincode or '') ~= tostring(pin or '') then
        notify(source, 'pin_wrong', 'error')
        cb(false)
        return
    end
    session[source] = 'atm'
    cb(snapshot(xPlayer))
end)

ESX.RegisterServerCallback('shiny-banking:refresh', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not session[source] then
        cb(false)
        return
    end
    cb(snapshot(xPlayer))
end)

ESX.RegisterServerCallback('shiny-banking:transactions', function(source, cb, payload)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not session[source] then
        cb({})
        return
    end
    local society = payload == true or (type(payload) == 'table' and payload.society == true)
    if society then
        if not canSociety(xPlayer) then
            cb({})
            return
        end
        cb(DB.transactions(societyAccount(jobName(xPlayer)), 40))
        return
    end
    cb(DB.transactions(xPlayer.identifier, 40))
end)

local function billingReady()
    return GetResourceState('shiny-billing') == 'started'
end

ESX.RegisterServerCallback('shiny-banking:invoices', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not requireOpen(source, false) or not billingReady() then
        cb({})
        return
    end
    cb(exports['shiny-billing']:GetUnpaid(source) or {})
end)

ESX.RegisterServerCallback('shiny-banking:payInvoice', function(source, cb, payload)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not requireOpen(source, false) then
        cb(false)
        return
    end
    if not billingReady() then
        notify(source, 'no_permission', 'error')
        cb(false)
        return
    end
    local id = type(payload) == 'table' and payload.id or payload
    local ok = exports['shiny-billing']:PayInvoice(source, id)
    if not ok then
        cb(false)
        return
    end
    cb({
        account = snapshot(xPlayer),
        invoices = exports['shiny-billing']:GetUnpaid(source) or {},
    })
end)

ESX.RegisterServerCallback('shiny-banking:payAllInvoices', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not requireOpen(source, false) then
        cb(false)
        return
    end
    if not billingReady() then
        notify(source, 'no_permission', 'error')
        cb(false)
        return
    end
    local result = exports['shiny-billing']:PayAll(source)
    if type(result) ~= 'table' or not result.ok then
        cb(false)
        return
    end
    cb({
        account = snapshot(xPlayer),
        invoices = exports['shiny-billing']:GetUnpaid(source) or {},
    })
end)

local function amountOk(value)
    value = math.floor(tonumber(value) or 0)
    if value < 1 or value > MaxAmount then return end
    return value
end

ESX.RegisterServerCallback('shiny-banking:deposit', function(source, cb, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    local amount = type(data) == 'table' and amountOk(data.amount) or amountOk(data)
    if not xPlayer or not requireOpen(source, true) or not amount then
        if xPlayer then notify(source, 'invalid_amount', 'error') end
        cb(false)
        return
    end
    local toSociety = type(data) == 'table' and data.society == true
    if toSociety then
        if session[source] ~= 'bank' or not canSociety(xPlayer) then
            notify(source, 'no_permission', 'error')
            cb(false)
            return
        end
        if cash(xPlayer) < amount then
            notify(source, 'no_money_pocket', 'error')
            cb(false)
            return
        end
        removeCash(xPlayer, amount)
        local account = societyAccount(jobName(xPlayer))
        addSocietyMoney(account, amount)
        addTransaction(xPlayer.identifier, characterName(xPlayer), account, jobLabel(xPlayer), amount, 'deposit')
        notify(source, 'deposited_society', 'success', amount)
        cb(snapshot(xPlayer))
        return
    end
    if cash(xPlayer) < amount then
        notify(source, 'no_money_pocket', 'error')
        cb(false)
        return
    end
    removeCash(xPlayer, amount)
    addBank(xPlayer, amount)
    addTransaction(xPlayer.identifier, characterName(xPlayer), xPlayer.identifier, characterName(xPlayer), amount, 'deposit')
    notify(source, 'deposited', 'success', amount)
    cb(snapshot(xPlayer))
end)

ESX.RegisterServerCallback('shiny-banking:withdraw', function(source, cb, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    local amount = type(data) == 'table' and amountOk(data.amount) or amountOk(data)
    if not xPlayer or not requireOpen(source, true) or not amount then
        if xPlayer then notify(source, 'invalid_amount', 'error') end
        cb(false)
        return
    end
    local fromSociety = type(data) == 'table' and data.society == true
    if fromSociety then
        if session[source] ~= 'bank' or not canSociety(xPlayer) then
            notify(source, 'no_permission', 'error')
            cb(false)
            return
        end
        local account = societyAccount(jobName(xPlayer))
        if getSocietyMoney(account) < amount then
            notify(source, 'society_no_money', 'error')
            cb(false)
            return
        end
        if not addSocietyMoney(account, -amount) then
            cb(false)
            return
        end
        addCash(xPlayer, amount)
        addTransaction(account, jobLabel(xPlayer), xPlayer.identifier, characterName(xPlayer), amount, 'withdraw')
        notify(source, 'withdrawn_society', 'success', amount)
        cb(snapshot(xPlayer))
        return
    end
    if bank(xPlayer) < amount then
        notify(source, 'no_money_bank', 'error')
        cb(false)
        return
    end
    removeBank(xPlayer, amount)
    addCash(xPlayer, amount)
    addTransaction(xPlayer.identifier, characterName(xPlayer), xPlayer.identifier, characterName(xPlayer), amount, 'withdraw')
    notify(source, 'withdrawn', 'success', amount)
    cb(snapshot(xPlayer))
end)

ESX.RegisterServerCallback('shiny-banking:transfer', function(source, cb, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not requireOpen(source, true) or type(data) ~= 'table' then
        cb(false)
        return
    end
    local amount = amountOk(data.amount)
    local iban = trim(tostring(data.iban or '')):upper()
    if not amount or iban == '' then
        notify(source, 'invalid_amount', 'error')
        cb(false)
        return
    end
    local fromSociety = data.society == true
    if fromSociety and (session[source] ~= 'bank' or not canSociety(xPlayer)) then
        notify(source, 'no_permission', 'error')
        cb(false)
        return
    end

    local myIban = select(1, ensureIban(xPlayer.identifier))
    local soc = fromSociety and ensureSociety(xPlayer)
    if (not fromSociety and iban == myIban) or (fromSociety and soc and iban == soc.iban) then
        notify(source, 'not_send_yourself', 'error')
        cb(false)
        return
    end

    local sourceIdent = fromSociety and societyAccount(jobName(xPlayer)) or xPlayer.identifier
    local sourceName = fromSociety and jobLabel(xPlayer) or characterName(xPlayer)
    local sourceMoney = fromSociety and getSocietyMoney(sourceIdent) or bank(xPlayer)
    if sourceMoney < amount then
        notify(source, fromSociety and 'society_no_money' or 'no_money_bank', 'error')
        cb(false)
        return
    end

    local user = DB.ibanOwner(iban)
    local societyRow = not user and DB.societyByIban(iban)
    if not user and not societyRow then
        notify(source, 'iban_not_exist', 'error')
        cb(false)
        return
    end

    if fromSociety then
        addSocietyMoney(sourceIdent, -amount)
    else
        removeBank(xPlayer, amount)
    end

    if user then
        local target = ESX.GetPlayerFromIdentifier(user.identifier)
        local targetName = target and characterName(target) or dbName(user.identifier)
        if target then
            addBank(target, amount)
            notify(target.source, 'received_from', 'success', amount, sourceName)
        else
            addOfflineBank(user.identifier, amount)
        end
        addTransaction(sourceIdent, sourceName, user.identifier, targetName, amount, 'transfer')
        notify(source, 'transferred_to', 'success', amount, targetName)
    else
        addSocietyMoney(societyRow.society, amount)
        addTransaction(sourceIdent, sourceName, societyRow.society, societyRow.society_name, amount, 'transfer')
        notify(source, 'transferred_to', 'success', amount, societyRow.society_name)
    end
    cb(snapshot(xPlayer))
end)

ESX.RegisterServerCallback('shiny-banking:settings', function(source, cb, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not requireOpen(source, false) or type(data) ~= 'table' then
        cb(false)
        return
    end
    local action = data.action
    if action == 'iban' then
        local iban = trim(tostring(data.value or '')):upper()
        local max = Config.CustomIBANMaxChars or 10
        if #iban < 3 or #iban > max then
            notify(source, 'iban_invalid', 'error')
            cb(false)
            return
        end
        if not Config.CustomIBANAllowLetters and iban:find('[^0-9]') then
            notify(source, 'iban_invalid', 'error')
            cb(false)
            return
        end
        if not iban:find('^[%w]+$') then
            notify(source, 'iban_invalid', 'error')
            cb(false)
            return
        end
        local current = select(1, ensureIban(xPlayer.identifier))
        if iban == current then
            notify(source, 'iban_invalid', 'error')
            cb(false)
            return
        end
        if DB.ibanExists(iban) then
            notify(source, 'iban_in_use', 'error')
            cb(false)
            return
        end
        if bank(xPlayer) < IbanCost then
            notify(source, 'iban_no_money', 'error', IbanCost)
            cb(false)
            return
        end
        if IbanCost > 0 then removeBank(xPlayer, IbanCost) end
        DB.setIban(xPlayer.identifier, iban)
        if IbanCost > 0 then
            addTransaction(xPlayer.identifier, characterName(xPlayer), 'bank', 'Bank', IbanCost, 'transfer')
        end
        notify(source, 'iban_changed', 'success', iban)
        cb(snapshot(xPlayer))
        return
    end
    if action == 'pin' then
        local pin = tostring(data.value or '')
        if not pin:find('^%d%d%d%d$') then
            notify(source, 'pin_digits', 'error')
            cb(false)
            return
        end
        local profile = DB.profile(xPlayer.identifier)
        local first = not profile or tostring(profile.pincode or '') == ''
        local cost = first and 0 or PinCost
        if cost > 0 and bank(xPlayer) < cost then
            notify(source, 'pin_no_money', 'error', cost)
            cb(false)
            return
        end
        if cost > 0 then
            removeBank(xPlayer, cost)
            addTransaction(xPlayer.identifier, characterName(xPlayer), 'bank', 'Bank', cost, 'transfer')
        end
        DB.setPin(xPlayer.identifier, pin)
        notify(source, 'pin_changed', 'success', pin)
        cb(snapshot(xPlayer))
        return
    end
    if action == 'card' then
        if bank(xPlayer) < CardPrice then
            notify(source, 'no_money_bank', 'error')
            cb(false)
            return
        end
        removeBank(xPlayer, CardPrice)
        giveCard(xPlayer)
        addTransaction(xPlayer.identifier, characterName(xPlayer), 'bank', 'Bank', CardPrice, 'transfer')
        notify(source, 'bought_cc', 'success', CardPrice)
        cb(snapshot(xPlayer))
        return
    end
    cb(false)
end)

RegisterNetEvent('shiny-banking:close', function()
    session[source] = nil
end)

AddEventHandler('playerDropped', function()
    session[source] = nil
end)

local function exportAddMoney(society, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    return addSocietyMoney(societyAccount(society), amount)
end

local function exportRemoveMoney(society, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    local account = societyAccount(society)
    if getSocietyMoney(account) < amount then return false end
    return addSocietyMoney(account, -amount)
end

local function exportGetAccount(society)
    return getSocietyMoney(societyAccount(society))
end

local function exportAddTransaction(senderIdent, senderName, receiverIdent, receiverName, amount, typ)
    addTransaction(senderIdent, senderName, receiverIdent, receiverName, amount, typ or 'transfer')
    return true
end

exports('AddMoney', exportAddMoney)
exports('RemoveMoney', exportRemoveMoney)
exports('GetAccount', exportGetAccount)
exports('AddTransaction', exportAddTransaction)

AddEventHandler('shiny-banking:AddNewTransaction', function(receiverName, receiverIdent, senderName, senderIdent, amount, reason)
    local extra = reason and (' (' .. tostring(reason) .. ')') or ''
    addTransaction(senderIdent, tostring(senderName) .. extra, receiverIdent, tostring(receiverName) .. extra, amount, 'transfer')
end)