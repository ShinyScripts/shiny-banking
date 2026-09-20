fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'
version '1.0.0'

author 'Shiny'

dependencies {
    'es_extended',
    'oxmysql',
}

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'locales/*.lua',
    'shared/locale.lua',
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
}