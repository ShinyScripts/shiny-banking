DB = {}

function DB.ensure()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `shiny_banking_transactions` (
          `id` int NOT NULL AUTO_INCREMENT,
          `receiver_identifier` varchar(64) NOT NULL,
          `receiver_name` varchar(128) NOT NULL,
          `sender_identifier` varchar(64) NOT NULL,
          `sender_name` varchar(128) NOT NULL,
          `value` int NOT NULL,
          `type` varchar(24) NOT NULL,
          `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `receiver` (`receiver_identifier`),
          KEY `sender` (`sender_identifier`)
        )
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `shiny_banking_societies` (
          `society` varchar(64) NOT NULL,
          `society_name` varchar(128) NOT NULL,
          `iban` varchar(16) NOT NULL,
          PRIMARY KEY (`society`),
          UNIQUE KEY `iban` (`iban`)
        )
    ]])
    pcall(function()
        MySQL.query.await('ALTER TABLE users ADD COLUMN iban varchar(16) NULL')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE users ADD COLUMN pincode varchar(8) NULL')
    end)
end

function DB.profile(identifier)
    return MySQL.single.await('SELECT iban, pincode FROM users WHERE identifier = ?', { identifier })
end

function DB.setIban(identifier, iban)
    return MySQL.update.await('UPDATE users SET iban = ? WHERE identifier = ?', { iban, identifier })
end

function DB.setPin(identifier, pin)
    return MySQL.update.await('UPDATE users SET pincode = ? WHERE identifier = ?', { pin, identifier })
end

function DB.ibanOwner(iban)
    return MySQL.single.await('SELECT identifier, firstname, lastname FROM users WHERE iban = ?', { iban })
end

function DB.ibanExists(iban)
    if MySQL.scalar.await('SELECT identifier FROM users WHERE iban = ?', { iban }) then
        return true
    end
    return MySQL.scalar.await('SELECT society FROM shiny_banking_societies WHERE iban = ?', { iban }) ~= nil
end

function DB.society(account)
    return MySQL.single.await('SELECT society, society_name, iban FROM shiny_banking_societies WHERE society = ?', { account })
end

function DB.societyByIban(iban)
    return MySQL.single.await('SELECT society, society_name, iban FROM shiny_banking_societies WHERE iban = ?', { iban })
end

function DB.upsertSociety(account, name, iban)
    MySQL.insert.await(
        'INSERT INTO shiny_banking_societies (society, society_name, iban) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE society_name = VALUES(society_name)',
        { account, name, iban }
    )
end

function DB.addTransaction(row)
    return MySQL.insert.await([[
        INSERT INTO shiny_banking_transactions
            (receiver_identifier, receiver_name, sender_identifier, sender_name, value, type)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        row.receiver_identifier,
        row.receiver_name,
        row.sender_identifier,
        row.sender_name,
        row.value,
        row.type,
    })
end

function DB.transactions(identifier, limit)
    return MySQL.query.await([[
        SELECT id, receiver_identifier, receiver_name, sender_identifier, sender_name, value, type,
               UNIX_TIMESTAMP(created_at) AS created_unix
        FROM shiny_banking_transactions
        WHERE receiver_identifier = ? OR sender_identifier = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { identifier, identifier, limit or 40 }) or {}
end