-- Stable GTA:SA model names, independent of font-encoded/localized GXT bytes.
-- Model IDs: https://open.mp/docs/scripting/resources/vehicleid
-- User replacements live in vehicle.model_aliases and are edited in the GUI.
local rows={
    'Landstalker','Bravura','Buffalo','Linerunner','Perennial','Sentinel','Dumper','Firetruck','Trashmaster','Stretch',
    'Manana','Infernus','Voodoo','Pony','Mule','Cheetah','Ambulance','Leviathan','Moonbeam','Esperanto',
    'Taxi','Washington','Bobcat','Mr. Whoopee','BF Injection','Hunter','Premier','Enforcer','Securicar','Banshee',
    'Predator','Bus','Rhino','Barracks','Hotknife','Trailer','Previon','Coach','Cabbie','Stallion',
    'Rumpo','RC Bandit','Romero','Packer','Monster','Admiral','Squalo','Seasparrow','Pizzaboy','Tram',
    'Trailer','Turismo','Speeder','Reefer','Tropic','Flatbed','Yankee','Caddy','Solair','Topfun',
    'Skimmer','PCJ-600','Faggio','Freeway','RC Baron','RC Raider','Glendale','Oceanic','Sanchez','Sparrow',
    'Patriot','Quad','Coastguard','Dinghy','Hermes','Sabre','Rustler','ZR-350','Walton','Regina',
    'Comet','BMX','Burrito','Camper','Marquis','Baggage','Dozer','Maverick','News Chopper','Rancher',
    'FBI Rancher','Virgo','Greenwood','Jetmax','Hotring Racer','Sandking','Blista Compact','Police Maverick','Boxville','Benson',
    'Mesa','RC Goblin','Hotring Racer','Hotring Racer','Bloodring Banger','Rancher','Super GT','Elegant','Journey','Bike',
    'Mountain Bike','Beagle','Cropduster','Stuntplane','Tanker','Roadtrain','Nebula','Majestic','Buccaneer','Shamal',
    'Hydra','FCR-900','NRG-500','HPV1000','Cement Truck','Towtruck','Fortune','Cadrona','FBI Truck','Willard',
    'Forklift','Tractor','Combine Harvester','Feltzer','Remington','Slamvan','Blade','Freight','Brown Streak','Vortex',
    'Vincent','Bullet','Clover','Sadler','Firetruck LA','Hustler','Intruder','Primo','Cargobob','Tampa',
    'Sunrise','Merit','Utility Van','Nevada','Yosemite','Windsor','Monster A','Monster B','Uranus','Jester',
    'Sultan','Stratum','Elegy','Raindance','RC Tiger','Flash','Tahoma','Savanna','Bandito','Freight Flat Trailer',
    'Streak Trailer','Kart','Mower','Dune','Sweeper','Broadway','Tornado','AT-400','DFT-30','Huntley',
    'Stafford','BF-400','Newsvan','Tug','Tanker Trailer','Emperor','Wayfarer','Euros','Hotdog','Club',
    'Freight Box Trailer','Trailer','Andromada','Dodo','RC Cam','Launch','Police LS','Police SF','Police LV','Police Ranger',
    'Picador','S.W.A.T.','Alpha','Phoenix','Glendale Shit','Sadler Shit','Baggage Trailer A','Baggage Trailer B','Tug Stairs','Boxville',
    'Farm Trailer','Utility Trailer',
}
local out={};for i,name in ipairs(rows)do out[i+399]=name end
return out
