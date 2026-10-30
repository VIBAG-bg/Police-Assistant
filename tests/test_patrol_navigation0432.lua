local fixture=require 'support.fixture';local routes=require 'support.ui_routes'
local s=fixture({demo=false});s.step();s.page('addons');routes.click(s,'Открыть быстрое окно помощников (F4)##assist-open')
routes.click(s,'Патруль##assist-tabspatrol');local before=s.workspace.studio.partnerPage
routes.click(s,'Трафик-стоп и преследование##patrol-vehicle')
eq(s.workspace.studio.assistPage,'traffic');eq(s.workspace.studio.partnerPage,before,'F4 cannot mutate F9 partner navigation')
onScriptTerminate(s.script)
s=fixture({demo=false});s.step();s.page('partners');routes.click(s,'Патруль##Напарники и служба##partners-pagepatrol')
local assist=s.workspace.studio.assistPage;routes.click(s,'Трафик-стоп и преследование##patrol-vehicle')
eq(s.workspace.studio.partnerPage,'vehicle');eq(s.workspace.studio.assistPage,assist,'F9 cannot mutate F4 navigation')
onScriptTerminate(s.script)
