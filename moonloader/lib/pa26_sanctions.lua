-- Read-only view of the same source-linked articles used by the knowledge base.
local core=require 'pa26_core';local model=require 'pa26_bindings'
local M={};local Catalog={};Catalog.__index=Catalog
function M.new(data)
 local self=setmetatable({rows={},byId={}},Catalog)
 for _,a in ipairs(data and data.articles or{})do if a.code=='AK'and type(a.text)=='string'then
  local r={id=a.id,number=tonumber(a.article),article='АК ст. '..a.article,title=a.title,text=a.text,
   source=model.copy(a.source),hash=a.source_text_sha256,branches={}}
  for _,b in ipairs(a.sanctions or{})do
   if b.kind=='fine'and b.unit=='ПМ'and core.finite(b.min)and core.finite(b.max)and b.min>=0 and b.min<=b.max and
      b.source_text_sha256==a.source_text_sha256 and type(b.source_excerpt)=='string'and a.text:find(b.source_excerpt,1,true)then
    local value=model.copy(b);value.condition=value.condition or r.title;value.alternative=value.alternative or value.source_excerpt;r.branches[#r.branches+1]=value
   end
  end
  self.rows[#self.rows+1]=r;self.byId[r.id]=r
 end end
 table.sort(self.rows,function(a,b)return a.number<b.number end);return self
end
function Catalog:branch(id,index)
 local r=self.byId[id];return r and r.branches[index or 1],r
end
function Catalog:search(query,category)
 local out={};query=model.casefold(query or''):gsub('ё','е'):match('^%s*(.-)%s*$')
 for _,r in ipairs(self.rows)do
  local n=r.number;local include=category=='road'and n>=37 and n<=49 or category=='order'and n>=20 and n<=36 or
   category=='police'and n>=50 and n<=61 or category==nil or category=='all'
  if include and(query==''or model.casefold(r.article..' '..r.title):gsub('ё','е'):find(query,1,true))then out[#out+1]=r end
 end;return out
end
function M.money(branch,rate,mode)
 if not branch or not core.finite(rate)or rate%1~=0 or rate<=0 or rate>1000000 then return nil,'Укажите целый курс ПМ от 1 до 1000000; 0 отключает расчёт.'end
 local pm=mode=='min'and branch.min or mode=='max'and branch.max or mode=='mid'and(branch.min+branch.max)/2
 if not core.finite(pm)then return nil,'Выберите допустимую ветвь и вариант суммы.'end
 local amount=math.floor(pm*rate+.5)
 if not core.finite(amount)or amount<1 or amount>999999999 then return nil,'Сумма выходит за допустимый диапазон. Введите её вручную.'end
 return tostring(amount)
end
function M.select(form,row,index)
 local b=row and row.branches[index or 1];if not b then return nil,'Для этой статьи нет проверенной денежной ветви.'end
 form.sanction_id=row.id;form.sanction_branch=index or 1;form.sanction_hash=row.hash
 form.article=row.article;form.part='';form.basis=row.article..' · '..row.title
 return true
end
function Catalog:valid(form)
 if not form.sanction_id then return true end
 local b,r=self:branch(form.sanction_id,form.sanction_branch)
 return b~=nil and r.hash==form.sanction_hash
end
return M
