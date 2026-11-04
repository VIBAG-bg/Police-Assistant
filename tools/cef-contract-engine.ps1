# PA-owned read-only contract verifier. Never evaluates launcher JavaScript.
# This file is embedded in pa26_cef_contract.lua for the SAME installer/runtime
# decision, without extending the frozen updater's file ownership policy.
if (-not ('PaCef0450.Contract' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Security.Cryptography;
using System.Diagnostics;
namespace PaCef0450 {
 public sealed class Tok { public string v,k; public int a,b; public Tok(string v,string k,int a,int b){this.v=v;this.k=k;this.a=a;this.b=b;} }
 public sealed class Contract {
  public static string Hash(byte[] bytes){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
  public static byte[] ReadLimited(string path,int limit){using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
   long size=f.Length;if(size<1||size>limit)throw new Exception("file_size");byte[] b=new byte[(int)size];int n=0;while(n<b.Length){int got=f.Read(b,n,b.Length-n);if(got==0)throw new Exception("file_changed");n+=got;}if(f.ReadByte()!=-1)throw new Exception("file_changed");return b;}}
  static bool Id(char c){return Char.IsLetterOrDigit(c)||c=='_'||c=='$';}
  public static List<Tok> Tokens(string s) {
   var t=new List<Tok>();var watch=Stopwatch.StartNew();
   for(int i=0;i<s.Length;) {
    if(t.Count>650000 || watch.ElapsedMilliseconds>8000)throw new Exception("analysis_limit");
    char c=s[i];if(Char.IsWhiteSpace(c)){i++;continue;}int a=i;
    if(c=='/'&&i+1<s.Length&&s[i+1]=='/'){i+=2;while(i<s.Length&&s[i]!='\r'&&s[i]!='\n')i++;continue;}
    if(c=='/'&&i+1<s.Length&&s[i+1]=='*'){int end=s.IndexOf("*/",i+2,StringComparison.Ordinal);if(end<0)throw new Exception("js_comment");i=end+2;continue;}
    if(c=='\''||c=='"'||c=='`'){
     char q=c;i++;bool closed=false;
     while(i<s.Length){if(s[i]=='\\'){i+=2;continue;}if(s[i++]==q){closed=true;break;}}
     if(!closed)throw new Exception("js_string");t.Add(new Tok(s.Substring(a,i-a),"str",a,i));continue;
    }
    if(Char.IsLetter(c)||c=='_'||c=='$') {i++;while(i<s.Length&&Id(s[i]))i++;t.Add(new Tok(s.Substring(a,i-a),"id",a,i));continue;}
    if(Char.IsDigit(c)) {i++;while(i<s.Length&&(Id(s[i])||s[i]=='.'))i++;t.Add(new Tok(s.Substring(a,i-a),"num",a,i));continue;}
    // Regex literals are opaque tokens. Division remains punctuation. The
    // reviewed grammar uses no ambiguous regex after a closing control block.
    string prev=t.Count==0?"":t[t.Count-1].v;
    if(c=='/'&&(prev=="("||prev=="="||prev==","||prev==":"||prev=="return"||prev=="!"||prev=="["||prev=="&&"||prev=="||"||prev=="?")){
     i++;bool cls=false,closed=false;
     while(i<s.Length){char ch=s[i++];if(ch=='\\'){i++;continue;}if(ch=='[')cls=true;if(ch==']')cls=false;if(ch=='/'&&!cls){closed=true;break;}if(ch=='\n'||ch=='\r')break;}
     if(!closed)throw new Exception("js_regex");while(i<s.Length&&Char.IsLetter(s[i]))i++;t.Add(new Tok(s.Substring(a,i-a),"regex",a,i));continue;
    }
    string op=null;
    foreach(string v in new[]{"===","!==",">>>","**=","=>","==","!=","<=",">=","++","--","&&","||","+=","-=","*=","/=","<<",">>","?.","??","**"})if(i+v.Length<=s.Length&&s.Substring(i,v.Length)==v){op=v;break;}
    if(op==null)op=c.ToString();i+=op.Length;t.Add(new Tok(op,"p",a,i));
   }return t;
  }
  static Dictionary<int,int> Pairs(List<Tok> t){
   var d=new Dictionary<int,int>();var stack=new Stack<int>();
   for(int i=0;i<t.Count;i++){string v=t[i].v;if(t[i].k!="p")continue;
    if(v=="("||v=="["||v=="{"){if(stack.Count>=512)throw new Exception("js_depth");stack.Push(i);}
    else if(v==")"||v=="]"||v=="}"){if(stack.Count==0)throw new Exception("js_balance");int x=stack.Pop();if((t[x].v+v)!="()"&&(t[x].v+v)!="[]"&&(t[x].v+v)!="{}")throw new Exception("js_balance");d[x]=i;}
   }if(stack.Count!=0)throw new Exception("js_balance");return d;
  }
  static string Canon(List<Tok> t,int a,int b,Dictionary<int,int> omitted){
   var s=new StringBuilder();var ids=new Dictionary<string,string>();
   for(int i=a;i<=b;i++){
    int end;if(omitted!=null&&omitted.TryGetValue(i,out end)){s.Append("{PA_FUNCTION_BODY};");i=end;continue;}
    string v=t[i].v;
    if(t[i].k=="id"&&Regex.IsMatch(v,"^_0x[0-9a-fA-F]+$")){string id;if(!ids.TryGetValue(v,out id)){id="p"+ids.Count;ids[v]=id;}v=id;}
    s.Append(t[i].k).Append(':').Append(v.Length).Append(':').Append(v).Append(';');
   }return Hash(Encoding.UTF8.GetBytes(s.ToString()));
  }
  public static Dictionary<string,string> Inventory(string s,string[] names){
   var t=Tokens(s);var pairs=Pairs(t);var functions=new Dictionary<string,int[]>();var omit=new Dictionary<int,int>();
   for(int i=0;i+3<t.Count;i++)if(t[i].v=="function"&&t[i+1].k=="id"&&t[i+2].v=="("){
    int close=pairs[i+2];if(close+1>=t.Count||t[close+1].v!="{")throw new Exception("js_function");int end=pairs[close+1];
    string name=t[i+1].v;if(functions.ContainsKey(name))throw new Exception("js_duplicate_function");
    functions[name]=new[]{i,end};omit[close+1]=end;i=end;
   }
   var result=new Dictionary<string,string>();
   if(functions.Count>2048)throw new Exception("analysis_limit");int work=0;var closure=new HashSet<string>(names);bool changed=true;
   while(changed){if(closure.Count>512||work>4000000)throw new Exception("analysis_limit");changed=false;foreach(string n in new List<string>(closure)){int[] f;if(!functions.TryGetValue(n,out f))throw new Exception("missing_function:"+n);for(int i=f[0];i<=f[1];i++){work++;if(t[i].k=="id"&&functions.ContainsKey(t[i].v)&&closure.Add(t[i].v))changed=true;}}}
   foreach(string n in closure){int[] f;if(!functions.TryGetValue(n,out f))throw new Exception("missing_function:"+n);result[n]=Canon(t,f[0],f[1],null);}
   // Pin literal string table, decoder and rotation bootstrap, not just event
   // spellings. A changed indirect payload must invalidate its whole profile.
   if(t.Count<6||t[0].v!="const"||t[1].k!="id"||t[2].v!="="||t[3].k!="id"||t[4].v!=";")throw new Exception("decoder_bootstrap");
   int[] decoder;if(!functions.TryGetValue(t[3].v,out decoder))throw new Exception("decoder_function");
   result["$decoder"]=Canon(t,decoder[0],decoder[1],null);
   int table=decoder[0]+8;string tableName=null;
   for(int i=decoder[0];i+2<=decoder[1]&&i<decoder[0]+40;i++)if(t[i].v=="="&&t[i+1].k=="id"&&t[i+2].v=="("){tableName=t[i+1].v;break;}
   int[] tableRange;if(tableName==null||!functions.TryGetValue(tableName,out tableRange))throw new Exception("decoder_table");
   result["$table"]=Canon(t,tableRange[0],tableRange[1],null);
   result["$initialization_and_events"]=Canon(t,0,t.Count-1,omit);
   // Other function bodies may evolve, but adding references to any protected
   // chat API/variable in them cannot pass as an unrelated implementation edit.
   var protectedNames=new HashSet<string>(closure);foreach(var name in new[]{"cef","chatInputField","chatInputElement","chatContainer","chatMsgList","dialogElement","sendMessageToChat","eval","Function","globalThis","window","document","Object","Reflect","Proxy"})protectedNames.Add(name);
   var surface=new List<string>();
   foreach(var f in functions)if(!closure.Contains(f.Key)&&f.Key!=t[3].v&&f.Key!=tableName){
    var parts=new List<string>();for(int i=f.Value[0];i<=f.Value[1];i++)if(t[i].k=="id"&&protectedNames.Contains(t[i].v))parts.Add(t[i].v);
    if(parts.Count>0)surface.Add(f.Key+":"+Canon(t,f.Value[0],f.Value[1],null));
   }surface.Sort(StringComparer.Ordinal);result["$protected_references"]=Hash(Encoding.UTF8.GetBytes(String.Join("\n",surface.ToArray())));
   return result;
  }
  public static string Markup(string html){
   if(html.Length<1||html.Length>1048576||html.IndexOf('\0')>=0)return "html_size";
   var ids=new Dictionary<string,string>();var stack=new Stack<string>();bool fieldInside=false;int main=0,adapter=0;
   var clean=new StringBuilder();int cursor=0;while(cursor<html.Length){int at=html.IndexOf("<!--",cursor,StringComparison.Ordinal);if(at<0){clean.Append(html.Substring(cursor));break;}int end=html.IndexOf("-->",at+4,StringComparison.Ordinal);if(end<0)return "html_comment";clean.Append(html.Substring(cursor,at-cursor));cursor=end+3;}html=clean.ToString();
   var tags=Regex.Matches(html,"<[^<>]{1,8192}>");
   foreach(Match m in tags){string tag=m.Value;if(tag.StartsWith("<!--"))continue;
    var name=Regex.Match(tag,"^<(/?)([a-zA-Z][a-zA-Z0-9-]*)");if(!name.Success)continue;
    string n=name.Groups[2].Value.ToLowerInvariant();bool closing=name.Groups[1].Value=="/";
    if(closing){if(n=="form"){if(stack.Count==0)return "html_form";stack.Pop();}continue;}
    bool duplicate=false;var attrs=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
    foreach(Match a in Regex.Matches(tag.Substring(name.Length),"([a-zA-Z_:][a-zA-Z0-9_:.-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))")){
     string key=a.Groups[1].Value;if(attrs.ContainsKey(key))duplicate=true;attrs[key]=a.Groups[2].Success?a.Groups[2].Value:a.Groups[3].Success?a.Groups[3].Value:a.Groups[4].Value;
    }
    string id;attrs.TryGetValue("id",out id);if(id!=null){if(ids.ContainsKey(id)&&(id=="chatInput"||id=="chatInputField"||id=="chatMsgList"||id=="Dialog"||id=="SendMsgButton"))return "html_duplicate_id";ids[id]=n;}
    if(duplicate&&(n=="script"||id=="chatInputField"||id=="chatInput"||id=="Dialog"||id=="chatMsgList"||id=="SendMsgButton"))return "html_duplicate_attribute";
    if(n=="form")stack.Push(id??"");
    if(id=="chatInputField")fieldInside=n=="input"&&stack.Count>0&&stack.Peek()=="chatInput"&&(!attrs.ContainsKey("type")||attrs["type"].ToLowerInvariant()=="text");
    if(id=="chatInputField"&&Regex.IsMatch(tag,"\\s(?:readonly|disabled)(?:\\s|=|>)",RegexOptions.IgnoreCase))return "html_input_disabled";
    if(n=="script"){
     if(Regex.IsMatch(tag,"\\s(?:async|defer)(?:\\s|=|>)",RegexOptions.IgnoreCase)||attrs.ContainsKey("type"))return "html_async_script";
     string src;if(!attrs.TryGetValue("src",out src))return "html_inline_script";
     if(src=="main.js")main++;else if(src=="pa26-chat.js")adapter++;else return "html_extra_script";
    }
   }
   foreach(string id in new[]{"chatInput","chatInputField","chatMsgList","Dialog","SendMsgButton"})if(!ids.ContainsKey(id))return "missing_dom:"+id;
   if(ids["chatInput"]!="form"||ids["Dialog"]!="div"||!fieldInside||main!=1||adapter>1||stack.Count!=0)return "html_structure";
   return "verified";
  }
 }
}
'@
}
function Get-PaCefContract([string]$HudRoot, $Registry, [switch]$Inventory) {
 $result=@{schema=2;state='UNAVAILABLE';allowed=$false;known=$false;reason='files_unavailable';sha256=$null;fingerprint=$null;
  mode='native-only';capabilities=@{};runtime='NOT_RUN';protocol=2}
 try {
  $main=Join-Path $HudRoot 'main.js';$html=Join-Path $HudRoot 'index.html'
  foreach($path in @($main,$html)){
   $ancestor=[IO.Path]::GetFullPath($path)
   while($ancestor){$node=Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop;if(($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'unsafe_path'};$ancestor=[IO.Path]::GetDirectoryName($ancestor)}
   $file=Get-Item -LiteralPath $path -ErrorAction Stop
   if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'unsafe_path'}
   if($file.Length -gt $(if($path -eq $main){4194304}else{1048576}) -or $file.Length -lt 1){throw 'file_size'}
  }
  $bytes=[PaCef0450.Contract]::ReadLimited($main,4194304);$result.sha256=[PaCef0450.Contract]::Hash($bytes)
  $markup=[PaCef0450.Contract]::Markup([Text.Encoding]::UTF8.GetString([PaCef0450.Contract]::ReadLimited($html,1048576)))
  if($markup -ne 'verified'){$result.state='INCOMPATIBLE';$result.reason=$markup;return $result}
  $result.capabilities.dom=$true
  $known=@($Registry.known_versions|Where-Object sha256 -CEQ $result.sha256)
  if($known.Count -eq 1 -and -not $Inventory){
   $result.known=$true;$result.fingerprint=$known[0].fingerprint;$result.reason='reviewed_identity_and_dom'
  }else{
   $text=[Text.Encoding]::UTF8.GetString($bytes)
   $map=[PaCef0450.Contract]::Inventory($text,[string[]]$Registry.required_functions)
   if($Inventory){$result.inventory=$map}
   foreach($profile in $Registry.contract_profiles){
    $match=$true
    if(@($profile.components.PSObject.Properties).Count -ne $map.Count){$match=$false}
    foreach($item in $profile.components.PSObject.Properties){if(-not $map.ContainsKey($item.Name) -or $map[$item.Name] -cne $item.Value){$match=$false;break}}
    if($match){$result.fingerprint=$profile.fingerprint;break}
   }
   if(-not $result.fingerprint){$result.state='INCOMPATIBLE';$result.reason='functional_profile_mismatch';return $result}
   $result.reason='normalized_contract_and_dom'
  }
  $result.capabilities=@{dom=$true;outgoing=$true;incoming=$true;payloads=$true;lifecycle=$true;focus=$true;ipc=$true;adapter_order=$true}
  $result.state='CONTRACT_COMPATIBLE';$result.allowed=$true;$result.mode='cef-provisional'
 }catch{$result.reason=if($_.Exception.Message -match '^(js_|decoder_|missing_function|analysis_limit|unsafe_path|file_size)'){$_.Exception.Message}else{'files_or_analysis_unavailable'};if($result.sha256){$result.state='INCOMPATIBLE'}}
 return $result
}
