-- Exercise the visible compact/expanded reader controls, not hidden state.
local M={}
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label)end
function M.filters(s)
 local v=assert(s.knowledgeUi)
 if not v.showFilters then click(s,v.compactView and'Фильтры##kb-filters-compact'or'Показать фильтры и статусы##kb-filters-toggle')end
end
function M.all(s)
 if s.knowledgeUi.knowledge.personal.view.catalog_mode=='current'then click(s,'Актуальное##kb-current-mode')end
end
function M.ack(s)
 if s.workspace.studio:hasWarning()then click(s,'ОК##warning-ok');s.render()end
end
function M.newCard(s)
 if s.knowledgeUi.compactView then click(s,'Данные##kb-mode');click(s,'Создать личную карточку##kb-new-compact')
 else click(s,'Создать карточку##kb-new')end
end
return M
