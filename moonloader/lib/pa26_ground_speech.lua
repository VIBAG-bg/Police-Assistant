-- Editable officer interpretation, never an amendment to the source of law.
local core=require 'pa26_core'
local M={}
M.defaults={
 speed='Я {gender:остановил|остановила} вас, поскольку вы превысили установленную скорость движения.',
 signal='Я {gender:остановил|остановила} вас, потому что вы проехали на запрещающий сигнал светофора.',
 junction='Я {gender:остановил|остановила} вас, чтобы уточнить обстоятельства проезда перекрёстка.',
 parking='Причина остановки — нарушение правил остановки или парковки.',
 wrong_way='Вы выехали на встречную полосу. Давайте уточним, что произошло.',
 defect='Я {gender:заметил|заметила} признаки технической неисправности. Мне необходимо уточнить состояние автомобиля.',
 registration='Я {gender:остановил|остановила} вас для уточнения регистрационных данных транспортного средства.',
 insurance='Мне необходимо проверить сведения об обязательном страховании вашего автомобиля.',
 sobriety_check='Манера управления вызвала у меня вопросы. Мне необходимо уточнить обстоятельства и проверить документы.',
 intoxicated='Причина остановки — установленные в этой ситуации признаки управления в состоянии опьянения.',
 exam_refusal='Мне необходимо уточнить обстоятельства вашего отказа от законного освидетельствования.',
 left_accident='Я {gender:остановил|остановила} вас, чтобы уточнить обстоятельства оставления места ДТП.',
 bulletin='Ваш автомобиль похож на транспорт из поступившей ориентировки. Мне нужно уточнить данные.'}
function M.validate(raw)
 if raw~=nil and type(raw)~='table'then return nil,'Повреждены реплики причин остановки.'end
 local out={}
 for id,stock in pairs(M.defaults)do
  local text=raw and raw[id]or stock
  if type(text)~='string'or not core.validUtf8(text)or #text>4096 or not text:match('%S')or text:match('^%s*[/@]')or text:find('%c')then return nil,'Проверьте реплику причины: '..id end
  for key in core.stripGender(text):gmatch('{([^{}]+)}')do if key=='ground_speech'or not require('pa26_copilot_settings').variables[key]then return nil,'Неизвестная переменная в причине: '..key end end
  out[id]=text
 end
 return out
end
function M.text(cfg,id,gender)
 local text=id=='custom'and cfg.stop_custom or(cfg.ground_speech or M.defaults)[id]
 return core.expandGender(text or'Уточните фактическую причину остановки.',gender)
end
return M
