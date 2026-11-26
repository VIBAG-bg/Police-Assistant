# PA-owned read-only contract verifier. Never evaluates launcher JavaScript.
# This file is embedded in pa26_cef_contract.lua for the SAME installer/runtime
# decision, without extending the frozen updater's file ownership policy.
if (-not ('PaCef0452.Contract' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Security.Cryptography;
using System.Diagnostics;
namespace PaCef0452 {
 public sealed class Tok { public string v,k; public int a,b; public Tok(string v,string k,int a,int b){this.v=v;this.k=k;this.a=a;this.b=b;} }
 public sealed class Contract {
  const string PaMarker="<!-- PA26 CEF chat adapter -->";
  const string PaTag=PaMarker+"<script src=\"pa26-chat.js\"></script>";
  static readonly Regex MainTag=new Regex("<script\\s+src=(['\"])main\\.js\\1\\s*>");
  public static string InstallMarkup(string html){
   string clean=html.Replace(PaTag,"");
   if(html.Length-clean.Length>PaTag.Length||clean.Contains(PaMarker)||clean.Contains("pa26-chat.js"))throw new Exception("html_adapter_tag");
   if(MainTag.Matches(clean).Count!=1)throw new Exception("html_main_tag");
   return MainTag.Replace(clean,PaTag+"$0",1);
  }
  public static string Hash(byte[] bytes){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
  public static byte[] ReadLimited(string path,int limit){using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
   long size=f.Length;if(size<1||size>limit)throw new Exception("file_size");byte[] b=new byte[(int)size];int n=0;while(n<b.Length){int got=f.Read(b,n,b.Length-n);if(got==0)throw new Exception("file_changed");n+=got;}if(f.ReadByte()!=-1)throw new Exception("file_changed");return b;}}
  static bool Id(char c){return Char.IsLetterOrDigit(c)||c=='_'||c=='$';}
  public static List<Tok> Tokens(string s) {
   var t=new List<Tok>();var watch=Stopwatch.StartNew();
   for(int i=0;i<s.Length;) {
    if(t.Count>650000 || watch.ElapsedMilliseconds>8000)throw new Exception("analysis_limit");
    char c=s[i];if(Char.IsWhiteSpace(c)){i++;continue;}int a=i;
    if(c=='/'&&i+1<s.Length&&s[i+1]=='/'){
     i+=2;while(i<s.Length&&s[i]!='\r'&&s[i]!='\n'&&s[i]!='\u2028'&&s[i]!='\u2029')i++;continue;
    }
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
  // This fallback accepts an equivalent string-table literal. All source
  // before and after the array, and all values in the array, are still pinned.
  static bool AppendPackedLiteral(StringBuilder value,string literal) {
   if(literal.Length<2||(literal[0]!='\''&&literal[0]!='"'))return false;
   for(int i=1;i<literal.Length-1;i++){
    char ch=literal[i];
    if(ch=='\\'){
     if(++i>=literal.Length-1)return false;
     ch=literal[i];
     if(ch=='x'||ch=='u'){
      int width=ch=='x'?2:4,result=0;
      if(i+width>=literal.Length-1)return false;
      for(int j=0;j<width;j++){
       int digit="0123456789abcdef".IndexOf(Char.ToLowerInvariant(literal[++i]));
       if(digit<0)return false;
       result=16*result+digit;
      }
      ch=(char)result;
     }else if(ch!='/')return false;
    }
    if(!(ch>='A'&&ch<='Z'||ch>='a'&&ch<='z'||ch>='0'&&ch<='9'||ch=='+'||ch=='/'||ch=='='))return false;
    value.Append(ch);
   }
   return true;
  }
  static string RepackedSignature(string source,List<Tok> tokens,Dictionary<int,int> pairs,int[] range){
   int start=range[0]+8;
   if(start>=range[1]||tokens[range[0]+3].v!=")"||tokens[start-4].v!="{"||
    tokens[start-3].v!="const"||tokens[start-2].k!="id"||tokens[start-1].v!="="||tokens[start].v!="[")return null;
   int end;
   if(!pairs.TryGetValue(start,out end)||end>=range[1])return null;
   // Do not discard comments or non-JS whitespace inside the relaxed range.
   for(int next=start+1;next<=end;next++){
    for(int i=tokens[next-1].b;i<tokens[next].a;i++){
     char ch=source[i];
     if(ch!=' '&&ch!='\t'&&ch!='\r'&&ch!='\n')return null;
    }
   }
   var values=new StringBuilder();var item=new StringBuilder();
   for(int cursor=start+1;cursor<end;){
    item.Clear();
    do{
     if(cursor>=end||tokens[cursor].k!="str"||!AppendPackedLiteral(item,tokens[cursor++].v))return null;
     if(cursor==end||tokens[cursor].v!="+")break;
     cursor++;
    }while(true);
    // The delimiter cannot occur in an accepted value. Keep order, length
    // and empty elements significant, including the first rotation seed.
    values.Append(':').Append(item);
    if(cursor<end&&tokens[cursor++].v!=",")return null;
   }
   var utf8=Encoding.UTF8;
   string prefix=Hash(utf8.GetBytes(source.Substring(0,tokens[start].a)));
   string suffix=Hash(utf8.GetBytes(source.Substring(tokens[end].b)));
   return Hash(utf8.GetBytes("pa-cef-table-v1:"+prefix+":"+suffix+":"+Hash(utf8.GetBytes(values.ToString()))));
  }
  public static Dictionary<string,string> Inventory(string s,string[] names,out string repacked){
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
   repacked=RepackedSignature(s,t,pairs,tableRange);
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
     if(src=="main.js"){if(!MainTag.IsMatch(tag))return "html_main_tag";main++;}else if(src=="pa26-chat.js")adapter++;else return "html_extra_script";
    }
   }
   foreach(string id in new[]{"chatInput","chatInputField","chatMsgList","Dialog","SendMsgButton"})if(!ids.ContainsKey(id))return "missing_dom:"+id;
   if(ids["chatInput"]!="form"||ids["Dialog"]!="div"||ids["chatMsgList"]!="div"||ids["SendMsgButton"]!="svg"||
    !fieldInside||main!=1||adapter>1||stack.Count!=0)return "html_structure";
   return "verified";
  }
 }
}
'@
}
function Find-PaCefProfile($Profiles,$Map,[string]$Repacked,[string]$InterfaceVersion) {
 $pattern='^'+[regex]::Escape($InterfaceVersion)+':[a-f0-9]{64}$'
 foreach($profile in @($Profiles)){
  if($null -eq $profile -or -not $profile.PSObject.Properties['components'] -or
     -not $profile.PSObject.Properties['fingerprint'] -or $profile.fingerprint -isnot [string] -or
     $profile.fingerprint -cnotmatch $pattern -or $profile.components -isnot [pscustomobject]){continue}
  $items=@($profile.components.PSObject.Properties)
  if($items.Count -ne $Map.Count){continue}
  $wellFormed=$true;$exact=$true
  foreach($item in $items){
   if($item.Name -cnotmatch '^[A-Za-z_$][A-Za-z0-9_$]{0,80}$' -or
      -not $Map.ContainsKey($item.Name) -or $item.Value -isnot [string] -or
      $item.Value -cnotmatch '^[a-f0-9]{64}$'){$wellFormed=$false;break}
   if($Map[$item.Name] -cne $item.Value){$exact=$false}
  }
  if(-not $wellFormed){continue}
  if($exact){return @{fingerprint=$profile.fingerprint;reason='normalized_contract_and_dom'}}
  if($Repacked -and $profile.PSObject.Properties['repacked_sha256'] -and
     $profile.repacked_sha256 -is [string] -and $profile.repacked_sha256 -ceq $Repacked){
   return @{fingerprint=$profile.fingerprint;reason='normalized_repacked_and_dom'}
  }
 }
}
function Get-PaPublishedCefRegistry {
 # The official repository is fixed independently of any update/user URL.
 # Consume bounded HTTPS JSON data only. Redirects and credentials are disabled.
 $uri='https://raw.githubusercontent.com/VIBAG-bg/Police-Assistant/main/CEF_CONTRACT.json'
 $prior=[Net.ServicePointManager]::SecurityProtocol
 $response=$null;$buffer=$null;$stream=$null
 try {
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $request=[Net.HttpWebRequest]::Create($uri)
  $request.AllowAutoRedirect=$false;$request.UseDefaultCredentials=$false
  $request.Timeout=5000;$request.ReadWriteTimeout=3000
  $request.UserAgent='Police-Assistant-CEF'
  $response=$request.GetResponse()
  $limit=131072
  if([int]$response.StatusCode -ne 200 -or $response.ContentLength -gt $limit){throw 'profile_response'}
  $stream=$response.GetResponseStream()
  $buffer=New-Object IO.MemoryStream
  $chunk=New-Object byte[] 8192
  $clock=[Diagnostics.Stopwatch]::StartNew()
  while(($read=$stream.Read($chunk,0,$chunk.Length)) -gt 0){
   if($clock.ElapsedMilliseconds -gt 5000 -or $buffer.Length+$read -gt $limit){throw 'profile_size_or_timeout'}
   $buffer.Write($chunk,0,$read)
  }
  if($clock.ElapsedMilliseconds -gt 5000 -or $buffer.Length -eq 0){throw 'profile_response'}
  $utf8=New-Object Text.UTF8Encoding($false,$true)
  $utf8.GetString($buffer.ToArray()) | ConvertFrom-Json -ErrorAction Stop
 } finally {
  if($stream){$stream.Dispose()}
  if($response){$response.Dispose()}
  if($buffer){$buffer.Dispose()}
  [Net.ServicePointManager]::SecurityProtocol=$prior
 }
}
function Get-PaCefContract([string]$HudRoot, $Registry, [switch]$Inventory, [switch]$OnlineProfiles) {
 $result=@{schema=2;state='UNAVAILABLE';allowed=$false;known=$false;reason='files_unavailable';sha256=$null;fingerprint=$null;
  html_sha256=$null;mode='native-only';capabilities=@{};runtime='NOT_RUN';protocol=2;profile_source=$null;profile_lookup='not_needed'}
 try {
  $main=Join-Path $HudRoot 'main.js';$html=Join-Path $HudRoot 'index.html'
  foreach($path in @($main,$html)){
   $ancestor=[IO.Path]::GetFullPath($path)
   while($ancestor){$node=Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop;if(($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'unsafe_path'};$ancestor=[IO.Path]::GetDirectoryName($ancestor)}
   $file=Get-Item -LiteralPath $path -ErrorAction Stop
   if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'unsafe_path'}
   if($file.Length -gt $(if($path -eq $main){4194304}else{1048576}) -or $file.Length -lt 1){throw 'file_size'}
  }
  $bytes=[PaCef0452.Contract]::ReadLimited($main,4194304);$result.sha256=[PaCef0452.Contract]::Hash($bytes)
  $htmlBytes=[PaCef0452.Contract]::ReadLimited($html,1048576)
  $result.html_sha256=[PaCef0452.Contract]::Hash($htmlBytes)
  $utf8=New-Object Text.UTF8Encoding($false,$true)
  $htmlText=$utf8.GetString($htmlBytes)
  $markup=[PaCef0452.Contract]::Markup($htmlText)
  if($markup -ne 'verified'){$result.state='INCOMPATIBLE';$result.reason=$markup;return $result}
  [PaCef0452.Contract]::InstallMarkup($htmlText)|Out-Null
  $result.capabilities.dom=$true
  $known=@($Registry.known_versions|Where-Object sha256 -CEQ $result.sha256)
  if($known.Count -eq 1 -and -not $Inventory){
   $result.known=$true;$result.fingerprint=$known[0].fingerprint;$result.reason='reviewed_identity_and_dom';$result.profile_source='bundled'
  }else{
   try{$text=$utf8.GetString($bytes)}
   catch{$result.state='INCOMPATIBLE';$result.reason='js_encoding';return $result}
   $repacked=''
   $map=[PaCef0452.Contract]::Inventory($text,[string[]]$Registry.required_functions,[ref]$repacked)
   if($Inventory){$result.inventory=$map;$result.repacked_sha256=$repacked}
   $match=Find-PaCefProfile $Registry.contract_profiles $map $repacked $Registry.interface_version
   if($match){$result.profile_source='bundled'}
   elseif($OnlineProfiles){
    try {
     $published=Get-PaPublishedCefRegistry
     if($published -is [pscustomobject] -and $published.PSObject.Properties['schema'] -and
        $published.PSObject.Properties['protocol'] -and $published.PSObject.Properties['interface_version'] -and
        $published.PSObject.Properties['contract_profiles'] -and
        ($published.schema -is [int] -or $published.schema -is [long]) -and $published.schema -eq 2 -and
        ($published.protocol -is [int] -or $published.protocol -is [long]) -and $published.protocol -eq 2 -and
        $published.interface_version -is [string] -and
        $published.interface_version -ceq $Registry.interface_version -and $published.contract_profiles -is [array] -and
        $published.contract_profiles.Count -le 24){
      $match=Find-PaCefProfile $published.contract_profiles $map $repacked $Registry.interface_version
      if($match){$result.profile_source='official';$result.profile_lookup='matched'}
      else{$result.profile_lookup='no_match'}
     }else{$result.profile_lookup='invalid'}
    }catch{$result.profile_lookup='unavailable'}
   }else{$result.profile_lookup='disabled'}
   if(-not $match){
    $result.state='INCOMPATIBLE';$result.reason='functional_profile_mismatch';return $result
   }
   $result.fingerprint=$match.fingerprint;$result.reason=$match.reason
  }
  $result.capabilities=@{dom=$true;outgoing=$true;incoming=$true;payloads=$true;lifecycle=$true;focus=$true;ipc=$true;adapter_order=$true}
  $result.state='CONTRACT_COMPATIBLE';$result.allowed=$true;$result.mode='cef-provisional'
 }catch{
  $cause=$_.Exception.GetBaseException()
  if($cause -is [System.Management.Automation.ItemNotFoundException] -or $cause -is [IO.FileNotFoundException] -or $cause -is [IO.DirectoryNotFoundException]){
   $result.reason='files_unavailable'
  }elseif($cause -is [Text.DecoderFallbackException]){
   $result.state='INCOMPATIBLE';$result.reason='html_encoding'
  }elseif($cause.Message -match '^(js_|decoder_|missing_function:|html_|unsafe_path$|file_size$)'){
   $result.state='INCOMPATIBLE';$result.reason=$cause.Message
  }elseif($cause.Message -cin @('analysis_limit','file_changed')){
   $result.reason=$cause.Message
  }else{$result.reason='files_or_analysis_unavailable'}
 }
 return $result
}
