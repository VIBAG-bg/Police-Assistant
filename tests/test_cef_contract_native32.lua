-- Historical command entry point; use the shared adaptive verifier probe.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local root=assert(source:match('^(.*)/tests/'))
dofile(root..'/tests/test_cef_adaptive_native32.lua')
