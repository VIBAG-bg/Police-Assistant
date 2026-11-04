-- Pure controller. The production backend remains absent until input units and
-- release semantics are verified. No raw memory writes or guessed game keys.
local core=require 'pa26_core';local M={};local C={};C.__index=C
function M.new(backend)return setmetatable({backend=backend,active=false,signal='off',injected=false},C)end
local function safe(s)
 return s and s.session and s.alive and s.focused and not s.paused and not s.typing and not s.modal and not s.blocked and
  s.driver==true and s.vehicle_class=='car'and s.vehicle and not s.brake and not s.handbrake
end
function C:release(reason)
 local b=self.backend
 if self.injected and b and b.release then pcall(b.release,b)end
 self.injected=false;self.active=false;self.vehicle=nil;self.signal='off';self.reason=reason
end
function C:engage(s,cfg)
 if not cfg.enabled or not cfg.cruise then return nil,'Круиз выключен.'end
 if not self.backend or self.backend.verified~=true then return nil,'Управление GTA не проверено: круиз недоступен на этой сборке.'end
 if not safe(s)then return nil,'Нужен водитель автомобиля и свободный игровой ввод.'end
 self.vehicle=s.vehicle;self.session=s.session;self.active=true;self.speed=cfg.target_speed;self.reason=nil;return true
end
function C:tick(s,cfg)
 if not self.active then return end
 if not cfg.enabled or not cfg.cruise or not safe(s)or s.vehicle~=self.vehicle or s.session~=self.session or not core.finite(s.speed)then self:release('Круиз безопасно отключён.');return end
 -- A failing backend may already have injected input. Release on every failure.
 self.injected=true
 local ok,result=pcall(self.backend.drive,self.backend,s.speed,self.speed)
 if not ok or result~=true then self:release('Ошибка управления. Повторное включение только вручную.');return end
 self.injected=true
end
function C:toggleSignal(kind,s,cfg)
 if not cfg.enabled or not cfg.signals or not safe(s)then return nil,'Поворотники выключены или машина недоступна.'end
 if not self.backend or not self.backend.signalsVerified then return nil,'Геометрия локальных индикаторов ещё не проверена.'end
 if not({left=true,right=true,hazard=true})[kind]then return nil,'Неизвестный индикатор.'end
 self.signal=self.signal==kind and'off'or kind;return true
end
function C:view()return {active=self.active,speed=self.speed,signal=self.signal,reason=self.reason or'Native-управление и индикаторы не проверены; выключены'}end
return M
