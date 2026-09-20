Config = {}

Config.Locale = GetConvar('esx:locale', 'en')
Config.IBANPrefix = 'SD'
Config.IBANNumbers = 6
Config.CustomIBANMaxChars = 10
Config.CustomIBANAllowLetters = true
Config.IBANChangeCost = 5000
Config.PINChangeCost = 1000
Config.MaxAmount = 10000000
Config.UseAddonAccount = true
Config.RequireCreditCardForATM = false
Config.CreditCardItem = 'creditcard'
Config.CreditCardPrice = 100
Config.UseTarget = true
Config.TargetDistance = 1.5
Config.ATMDistance = 1.5
Config.ShowBankBlips = true
Config.Webhook = ''

Config.Societies = {
    police = true,
    ambulance = true,
}

Config.SocietyAccessRanks = {
    boss = true,
    chief = true,
}

Config.ATMModels = {
    `prop_atm_01`,
    `prop_atm_02`,
    `prop_atm_03`,
    `prop_fleeca_atm`,
}

Config.BankLocations = {
    { blip = 108, color = 2, scale = 0.9, label = 'Bank', coords = vec3(150.266, -1040.203, 29.374) },
    { blip = 108, color = 2, scale = 0.9, label = 'Bank', coords = vec3(-1212.980, -330.841, 37.787) },
    { blip = 108, color = 2, scale = 0.9, label = 'Bank', coords = vec3(-2962.582, 482.627, 15.703) },
    { blip = 108, color = 2, scale = 0.9, label = 'Bank', coords = vec3(-112.202, 6469.295, 31.626) },
    { blip = 108, color = 2, scale = 0.9, label = 'Bank', coords = vec3(314.187, -278.621, 54.170) },
    { blip = 108, color = 2, scale = 0.9, label = 'Bank', coords = vec3(-351.534, -49.529, 49.042) },
    { blip = 108, color = 3, scale = 1.2, label = 'Bank', coords = vec3(253.38, 220.79, 106.29) },
    { blip = 108, color = 2, scale = 0.9, label = 'Bank', coords = vec3(1175.064, 2706.643, 38.094) },
}