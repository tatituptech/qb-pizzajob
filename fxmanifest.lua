fx_version 'cerulean'
game 'gta5'

author 'TatitupTech'
description 'Pizza Delivery Job with NPC deliveries, tips/refusal, ox_inventory, ox_lib UI and oxmysql logging'
version '1.0.2'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/script.js',
    'html/style.css'
}

dependencies {
    'qb-core',
    'oxmysql',
    'ox_lib',
    'ox_inventory'
}