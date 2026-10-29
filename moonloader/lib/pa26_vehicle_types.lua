-- GTA base model IDs: https://open.mp/docs/scripting/resources/vehicleid
-- Russian RP classes are editable labels, not server vehicle properties.
local core=require 'pa26_core'
local M={}
M.rows={{'car','Автомобиль','автомобиль','автомобиля'},{'bus','Автобус','автобус','автобуса'},
 {'bike','Мотоцикл','мотоцикл','мотоцикла'},{'bicycle','Велосипед','велосипед','велосипеда'},
 {'quad','Квадроцикл','квадроцикл','квадроцикла'},{'truck','Грузовик','грузовик','грузовика'},
 {'van','Фургон','фургон','фургона'},{'special','Спецтранспорт','спецтранспорт','спецтранспорта'},
 {'boat','Судно','судно','судна'},{'heli','Вертолёт','вертолёт','вертолёта'},
 {'plane','Самолёт','самолёт','самолёта'},{'train','Рельсовый транспорт','рельсовый транспорт','рельсового транспорта'},
 {'trailer','Прицеп','прицеп','прицепа'},{'unknown','Неизвестный тип','транспортное средство','транспортного средства'}}
local classes={}
local function group(key,ids)for id in ids:gmatch('%d+')do assert(not classes[tonumber(id)]);classes[tonumber(id)]=key end end
group('bus','431 437')
group('bike','448 461 462 463 468 521 522 523 581 586')
group('bicycle','481 509 510');group('quad','471')
group('boat','430 446 452 453 454 472 473 484 493 595')
group('heli','417 425 447 469 487 488 497 548 563')
group('plane','460 464 465 476 501 511 512 513 519 520 553 577 592 593 594')
group('train','449 537 538 569 570 590')
group('trailer','435 450 584 591 606 607 608 610 611')
group('van','413 418 440 459 482 483 508 582')
group('truck','403 408 414 423 455 456 478 498 499 514 515 554 588 609')
group('special','406 407 416 427 428 432 433 441 443 444 457 470 485 486 490 524 525 528 530 531 532 539 544 552 556 557 564 568 571 572 573 574 578 583 601')
function M.class(id)
 if not core.finite(id)or id%1~=0 or id<400 or id>611 then return'unknown'end
 return classes[id]or'car'
end
function M.defaults()
 local out={};for _,r in ipairs(M.rows)do out[r[1]]={name=r[3],genitive=r[4]}end;return out
end
function M.names(id,settings)
 local key=M.class(id);local row=settings and settings[key]or M.defaults()[key]
 return row.name,row.genitive,key
end
function M.validate(raw)
 local d=M.defaults();if raw==nil then return d end
 if type(raw)~='table'then return nil,'Проверьте названия типов транспорта.'end
 for _,r in ipairs(M.rows)do local row=raw[r[1]]
  if row~=nil then
   if type(row)~='table'then return nil,'Проверьте тип транспорта: '..r[2]end
   for _,k in ipairs({'name','genitive'})do local s=row[k]
    if type(s)~='string'or s==''or #s>160 or not core.validUtf8(s)or s:find('[{}%c]')then return nil,'Название типа: до 160 байт без переменных и переносов.'end
    d[r[1]][k]=s
   end
  end
 end;return d
end
return M
