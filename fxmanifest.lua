fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aslab-storage'
description 'Self storage units, shipping containers and a trade counter in Paleto Bay, Sandy Shores and Cypress Flats'
version '1.0.0'

this_is_a_map 'yes'

ox_lib 'locale'

data_file 'DLC_ITYP_REQUEST' 'stream/paleto/ssf_storage_facility.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/paleto/ssf_passage.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sandy/ssf_s_storage.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sandy/ssf_s_passage.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/cypress/ssf_c_storage.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/cypress/ssf_c_passage.ytyp'

ui_page 'html/index.html'

files {
    'locales/*.json',
    'html/*.html',
    'html/*.js',
    'html/*.css',
    'html/fonts/*.woff2',
    'html/thumbs/*.png',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locale.lua',
    'sites/*.lua',
    'data.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/panel.lua',
    'client/storage.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
