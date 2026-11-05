param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Stage)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([IntPtr]::Size -ne 4){throw 'Для проверки старого набора нужен 32-битный Windows PowerShell.'}

Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

// Run the PA validators with JSON passed through the Lua stack as data.
// Only manifest-checked PA modules are registered. No game script is loaded.
public static class PaLegacyLua {
    private const string Lua = "lua51.dll";
    private static readonly Encoding Utf8 = new UTF8Encoding(false, true);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern IntPtr LoadLibraryEx(string path, IntPtr reserved, uint flags);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern IntPtr luaL_newstate();
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void luaL_openlibs(IntPtr state);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_close(IntPtr state);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern int lua_checkstack(IntPtr state, int count);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern int lua_gettop(IntPtr state);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_settop(IntPtr state, int top);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern int luaL_loadbuffer(IntPtr state, byte[] buffer, UIntPtr length, string name);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern int lua_pcall(IntPtr state, int args, int results, int error);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_getfield(IntPtr state, int index, string key);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_setfield(IntPtr state, int index, string key);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_settable(IntPtr state, int index);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_createtable(IntPtr state, int array, int keys);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_rawseti(IntPtr state, int index, int key);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_pushlstring(IntPtr state, byte[] bytes, UIntPtr length);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_pushnumber(IntPtr state, double number);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_pushboolean(IntPtr state, int value);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern void lua_pushnil(IntPtr state);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern int lua_type(IntPtr state, int index);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern int lua_toboolean(IntPtr state, int index);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern double lua_tonumber(IntPtr state, int index);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern IntPtr lua_tolstring(IntPtr state, int index, out UIntPtr length);
    [DllImport(Lua, CallingConvention=CallingConvention.Cdecl)] private static extern int lua_next(IntPtr state, int index);

    private static string StringAt(IntPtr state, int index) {
        UIntPtr length;
        IntPtr ptr = lua_tolstring(state, index, out length);
        if (ptr == IntPtr.Zero) throw new InvalidDataException("Invalid Lua string");
        byte[] bytes = new byte[checked((int)length.ToUInt64())];
        Marshal.Copy(ptr, bytes, 0, bytes.Length);
        return Utf8.GetString(bytes);
    }
    private static void PushString(IntPtr state, string value) {
        byte[] bytes = Utf8.GetBytes(value);
        lua_pushlstring(state, bytes, (UIntPtr)bytes.Length);
    }
    private static void Push(IntPtr state, object value, int depth) {
        if (depth > 64 || lua_checkstack(state, 4) == 0) throw new InvalidDataException("Invalid configuration depth");
        IDictionary dictionary = value as IDictionary;
        IList list = value as IList;
        if (dictionary != null) {
            lua_createtable(state, 0, dictionary.Count);
            foreach (DictionaryEntry item in dictionary) {
                PushString(state, (string)item.Key);
                Push(state, item.Value, depth+1);
                lua_settable(state, -3);
            }
        } else if (list != null) {
            lua_createtable(state, list.Count, 0);
            for (int i=0; i<list.Count; ++i) {
                Push(state, list[i], depth+1);
                lua_rawseti(state, -2, i+1);
            }
        } else if (value == null) lua_pushnil(state);
        else if (value is string) PushString(state, (string)value);
        else if (value is bool) lua_pushboolean(state, (bool)value ? 1 : 0);
        else lua_pushnumber(state, Convert.ToDouble(value, CultureInfo.InvariantCulture));
    }
    private static object Read(IntPtr state, int index, int depth) {
        if (depth > 64 || lua_checkstack(state, 4) == 0) throw new InvalidDataException("Invalid result depth");
        if (index < 0) index = lua_gettop(state) + index + 1;
        switch (lua_type(state, index)) {
            case 0: return null;
            case 1: return lua_toboolean(state, index) != 0;
            case 3: return lua_tonumber(state, index);
            case 4: return StringAt(state, index);
            case 5:
                Dictionary<string,object> result = new Dictionary<string,object>(StringComparer.Ordinal);
                bool array = true;
                int max = 0;
                lua_pushnil(state);
                while (lua_next(state,index) != 0) {
                    string key;
                    if (lua_type(state,-2) == 3) {
                        double number = lua_tonumber(state,-2);
                        key = number.ToString(CultureInfo.InvariantCulture);
                        if (number < 1 || number > Int32.MaxValue || number != Math.Floor(number)) array = false;
                        else max = Math.Max(max,(int)number);
                    } else {
                        if (lua_type(state,-2) != 4) throw new InvalidDataException("Invalid result key");
                        key = StringAt(state,-2);
                        array = false;
                    }
                    result.Add(key,Read(state,-1,depth+1));
                    lua_settop(state,-2);
                }
                if (!array || max != result.Count || max == 0) return result;
                object[] items = new object[max];
                for (int i=0; i<max; ++i) items[i] = result[(i+1).ToString(CultureInfo.InvariantCulture)];
                return items;
            default: throw new InvalidDataException("Invalid Lua result");
        }
    }
    public static byte[] Verified(string path, string expected) {
        byte[] bytes = File.ReadAllBytes(path);
        using (SHA256 sha = SHA256.Create()) {
            string actual = BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
            if (actual != expected) throw new InvalidDataException("PA validator integrity mismatch: "+Path.GetFileName(path));
        }
        return bytes;
    }
    private static void Load(IntPtr state, byte[] bytes, string name) {
        if (luaL_loadbuffer(state,bytes,(UIntPtr)bytes.Length,name) != 0) throw new InvalidDataException(StringAt(state,-1));
    }
    private static void Call(IntPtr state, int args, int results) {
        if (lua_pcall(state,args,results,0) != 0) throw new InvalidDataException(StringAt(state,-1));
    }
    public static void Run(string stage, Dictionary<string,byte[]> modules, byte[] runner) {
        string dll = Path.Combine(stage,"lua51.dll");
        Verified(dll,"ff976f6e965e3793e278fa9bf5e80b9b226a0b3932b9da764bffc8e41e6cdb60");
        if (LoadLibraryEx(dll,IntPtr.Zero,8) == IntPtr.Zero) throw new InvalidDataException("Cannot start verified LuaJIT");
        IntPtr state = luaL_newstate();
        if (state == IntPtr.Zero) throw new OutOfMemoryException();
        try {
            luaL_openlibs(state);
            lua_getfield(state,-10002,"package");
            PushString(state,""); lua_setfield(state,-2,"path");
            PushString(state,""); lua_setfield(state,-2,"cpath");
            lua_getfield(state,-1,"preload");
            foreach (KeyValuePair<string,byte[]> module in modules) {
                Load(state,module.Value,module.Key);
                lua_setfield(state,-2,module.Key);
            }
            lua_settop(state,0);
            Load(state,runner,"pa-legacy-presets");
            Call(state,0,1);
            JavaScriptSerializer json = new JavaScriptSerializer();
            json.MaxJsonLength = 8388608;
            json.RecursionLimit = 64;
            Push(state,json.DeserializeObject(File.ReadAllText(Path.Combine(stage,"in.json"),Utf8)),0);
            Call(state,1,1);
            File.WriteAllText(Path.Combine(stage,"out.json"),json.Serialize(Read(state,-1,0)),Utf8);
        } finally { lua_close(state); }
    }
}
'@ -ReferencedAssemblies System.Web.Extensions

try {
    $manifest=[IO.File]::ReadAllText((Join-Path $Source 'INSTALL_MANIFEST.json'))|ConvertFrom-Json
    if($manifest.release -cne '0.45.1'){throw 'Неверная целевая версия переноса.'}
    $modules=New-Object 'Collections.Generic.Dictionary[string,byte[]]'
    foreach($row in $manifest.files){
        if($row.path -cmatch '^lib\\(pa26_[a-z0-9_]+)\.lua$'){
            $name=$Matches[1]
            $modules.Add($name,[PaLegacyLua]::Verified((Join-Path (Join-Path $Source 'moonloader') $row.path),$row.sha256))
        }
    }
    $entry=@($manifest.setup_files|Where-Object path -CEQ 'tools/pa-legacy-presets.lua')
    if($entry.Count -ne 1){throw 'Отсутствует программа проверки переноса.'}
    $runner=[PaLegacyLua]::Verified((Join-Path $Source $entry[0].path),$entry[0].sha256)
    [PaLegacyLua]::Run($Stage,$modules,$runner)
}catch{
    [IO.File]::WriteAllText((Join-Path $Stage 'error.txt'),$_.Exception.GetBaseException().Message,(New-Object Text.UTF8Encoding($false)))
    exit 1
}
