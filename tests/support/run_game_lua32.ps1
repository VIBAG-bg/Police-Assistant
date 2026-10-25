param([Parameter(Mandatory=$true)][string]$Script)
$ErrorActionPreference='Stop'
if([IntPtr]::Size -ne 4) { throw 'Use the 32-bit PowerShell host.' }
$paGame=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Exsellent Launcher\game')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PaLua32 {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern bool SetDllDirectory(string path);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibrary(string path);
 [DllImport("lua51.dll",CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr luaL_newstate();
 [DllImport("lua51.dll",CallingConvention=CallingConvention.Cdecl)] public static extern void luaL_openlibs(IntPtr l);
 [DllImport("lua51.dll",CallingConvention=CallingConvention.Cdecl)] public static extern int luaL_loadfile(IntPtr l,string path);
 [DllImport("lua51.dll",CallingConvention=CallingConvention.Cdecl)] public static extern int lua_pcall(IntPtr l,int nargs,int results,int err);
 [DllImport("lua51.dll",CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr lua_tolstring(IntPtr l,int index,out UIntPtr len);
 [DllImport("lua51.dll",CallingConvention=CallingConvention.Cdecl)] public static extern void lua_close(IntPtr l);
}
'@
[PaLua32]::SetDllDirectory($paGame) | Out-Null
if([PaLua32]::LoadLibrary((Join-Path $paGame 'lua51.dll')) -eq [IntPtr]::Zero) { throw 'Cannot load the installed Lua runtime.' }
$paState=[PaLua32]::luaL_newstate()
if($paState -eq [IntPtr]::Zero) { throw 'Cannot create Lua state.' }
try {
 [PaLua32]::luaL_openlibs($paState)
 $paStatus=[PaLua32]::luaL_loadfile($paState,[IO.Path]::GetFullPath($Script))
 if($paStatus -eq 0) { $paStatus=[PaLua32]::lua_pcall($paState,0,0,0) }
 if($paStatus -ne 0) {
  $paLength=[UIntPtr]::Zero;$paError=[PaLua32]::lua_tolstring($paState,-1,[ref]$paLength)
  throw [Runtime.InteropServices.Marshal]::PtrToStringAnsi($paError,$paLength.ToUInt32())
 }
} finally { [PaLua32]::lua_close($paState) }
