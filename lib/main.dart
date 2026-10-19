import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'long_video.dart';

const sbUrl='https://vihbsfrwnslnmheowkhy.supabase.co';
const sbKey='sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';
const uuid=Uuid();
void main()=>runApp(const DevoraApp());

class DevoraApp extends StatefulWidget { const DevoraApp({super.key}); @override State<DevoraApp> createState()=>_AppState(); }
class _AppState extends State<DevoraApp>{
 String? token,email; bool loading=false;
 @override void initState(){super.initState(); restore();}
 Future<void> restore() async {
  // Never keep the whole app on a spinner while local storage initializes.
  Timer(const Duration(seconds: 5), () { if (mounted && loading) setState(() { loading=false; }); });
  try {
   final p=await SharedPreferences.getInstance().timeout(const Duration(seconds: 4));
   if(!mounted)return;
   setState(() { token=p.getString('access_token'); email=p.getString('email'); loading=false; });
  } catch (_) {
   if(!mounted)return;
   setState(() { token=null; email=null; loading=false; });
  }
 }
 Future<void> login(String t,String e)async{final p=await SharedPreferences.getInstance();await p.setString('access_token',t);await p.setString('email',e);setState((){token=t;email=e;});}
 Future<void> logout()async{final p=await SharedPreferences.getInstance();await p.remove('access_token');await p.remove('email');setState(()=>token=null);}
 @override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'Devora AI',theme:ThemeData(useMaterial3:true,brightness:Brightness.dark,scaffoldBackgroundColor:const Color(0xFF060A14),colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF558AFF),brightness:Brightness.dark)),home:token==null?AuthPage(onLogin:login):MainPage(token:token!,email:email??'',onLogout:logout));
}

class Api{
 static Map<String,String> headers(String t)=>{'Content-Type':'application/json','apikey':sbKey,'Authorization':'Bearer '+t};
 static Future<Map<String,dynamic>> auth(String action,String email,String password)async{
  final url=action=='signup'?sbUrl+'/auth/v1/signup':sbUrl+'/auth/v1/token?grant_type=password';
  final r=await http.post(Uri.parse(url),headers:{'Content-Type':'application/json','apikey':sbKey},body:jsonEncode({'email':email,'password':password})).timeout(const Duration(seconds:30));
  final d=jsonDecode(r.body);if(r.statusCode<200||r.statusCode>=300)throw Exception(d['msg']??d['message']??d['error_description']??'Authentication failed');
  if(d['access_token']==null)throw Exception('Account created. Confirm your email, then sign in.');
  return Map<String,dynamic>.from(d);
 }
 static Future<String> currentUserId(String t) async {
  final r=await http.get(Uri.parse(sbUrl+'/auth/v1/user'),headers:headers(t)).timeout(const Duration(seconds:30));
  if(r.statusCode<200||r.statusCode>=300)throw Exception('Your session expired. Sign in again.');
  final d=jsonDecode(r.body);
  final id=(d is Map?d['id']:'')?.toString()??'';
  if(id.isEmpty)throw Exception('Could not verify your account.');
  return id;
 }
 static Future<String> addGeneration(String t,{required String type,required String prompt,required String model,required String taskId}) async {
  final userId=await currentUserId(t);
  final r=await http.post(Uri.parse(sbUrl+'/rest/v1/ai_generations?select=id'),
   headers:{...headers(t),'Prefer':'return=representation'},
   body:jsonEncode({'user_id':userId,'type':type,'prompt':prompt,'model':model,'task_id':taskId,'status':'processing','result_urls':[]})
  ).timeout(const Duration(seconds:30));
  if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not save generation history: '+r.body);
  final d=jsonDecode(r.body);
  if(d is! List||d.isEmpty||d.first['id']==null)throw Exception('Supabase did not return a history ID.');
  return d.first['id'].toString();
 }
 static Future<void> updateGeneration(String t,String id,{required String status,String? url}) async {
  final values=<String,dynamic>{'status':status};
  if(url!=null&&url.isNotEmpty)values['result_urls']=[url];
  if(status=='completed'||status=='failed')values['completed_at']=DateTime.now().toUtc().toIso8601String();
  final r=await http.patch(Uri.parse(sbUrl+'/rest/v1/ai_generations?id=eq.'+Uri.encodeQueryComponent(id)),
   headers:{...headers(t),'Prefer':'return=minimal'},body:jsonEncode(values)
  ).timeout(const Duration(seconds:30));
  if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not update generation history: '+r.body);
 }
 static Future<List<Map<String,dynamic>>> loadGenerations(String t) async {
  final uri=Uri.parse(sbUrl+'/rest/v1/ai_generations?select=id,type,prompt,model,task_id,status,result_urls,created_at,completed_at&order=created_at.desc&limit=100');
  final r=await http.get(uri,headers:headers(t)).timeout(const Duration(seconds:30));
  if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not load history: '+r.body);
  final d=jsonDecode(r.body);
  if(d is! List)return [];
  return d.map((e)=>Map<String,dynamic>.from(e as Map)).toList();
 }
 static Future<List<Map<String,dynamic>>> loadChatThreads(String t) async {final r=await http.get(Uri.parse(sbUrl+'/rest/v1/devora_chat_threads?select=id,title,created_at,updated_at&order=updated_at.desc&limit=100'),headers:headers(t)).timeout(const Duration(seconds:30));if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not load chat history: '+r.body);final d=jsonDecode(r.body);if(d is! List)return [];return d.map((e)=>Map<String,dynamic>.from(e as Map)).toList();}
 static Future<String> createChatThread(String t,String title) async {final userId=await currentUserId(t);final safe=title.substring(0,title.length>70?70:title.length);final r=await http.post(Uri.parse(sbUrl+'/rest/v1/devora_chat_threads?select=id'),headers:{...headers(t),'Prefer':'return=representation'},body:jsonEncode({'user_id':userId,'title':safe.isEmpty?'New chat':safe})).timeout(const Duration(seconds:30));if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not create chat: '+r.body);final d=jsonDecode(r.body);if(d is! List||d.isEmpty)throw Exception('Supabase did not return a chat ID.');return d.first['id'].toString();}
 static Future<void> saveChatMessage(String t,String id,String role,String content) async {final userId=await currentUserId(t);final r=await http.post(Uri.parse(sbUrl+'/rest/v1/devora_chat_messages'),headers:{...headers(t),'Prefer':'return=minimal'},body:jsonEncode({'thread_id':id,'user_id':userId,'role':role,'content':content})).timeout(const Duration(seconds:30));if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not save chat message: '+r.body);await http.patch(Uri.parse(sbUrl+'/rest/v1/devora_chat_threads?id=eq.'+Uri.encodeQueryComponent(id)),headers:{...headers(t),'Prefer':'return=minimal'},body:jsonEncode({'updated_at':DateTime.now().toUtc().toIso8601String()})).timeout(const Duration(seconds:30));}
 static Future<List<Map<String,dynamic>>> loadChatMessages(String t,String id) async {final r=await http.get(Uri.parse(sbUrl+'/rest/v1/devora_chat_messages?select=id,role,content,created_at&thread_id=eq.'+Uri.encodeQueryComponent(id)+'&order=created_at.asc&limit=500'),headers:headers(t)).timeout(const Duration(seconds:30));if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not open chat: '+r.body);final d=jsonDecode(r.body);if(d is! List)return [];return d.map((e)=>Map<String,dynamic>.from(e as Map)).toList();}
 static Future<void> renameChatThread(String t,String id,String title) async {final safe=title.substring(0,title.length>70?70:title.length);final r=await http.patch(Uri.parse(sbUrl+'/rest/v1/devora_chat_threads?id=eq.'+Uri.encodeQueryComponent(id)),headers:{...headers(t),'Prefer':'return=minimal'},body:jsonEncode({'title':safe,'updated_at':DateTime.now().toUtc().toIso8601String()})).timeout(const Duration(seconds:30));if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not update chat title: '+r.body);}
 static Future<void> deleteChatThread(String t,String id) async {final r=await http.delete(Uri.parse(sbUrl+'/rest/v1/devora_chat_threads?id=eq.'+Uri.encodeQueryComponent(id)),headers:headers(t)).timeout(const Duration(seconds:30));if(r.statusCode<200||r.statusCode>=300)throw Exception('Could not delete chat: '+r.body);}
 static Future<String> uploadVoiceReference(String t,Uint8List bytes,String filename,String mime)async{
  if(bytes.isEmpty)throw Exception('The voice recording is empty.');
  if(bytes.length>25*1024*1024)throw Exception('Please choose an audio file smaller than 25 MB.');
  final userResponse=await http.get(Uri.parse(sbUrl+'/auth/v1/user'),headers:{'apikey':sbKey,'Authorization':'Bearer '+t}).timeout(const Duration(seconds:30));
  if(userResponse.statusCode<200||userResponse.statusCode>=300)throw Exception('Your session expired. Sign in again.');
  final user=jsonDecode(userResponse.body);
  final userId=(user['id']??'').toString();
  if(userId.isEmpty)throw Exception('Could not verify your account.');
  final safeName=DateTime.now().millisecondsSinceEpoch.toString()+'-'+filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
  final path=userId+'/'+safeName;
  final upload=await http.post(Uri.parse(sbUrl+'/storage/v1/object/devora-voice-inputs/'+path),headers:{'apikey':sbKey,'Authorization':'Bearer '+t,'Content-Type':mime,'x-upsert':'false'},body:bytes).timeout(const Duration(seconds:90));
  if(upload.statusCode<200||upload.statusCode>=300)throw Exception('Could not upload voice audio: '+upload.body);
  final signed=await http.post(Uri.parse(sbUrl+'/storage/v1/object/sign/devora-voice-inputs/'+path),headers:{'apikey':sbKey,'Authorization':'Bearer '+t,'Content-Type':'application/json'},body:jsonEncode({'expiresIn':3600})).timeout(const Duration(seconds:30));
  if(signed.statusCode<200||signed.statusCode>=300)throw Exception('Could not create a temporary audio link.');
  final data=jsonDecode(signed.body);
  final signedPath=(data['signedURL']??data['signedUrl']??'').toString();
  if(signedPath.isEmpty)throw Exception('Supabase did not return a signed audio link.');
  if(signedPath.startsWith('http'))return signedPath;
  if(signedPath.startsWith('/storage/v1/'))return sbUrl+signedPath;
  return sbUrl+'/storage/v1'+(signedPath.startsWith('/')?signedPath:'/'+signedPath);
 }
 static Future<Map<String,dynamic>> call(String fn,String t,Map<String,dynamic> body)async{
  final r=await http.post(Uri.parse(sbUrl+'/functions/v1/'+fn),headers:headers(t),body:jsonEncode(body)).timeout(const Duration(seconds:90));
  dynamic d;try{d=jsonDecode(r.body);}catch(_){d={'error':r.body};}
  if(r.statusCode<200||r.statusCode>=300||d is! Map||(d['error']!=null&&d['success']!=true))throw Exception(d is Map?(d['error']??d['message']??'Request failed'): 'Request failed');
  return Map<String,dynamic>.from(d);
 }
 // destiny-ai streams Groq/OpenAI responses as server-sent events. Collect
 // the text deltas here so the Flutter chat can display the final answer.
 static Future<Map<String,dynamic>> chat(String t,Map<String,dynamic> body)async{
  final r=await http.post(Uri.parse(sbUrl+'/functions/v1/destiny-ai'),headers:headers(t),body:jsonEncode(body)).timeout(const Duration(seconds:120));
  if(r.statusCode<200||r.statusCode>=300){
   dynamic err;try{err=jsonDecode(r.body);}catch(_){err={'error':r.body};}
   throw Exception(err is Map?(err['error']??err['message']??'Chat request failed'): 'Chat request failed');
  }
  final contentType=(r.headers['content-type']??'').toLowerCase();
  if(!contentType.contains('text/event-stream')){
   dynamic d;try{d=jsonDecode(r.body);}catch(_){d={'error':r.body};}
   if(d is Map&&(d['error']!=null))throw Exception(d['error'].toString());
   return d is Map?Map<String,dynamic>.from(d):{'reply':r.body};
  }
  final answer=StringBuffer();
  String? provider,selectedModel;
  for(final line in r.body.split(RegExp(r'\\r?\\n'))){
   if(!line.startsWith('data:'))continue;
   final raw=line.substring(5).trim();
   if(raw.isEmpty||raw=='[DONE]')continue;
   try{
    final event=jsonDecode(raw);
    if(event is! Map)continue;
    if(event['type']=='delta'&&event['text'] is String)answer.write(event['text']);
    if(event['type']=='start'){provider=event['provider']?.toString();selectedModel=event['model']?.toString();}
    if(event['type']=='error')throw Exception(event['error']??'AI stream failed');
   }catch(e){
    if(e is Exception&&e.toString().startsWith('Exception:'))rethrow;
   }
  }
  final reply=answer.toString().trim();
  if(reply.isEmpty)throw Exception('Groq returned an empty response. Check GROQ_API_KEY in Supabase Function Secrets and try again.');
  return {'reply':reply,'provider':provider??'groq','model':selectedModel};
 }
}
class AuthPage extends StatefulWidget{final Future<void> Function(String,String) onLogin;const AuthPage({super.key,required this.onLogin});@override State<AuthPage> createState()=>_AuthState();}
class _AuthState extends State<AuthPage>{
 final e=TextEditingController(),p=TextEditingController();bool signup=false,busy=false;String err='';
 Future<void> go()async{setState(()=>{busy=true,err=''});try{final d=await Api.auth(signup?'signup':'signin',e.text.trim(),p.text);await widget.onLogin(d['access_token'],(d['user']?['email']??e.text).toString());}catch(x){setState(()=>err=x.toString().replaceFirst('Exception: ',''));}if(mounted)setState(()=>busy=false);}
 @override Widget build(BuildContext c)=>Scaffold(body:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF07383A),Color(0xFF060A14),Color(0xFF040B0C)])),child:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:430),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Icon(Icons.auto_awesome,size:66,color:Color(0xFF55DCCB)),const SizedBox(height:16),const Text('Devora AI',textAlign:TextAlign.center,style:TextStyle(fontSize:32,fontWeight:FontWeight.w900)),const SizedBox(height:8),const Text('Your personal AI studio',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60)),const SizedBox(height:28),Glass(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[TextField(controller:e,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.mail_outline),border:InputBorder.none)),const Divider(color:Colors.white12),TextField(controller:p,obscureText:true,decoration:const InputDecoration(labelText:'Password',prefixIcon:Icon(Icons.lock_outline),border:InputBorder.none))]))),if(err.isNotEmpty)Padding(padding:const EdgeInsets.all(10),child:Text(err,style:const TextStyle(color:Colors.redAccent))),const SizedBox(height:12),FilledButton(onPressed:busy?null:go,style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52)),child:busy?const CircularProgressIndicator():Text(signup?'Create account':'Sign in')),TextButton(onPressed:()=>setState(()=>{signup=!signup,err=''}),child:Text(signup?'Already registered? Sign in':'Create a new account')),const SizedBox(height:18),const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.verified_user_outlined,size:15,color:Color(0xFF55DCCB)),SizedBox(width:6),Text('Secure authentication powered by Supabase',style:TextStyle(color:Colors.white54,fontSize:11))])])))))));
}
class MainPage extends StatefulWidget{final String token,email;final Future<void> Function() onLogout;const MainPage({super.key,required this.token,required this.email,required this.onLogout});@override State<MainPage> createState()=>_MainState();}
class _MainState extends State<MainPage>{int tab=0;num? wallet;final historyKey=GlobalKey<_HistoryPageState>();@override void initState(){super.initState();refresh();}
 Future<void> refresh()async{try{final d=await Api.call('devora-media',widget.token,{'action':'wallet'});if(mounted)setState(()=>wallet=d['balance']);}catch(_){}}
 @override
 Widget build(BuildContext c) => Scaffold(
   appBar: AppBar(
     title: const Row(children: [
       DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[Color(0xFF53E0D0),Color(0xFF147D86)]),borderRadius:BorderRadius.all(Radius.circular(12))),child:SizedBox(width:38,height:38,child:Icon(Icons.auto_awesome_rounded,color:Color(0xFF07101F),size:22))),
       SizedBox(width:11),
       Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
         Text('Devora AI',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18,letterSpacing:-.4)),
         Text('YOUR CREATIVE STUDIO',style:TextStyle(fontSize:9,letterSpacing:1.5,color:Colors.white54,fontWeight:FontWeight.w600)),
       ]),
     ]),
     actions: [
       if(wallet!=null) Padding(padding:const EdgeInsets.only(right:12),child:Center(child:Container(padding:const EdgeInsets.symmetric(horizontal:11,vertical:8),decoration:BoxDecoration(color:const Color(0xFF092C2D),borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFF1C7776))),child:Row(children:[const Icon(Icons.bolt_rounded,size:15,color:Color(0xFF68E7D5)),const SizedBox(width:4),Text(wallet.toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12)),const SizedBox(width:3),const Text('CR',style:TextStyle(fontSize:10,color:Colors.white60))])))),
     ],
   ),
   body: DecoratedBox(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF061719),Color(0xFF030607),Color(0xFF030607)])),child:IndexedStack(index:tab,children:[
     ChatPage(token:widget.token),
     MediaPage(token:widget.token,refresh:refresh),
     HistoryPage(key:historyKey,token:widget.token),
     CreditsPage(token:widget.token,onPaid:refresh),
     AccountPage(email:widget.email,wallet:wallet,refresh:refresh,logout:widget.onLogout),
   ])),
   bottomNavigationBar:NavigationBar(height:68,selectedIndex:tab,onDestinationSelected:(v){setState(()=>tab=v);if(v==2)historyKey.currentState?.loadHistory();},destinations:const[
     NavigationDestination(icon:Icon(Icons.chat_bubble_outline_rounded),selectedIcon:Icon(Icons.chat_rounded),label:'Chat'),
     NavigationDestination(icon:Icon(Icons.auto_awesome_mosaic_outlined),selectedIcon:Icon(Icons.auto_awesome),label:'Create'),
     NavigationDestination(icon:Icon(Icons.history_rounded),selectedIcon:Icon(Icons.history_toggle_off_rounded),label:'History'),
     NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),selectedIcon:Icon(Icons.account_balance_wallet_rounded),label:'Credits'),
     NavigationDestination(icon:Icon(Icons.person_outline_rounded),selectedIcon:Icon(Icons.person_rounded),label:'Account'),
   ]),
 );
}
class ChatPage extends StatefulWidget{final String token;const ChatPage({super.key,required this.token});@override State<ChatPage> createState()=>_ChatState();}
class _ChatState extends State<ChatPage>{
 final input=TextEditingController();final scroll=ScrollController();
 final msgs=<Map<String,String>>[{'role':'assistant','content':'Hi! I am Devora AI. Ask a question or use Create to generate media.'}];
 bool busy=false;String mode='Chat';String? threadId;List<Map<String,dynamic>> threads=[];
 @override void initState(){super.initState();loadThreads();}
 @override void dispose(){input.dispose();scroll.dispose();super.dispose();}
 void snack(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
 Future<void> loadThreads()async{try{final rows=await Api.loadChatThreads(widget.token);if(mounted)setState(()=>threads=rows);}catch(e){snack('Could not load chat history. Check Supabase permissions.');}}
 Future<void> newChat()async{if(busy)return;setState(()=>{threadId=null,msgs..clear()..add({'role':'assistant','content':'Hi! I am Devora AI. Ask a question or use Create to generate media.'})});}
 Future<void> openThread(Map<String,dynamic> th)async{Navigator.of(context).pop();try{final rows=await Api.loadChatMessages(widget.token,th['id'].toString());if(!mounted)return;setState(()=>{threadId=th['id'].toString(),msgs..clear()..addAll(rows.map((r)=>{'role':r['role'].toString(),'content':r['content'].toString()}))});if(msgs.isEmpty)setState(()=>msgs.add({'role':'assistant','content':'This chat is empty. Send a message to continue.'}));scrollBottom();}catch(e){snack(e.toString().replaceFirst('Exception: ',''));}}
 Future<void> showHistory()async{await loadThreads();if(!mounted)return;showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:const Color(0xFF071719),shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(24))),builder:(sc)=>SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:SizedBox(height:MediaQuery.of(sc).size.height*.68,child:Column(children:[
 Row(children:[const Expanded(child:Text('Chat history',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),IconButton(onPressed:()=>Navigator.pop(sc),icon:const Icon(Icons.close))]),
 SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:(){Navigator.pop(sc);newChat();},icon:const Icon(Icons.add),label:const Text('New chat'))),const SizedBox(height:8),
 Expanded(child:threads.isEmpty?const Center(child:Text('Your saved conversations will appear here.',style:TextStyle(color:Colors.white60))):ListView.separated(itemCount:threads.length,separatorBuilder:(_,__)=>const Divider(color:Colors.white10),itemBuilder:(ctx,i){final th=threads[i];return ListTile(leading:const Icon(Icons.chat_bubble_outline,color:Color(0xFF55DCCB)),title:Text((th['title']??'New chat').toString(),maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text((th['updated_at']??'').toString().replaceFirst('T',' ').split('.').first,style:const TextStyle(fontSize:11,color:Colors.white54)),onTap:()=>openThread(th),trailing:IconButton(icon:const Icon(Icons.delete_outline,color:Colors.white54),tooltip:'Delete chat',onPressed:()async{final ok=await showDialog<bool>(context:sc,builder:(dc)=>AlertDialog(title:const Text('Delete chat?'),content:const Text('This conversation and its messages will be deleted.'),actions:[TextButton(onPressed:()=>Navigator.pop(dc,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dc,true),child:const Text('Delete'))]));if(ok==true){try{await Api.deleteChatThread(widget.token,th['id'].toString());if(threadId==th['id'].toString())await newChat();await loadThreads();}catch(e){snack(e.toString());}}}));}))
 ])))));}
 void scrollBottom(){WidgetsBinding.instance.addPostFrameCallback((_){if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:220),curve:Curves.easeOut);});}
 Future<void> send()async{final q=input.text.trim();if(q.isEmpty||busy)return;input.clear();setState(()=>{msgs.add({'role':'user','content':q}),busy=true});scrollBottom();try{if(threadId==null)threadId=await Api.createChatThread(widget.token,q);await Api.saveChatMessage(widget.token,threadId!,'user',q);final d=await Api.chat(widget.token,{'message':q,'prompt':q,'mode':mode,'messages':msgs});final a=(d['reply']??d['response']??d['message']??d['content']??'No response returned.').toString();if(mounted)setState(()=>msgs.add({'role':'assistant','content':a}));await Api.saveChatMessage(widget.token,threadId!,'assistant',a);await Api.renameChatThread(widget.token,threadId!,q);await loadThreads();}catch(x){if(mounted)setState(()=>msgs.add({'role':'assistant','content':'Chat error: '+x.toString().replaceFirst('Exception: ','' )}));}if(mounted){setState(()=>busy=false);scrollBottom();}}
 @override Widget build(BuildContext c)=>Column(children:[
 Padding(padding:const EdgeInsets.fromLTRB(12,8,8,8),child:Row(children:[const Icon(Icons.auto_awesome_rounded,color:Color(0xFF55DCCB),size:18),const SizedBox(width:8),const Expanded(child:Text('AI ASSISTANT',style:TextStyle(color:Colors.white70,letterSpacing:1.4,fontWeight:FontWeight.w800,fontSize:11))),IconButton(tooltip:'Chat history',onPressed:showHistory,icon:const Icon(Icons.history_rounded)),IconButton(tooltip:'New chat',onPressed:newChat,icon:const Icon(Icons.add_comment_outlined)),DropdownButton<String>(value:mode,items:['Chat','Code','Study','Write','Creative'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>mode=v!))])),
 Expanded(child:ListView.builder(controller:scroll,padding:const EdgeInsets.all(14),itemCount:msgs.length+(busy?1:0),itemBuilder:(c,i){if(i>=msgs.length)return const Padding(padding:EdgeInsets.all(12),child:Text('Devora is thinking…',style:TextStyle(color:Colors.white54)));final m=msgs[i];final user=m['role']=='user';return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:Container(constraints:const BoxConstraints(maxWidth:340),margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:user?const Color(0xFF0A4A4B):const Color(0xFF09191B),borderRadius:BorderRadius.circular(18),border:Border.all(color:Colors.white10)),child:Text(m['content']??'',style:const TextStyle(height:1.45))));})),
 SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(12),child:Glass(child:Row(children:[Expanded(child:TextField(controller:input,minLines:1,maxLines:4,onSubmitted:(_)=>send(),decoration:const InputDecoration(hintText:'Message Devora AI…',border:InputBorder.none,contentPadding:EdgeInsets.all(12)))),IconButton(onPressed:busy?null:send,icon:const Icon(Icons.arrow_upward),style:IconButton.styleFrom(backgroundColor:const Color(0xFF139E9B)))]))))
 ]);}
class MediaPage extends StatefulWidget{final String token;final Future<void> Function() refresh;const MediaPage({super.key,required this.token,required this.refresh});@override State<MediaPage> createState()=>_MediaState();}
class _MediaState extends State<MediaPage> with WidgetsBindingObserver{
 final Set<String> activePolls=<String>{};
 bool resumingPending=false;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);WidgetsBinding.instance.addPostFrameCallback((_)=>resumePendingGenerations());}
 @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)resumePendingGenerations();}
 Future<void> resumePendingGenerations()async{
  if(resumingPending)return;resumingPending=true;
  try{final rows=await Api.loadGenerations(widget.token);for(final row in rows){if((row['status']??'').toString().toLowerCase()!='processing')continue;final task=(row['task_id']??'').toString();final id=(row['id']??'').toString();if(task.isEmpty||id.isEmpty||activePolls.contains(task))continue;unawaited(poll(task,historyId:id,resumed:true));}}
  catch(_){}
  finally{resumingPending=false;}
 }

 String? currentHistoryId; final prompt=TextEditingController(),musicStyle=TextEditingController(text:'Afrobeats, melodic, polished studio production');String type='image',model='gpt-image-2-text-to-image',resolution='720p',ratio='auto',status='',result='',voiceMode='AI voice',voiceFileName='',voiceMime='audio/mp4',visualStyle='Photorealistic';Uint8List? voiceBytes;final AudioRecorder recorder=AudioRecorder();int duration=10;String voiceGender='m';bool busy=false,downloading=false,recording=false; VideoPlayerController? videoController; final AudioPlayer audioPlayer=AudioPlayer(); bool mediaPlaying=false,previewLoading=false;
 final models={'image':['gpt-image-2-text-to-image','nano-banana-2-1','nano-banana-2','nano-banana-pro','grok-imagine-image-2-0/text-to-image','bytedance/seedream-v4-text-to-image','flux-2/pro-text-to-image','flux-2/flex-text-to-image','qwen2-1/text-to-image'],'video':['bytedance/seedance-2-5','veo-3-1','kling-3.0/video','grok-imagine-video-1-5-preview'],'music':['V6','V6_MINI','V6_WILD']};
 final visualStyles=['Photorealistic','Cinematic','Anime','3D render','Cartoon','Cyberpunk','Fantasy','Watercolor','Oil painting','Digital art','Comic book','Pixel art','Vintage film','Minimalist','Luxury editorial','Surreal','Ghibli-inspired','Claymation','Fashion editorial','Product photography','Architecture','Documentary','Neon noir','Dreamlike','Low-poly','Isometric','Pencil sketch','Charcoal drawing','Pop art','Retro futurism'];
 final musicStyles=['Afrobeats','Afro-fusion','Afropop','Amapiano','Hip-hop','Trap','R&B','Soul','Gospel','Pop','Dancehall','Reggae','House','EDM','Drill','Jazz','Blues','Rock','Acoustic','Orchestral','Cinematic soundtrack','Lo-fi','Highlife','Fuji','Amapiano-Afrobeats fusion','Synthwave','Funk','Country','Indie pop','Ambient'];
 final aspectRatios=['auto','1:1','16:9','9:16','4:3','3:4','3:2','2:3','21:9'];
 int get cost=>type=='image'?({'gpt-image-2-text-to-image':6,'nano-banana-2-1':12,'nano-banana-2':8,'nano-banana-pro':24,'grok-imagine-image-2-0/text-to-image':10,'bytedance/seedream-v4-text-to-image':8,'flux-2/pro-text-to-image':10,'qwen2-1/text-to-image':6}[model]??8):type=='video'?({'bytedance/seedance-2-5':170,'veo-3-1':255,'kling-3.0/video':70,'grok-imagine-video-1-5-preview':20}[model]??70):(model=='V6_MINI'?10:12);
 Future<void> generate()async{currentHistoryId=null;if(prompt.text.trim().isEmpty){setState(()=>status='Enter a song idea or lyrics first.');return;}if(type=='music'&&voiceMode!='AI voice'&&voiceBytes==null){setState(()=>status='Record or upload an audio sample first.');return;}setState(()=>{busy=true,status='Starting generation…',result=''});try{String? audioUrl;if(type=='music'&&voiceMode!='AI voice'){status='Uploading your voice reference securely…';audioUrl=await Api.uploadVoiceReference(widget.token,voiceBytes!,voiceFileName.isEmpty?'voice.m4a':voiceFileName,voiceMime);}final generationPrompt=type=='music'?prompt.text.trim():'${prompt.text.trim()}, style: $visualStyle';final body=<String,dynamic>{'type':type,'model':model,'prompt':generationPrompt,'requestId':uuid.v4(),'resolution':resolution,'aspectRatio':ratio,'duration':duration,'style':type=='music'?musicStyle.text.trim():visualStyle};if(type=='music'){body['voiceMode']=voiceMode;body['vocalGender']=voiceGender;}if(audioUrl!=null)body['audioUrl']=audioUrl;final d=await Api.call('devora-media',widget.token,body);final task=(d['taskId']??'').toString();setState(()=>status='Queued task '+task);if(task.isNotEmpty){try{currentHistoryId=await Api.addGeneration(widget.token,type:type,prompt:generationPrompt,model:model,taskId:task);}catch(_){if(mounted)setState(()=>status='Generation started; history could not be saved. Check Supabase history permissions.');}await poll(task,historyId:currentHistoryId);}}catch(x){if(mounted)setState(()=>status=x.toString().replaceFirst('Exception: ',''));}if(mounted){setState(()=>busy=false);await widget.refresh();}}
 @override void dispose(){WidgetsBinding.instance.removeObserver(this);videoController?.dispose();audioPlayer.dispose();prompt.dispose();musicStyle.dispose();recorder.dispose();super.dispose();}
 Future<void> chooseVoiceFile() async {
  try {
    final pick = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) bytes = await File(file.path!).readAsBytes();
    if (bytes == null || bytes.isEmpty) throw Exception('Could not read the selected audio file.');
    if (bytes.length > 25 * 1024 * 1024) throw Exception('Please choose an audio file smaller than 25 MB.');
    final ext = (file.extension ?? 'm4a').toLowerCase();
    final mime = ext == 'mp3' ? 'audio/mpeg' : ext == 'wav' ? 'audio/wav' : ext == 'ogg' ? 'audio/ogg' : ext == 'aac' ? 'audio/aac' : 'audio/mp4';
    setState(() {
      voiceBytes = bytes;
      voiceFileName = file.name;
      voiceMime = mime;
      voiceMode = 'Upload voice';
      status = 'Voice sample selected: ' + file.name;
    });
  } catch (e) {
    if (mounted) setState(() { status = 'Could not select audio: ' + e.toString().replaceFirst('Exception: ', ''); });
  }
 }
 Future<void> toggleRecording() async {
  try {
    if (recording) {
      final path = await recorder.stop();
      if (path == null) throw Exception('Recording did not produce an audio file.');
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) throw Exception('The recording is empty.');
      if (bytes.length > 25 * 1024 * 1024) throw Exception('Recording is over 25 MB. Please record a shorter sample.');
      setState(() {
        voiceBytes = bytes;
        voiceFileName = 'voice-recording.m4a';
        voiceMime = 'audio/mp4';
        recording = false;
        voiceMode = 'Record voice';
        status = 'Voice recording ready to use.';
      });
    } else {
      if (!await recorder.hasPermission()) throw Exception('Microphone permission is required to record your voice.');
      final dir = await getTemporaryDirectory();
      final path = dir.path + '/devora-voice-' + DateTime.now().millisecondsSinceEpoch.toString() + '.m4a';
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        recording = true;
        voiceMode = 'Record voice';
        status = 'Recording… tap Stop when finished.';
      });
    }
  } catch (e) {
    if (mounted) setState(() {
      recording = false;
      status = 'Recording error: ' + e.toString().replaceFirst('Exception: ', '');
    });
  }
 }
 Future<void> prepareMediaPreview(String url) async {
   if(type=='video') {
     final old=videoController; videoController=null; await old?.dispose();
     if(!mounted)return; setState(()=>previewLoading=true);
     try {
       final controller=VideoPlayerController.networkUrl(Uri.parse(url));
       await controller.initialize();
       if(!mounted){await controller.dispose();return;}
       setState(()=>{videoController=controller,previewLoading=false});
     } catch(_) { if(mounted)setState(()=>{previewLoading=false,status='Video preview unavailable. You can still download the MP4.'}); }
   } else if(type=='music') {
     try { await audioPlayer.stop(); await audioPlayer.setSource(UrlSource(url)); if(mounted)setState(()=>mediaPlaying=false); }
     catch(_) { if(mounted)setState(()=>status='Music preview unavailable. You can still download the audio file.'); }
   }
 }
 Future<void> toggleMediaPlayback() async {
   try {
     if(type=='video') {
       final controller=videoController;
       if(controller==null||!controller.value.isInitialized)return;
       if(controller.value.isPlaying){await controller.pause();}else{await controller.play();}
       if(mounted)setState(()=>{});
     } else if(type=='music') {
       if(mediaPlaying){await audioPlayer.pause();}else{await audioPlayer.resume();}
       if(mounted)setState(()=>mediaPlaying=!mediaPlaying);
     }
   } catch(e) { if(mounted)setState(()=>status='Playback error: '+e.toString()); }
 }
 Future<void> downloadResult() async {
   if(result.isEmpty||downloading)return;
   setState(()=>downloading=true);
   try {
     final uri=Uri.parse(result);
     final response=await http.get(uri).timeout(const Duration(seconds:120));
     if(response.statusCode<200||response.statusCode>=300)throw Exception('Download failed ('+response.statusCode.toString()+').');
     if(response.bodyBytes.isEmpty)throw Exception('The generated file is empty. Please try again.');
     final contentType=(response.headers['content-type']??'').split(';').first.trim().toLowerCase();
     final urlExt=uri.path.toLowerCase().split('.').last;
     late final String ext;
     late final MimeType mime;
     if(type=='image'){
       if(contentType=='image/jpeg'||contentType=='image/jpg'||urlExt=='jpg'||urlExt=='jpeg'){
         ext='jpg';mime=MimeType.jpeg;
       }else if(contentType=='image/webp'||urlExt=='webp'){
         ext='webp';mime=MimeType.other;
       }else if(contentType=='image/avif'||urlExt=='avif'){
         ext='avif';mime=MimeType.other;
       }else if(contentType=='image/gif'||urlExt=='gif'){
         ext='gif';mime=MimeType.gif;
       }else{
         ext='png';mime=MimeType.png;
       }
     }else if(type=='video'){
       ext='mp4';mime=MimeType.mp4Video;
     }else{
       ext='mp3';mime=MimeType.mp3;
     }
     await FileSaver.instance.saveAs(
       name:'Devora-AI-'+DateTime.now().millisecondsSinceEpoch.toString(),
       bytes:response.bodyBytes,
       ext:ext,
       mimeType:mime,
     );
     if(mounted)setState(()=>status=(type=='image'?'Image':type=='video'?'Video':'Music')+' downloaded successfully. Check your Downloads or saved files.');
   }catch(e){
     if(mounted)setState(()=>status='Could not save this file: '+e.toString().replaceFirst('Exception: ',''));
   }finally{
     if(mounted)setState(()=>downloading=false);
   }
 }
 Future<void> saveHistoryStatus(String status,{String? url,String? historyId})async{final id=historyId??currentHistoryId;if(id==null)return;try{await Api.updateGeneration(widget.token,id,status:status,url:url);}catch(_){}}
  Future<void> poll(String task,{String? historyId,bool resumed=false})async{
   if(!activePolls.add(task))return;
   try{
    // Provider jobs keep running remotely. Persisted task IDs are resumed on launch/app return.
    for(var i=0;i<2400;i++){
     await Future.delayed(const Duration(seconds:3));
     if(!mounted)return;
     try{
      final d=await Api.call('devora-media',widget.token,{'action':'status','taskId':task});
      final state=(d['state']??d['status']??'').toString().toLowerCase();
      final urls=d['urls'];String u=(d['url']??d['resultUrl']??'').toString();
      if(u.isEmpty&&urls is List&&urls.isNotEmpty)u=urls.first.toString();
      if(u.startsWith('http')){
       await saveHistoryStatus('completed',url:u,historyId:historyId);
       if(mounted&&(!resumed||currentHistoryId==historyId)){setState(()=>{result=u,status='Generation complete. Your file is ready to preview or download from History.'});currentHistoryId=historyId;await prepareMediaPreview(u);}
       await widget.refresh();return;
      }
      if(state.contains('fail')||state.contains('error')||state=='cancelled'){
       final message=(d['failMsg']??d['message']??'Generation failed').toString();
       await saveHistoryStatus('failed',historyId:historyId);
       if(mounted&&!resumed)setState(()=>status=message);
       return;
      }
      if(mounted&&!resumed)setState(()=>status='Generating… '+((i+1)*3).toString()+' seconds');
     }catch(_){if(mounted&&!resumed)setState(()=>status='Waiting for provider status…');}
    }
    if(mounted&&!resumed)setState(()=>status='Still processing on the provider. Check History again later.');
   }finally{activePolls.remove(task);}
  }
  @override
 Widget build(BuildContext c) {
   return ListView(
     padding: const EdgeInsets.all(16),
     children: [
       Glass(child:Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF0B4B50),Color(0xFF071F22),Color(0xFF061416)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         Container(width:42,height:42,decoration:BoxDecoration(color:const Color(0xFF55DCCB).withOpacity(.16),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.auto_awesome_rounded,color:Color(0xFF67E8D8),size:24)),
         const SizedBox(height:14),
         const Text('Create beyond\\nimagination',style:TextStyle(fontSize:27,height:1.08,fontWeight:FontWeight.w900,letterSpacing:-.7)),
         const SizedBox(height:8),
         const Text('Turn your ideas into stunning AI images, videos and music.',style:TextStyle(color:Colors.white70,height:1.4)),
       ]))),
       const SizedBox(height:18),
       Wrap(
         spacing: 8,
         children: ['image', 'video', 'music'].map((t) => ChoiceChip(
           label: Text(t.toUpperCase()),
           selected: type == t,
           onSelected: busy ? null : (_) => setState(() {
             type = t;
             model = models[t]!.first;
             status = '';
             result = '';
           }),
         )).toList(),
       ),
       if (type == 'video') ...[
         const SizedBox(height: 10),
         SizedBox(width: double.infinity, child: OutlinedButton.icon(
           onPressed: busy ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LongVideoPage(token: widget.token))),
           icon: const Icon(Icons.movie_creation_outlined),
           label: const Text('Create a video up to 1 hour — automatic scenes'),
           style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
         )),
       ],
       const SizedBox(height: 12),
       Glass(child: Padding(
         padding: const EdgeInsets.all(14),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(type=='music'?'SONG IDEA OR LYRICS':'PROMPT', style: const TextStyle(color: Colors.white54, letterSpacing: 1.5)),
             TextField(controller: prompt, minLines: 4, maxLines: 7, decoration: InputDecoration(hintText: type=='music'?'Describe your song or enter lyrics…':'Describe your creation…', border: InputBorder.none)),
             const Divider(color: Colors.white12),
             if(type!='music') ...[
               const Text('VISUAL STYLE',style:TextStyle(color:Colors.white54,letterSpacing:1.5)),
               DropdownButtonFormField<String>(value:visualStyle,isExpanded:true,decoration:const InputDecoration(border:InputBorder.none),items:visualStyles.map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:(v)=>setState(()=>visualStyle=v??'Photorealistic')),
               const SizedBox(height:8),
             ],
             const Text('MODEL', style: TextStyle(color: Colors.white54, letterSpacing: 1.5)),
             DropdownButtonFormField<String>(
               value: model,
               isExpanded: true,
               decoration: const InputDecoration(border: InputBorder.none),
               items: models[type]!.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
               onChanged: busy ? null : (v) => setState(() => model = v!),
             ),
                   if(type=='music') ...[
               const SizedBox(height:8),
               const Text('VOICE SOURCE',style:TextStyle(color:Colors.white54,letterSpacing:1.5)),
               Wrap(spacing:8,runSpacing:8,children:['AI voice','Record voice','Upload voice'].map((v)=>ChoiceChip(label:Text(v),selected:voiceMode==v,onSelected:busy?null:(_){setState(() { voiceMode=v; if(v=='AI voice'){voiceBytes=null;voiceFileName='';} status=''; });if(v=='Upload voice')chooseVoiceFile();})).toList()),
               if(voiceMode=='AI voice') ...[
                 const SizedBox(height:8),
                 DropdownButtonFormField<String>(value:voiceGender,decoration:const InputDecoration(labelText:'AI singing voice'),items:const [DropdownMenuItem(value:'m',child:Text('Male vocals')),DropdownMenuItem(value:'f',child:Text('Female vocals'))],onChanged:busy?null:(v)=>setState(()=>voiceGender=v??'m')),
                 const SizedBox(height:8),
                 const Text('Describe the song or enter lyrics in the prompt above.',style:TextStyle(color:Colors.white54,fontSize:12)),
               ] else ...[
                 const SizedBox(height:8),
                 Row(children:[Expanded(child:Text(voiceBytes==null?'Record a short voice sample or choose an audio file.':voiceFileName,style:const TextStyle(color:Colors.white70,fontSize:12),maxLines:2,overflow:TextOverflow.ellipsis)),const SizedBox(width:8),if(voiceMode=='Record voice')FilledButton.tonalIcon(onPressed:busy?null:toggleRecording,icon:Icon(recording?Icons.stop_circle_outlined:Icons.mic_none_rounded),label:Text(recording?'Stop':'Record'))else OutlinedButton.icon(onPressed:busy?null:chooseVoiceFile,icon:const Icon(Icons.upload_file_rounded),label:const Text('Choose audio'))]),
                 const SizedBox(height:5),
                 const Text('Your audio is uploaded privately to Supabase and sent to the music model as a reference. It may influence the result but does not guarantee an exact voice clone.',style:TextStyle(color:Colors.white54,fontSize:11)),
               ],
               const SizedBox(height:10),
               const Text('MUSIC STYLE / GENRE',style:TextStyle(color:Colors.white54,letterSpacing:1.5)),
               DropdownButtonFormField<String>(value:musicStyles.contains(musicStyle.text)?musicStyle.text:null,isExpanded:true,decoration:const InputDecoration(labelText:'Choose a genre',border:InputBorder.none),items:musicStyles.map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:(v)=>setState(()=>musicStyle.text=v??'Afrobeats')),
               TextField(controller:musicStyle,minLines:1,maxLines:2,decoration:const InputDecoration(labelText:'Or enter a custom style',hintText:'Afrobeats, R&B, soulful…',border:InputBorder.none)),
               const Divider(color:Colors.white12),
             ],
       if (type != 'music') ...[
               const Text('RESOLUTION', style: TextStyle(color: Colors.white54, letterSpacing: 1.5)),
               DropdownButtonFormField<String>(
                 value: resolution,
                 decoration: const InputDecoration(border: InputBorder.none),
                 items: (type == 'image' ? ['720p', '1080p'] : ['480p', '720p', '1080p']).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                 onChanged: busy ? null : (v) => setState(() => resolution = v!),
               ),
               const Text('ASPECT RATIO', style: TextStyle(color: Colors.white54, letterSpacing: 1.5)),
               DropdownButtonFormField<String>(
                 value: ratio,
                 decoration: const InputDecoration(border: InputBorder.none),
                 items: aspectRatios.map((v) => DropdownMenuItem(value: v, child: Text(v=='auto'?'Auto / model default':v))).toList(),
                 onChanged: busy ? null : (v) => setState(() => ratio = v!),
               ),
             ],
             if (type == 'video')
               Row(children: [
                 const Text('Duration'),
                 Expanded(child: Slider(value: duration.toDouble(), min: 5, max: 15, divisions: 10, onChanged: busy ? null : (v) => setState(() => duration = v.round()))),
                 Text('${duration}s'),
               ]),
             const Divider(color: Colors.white12),
             Text('Estimated cost: about ${cost} credits', style: const TextStyle(fontWeight: FontWeight.bold)),
             const Text('Actual provider charges can vary.', style: TextStyle(color: Colors.white38, fontSize: 11)),
           ],
         ),
       )),
       const SizedBox(height: 14),
       FilledButton.icon(
         onPressed: busy ? null : generate,
         icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
         label: Text(busy ? 'Generating…' : 'Generate'),
         style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
       ),
       if (status.isNotEmpty)
         Padding(padding: const EdgeInsets.only(top: 14), child: Glass(child: Padding(padding: const EdgeInsets.all(14), child: Text(status)))),
       if (result.isNotEmpty)
         Padding(padding: const EdgeInsets.only(top: 14), child: Glass(child: Padding(
           padding: const EdgeInsets.all(14),
           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
             Row(children:[const Icon(Icons.check_circle_rounded,color:Color(0xFF55DCCB),size:20),const SizedBox(width:8),const Expanded(child:Text('Your creation is ready',style:TextStyle(fontWeight:FontWeight.w800,fontSize:17)))]),
             const SizedBox(height:10),
             if(type=='image')
               ClipRRect(borderRadius:BorderRadius.circular(16),child:Image.network(result,fit:BoxFit.contain,width:double.infinity,loadingBuilder:(c,w,p)=>p==null?w:Container(height:210,alignment:Alignment.center,child:const CircularProgressIndicator()),errorBuilder:(c,e,st)=>Container(height:160,alignment:Alignment.center,child:const Text('Image preview unavailable. Try downloading the image.'))))
             else if(type=='video')
               Container(width:double.infinity,decoration:BoxDecoration(color:const Color(0xFF092C2D),borderRadius:BorderRadius.circular(16)),clipBehavior:Clip.antiAlias,child:Column(children:[
                 if(videoController!=null&&videoController!.value.isInitialized) AspectRatio(aspectRatio:videoController!.value.aspectRatio,child:VideoPlayer(videoController!))
                 else Container(height:210,alignment:Alignment.center,child:previewLoading?const CircularProgressIndicator():const Icon(Icons.movie_creation_rounded,size:54,color:Color(0xFF55DCCB))),
                 Padding(padding:const EdgeInsets.all(10),child:Row(children:[
                   IconButton(onPressed:toggleMediaPlayback,icon:Icon(videoController?.value.isPlaying==true?Icons.pause_circle:Icons.play_circle,size:34)),
                   const Expanded(child:Text('Video preview',style:TextStyle(fontWeight:FontWeight.w700))),
                 ])),
               ]))
             else
               Container(width:double.infinity,padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFF092C2D),borderRadius:BorderRadius.circular(16),border:Border.all(color:const Color(0xFF1C7776))),child:Row(children:[
                 IconButton(onPressed:toggleMediaPlayback,icon:Icon(mediaPlaying?Icons.pause_circle:Icons.play_circle,size:42,color:const Color(0xFF55DCCB))),
                 const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('AI music generated',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16)),Text('Play your music inside Devora AI',style:TextStyle(color:Colors.white60,fontSize:12))])),
               ])),
             const SizedBox(height:12),
             SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:downloading?null:downloadResult,icon:downloading?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.download_rounded),label:Text(downloading?'Saving to your phone…':'Download original '+type.toUpperCase()))),
             const SizedBox(height:5),
             const Text('The generated media is shown here. Download saves the original file to your device.',style:TextStyle(color:Colors.white54,fontSize:11)),
           ]),
         ))),
       const SizedBox(height: 20),
       const Text('API secrets stay on Supabase, not inside this APK.', style: TextStyle(color: Colors.white38, fontSize: 11)),
     ],
   );
 }
}

class HistoryPage extends StatefulWidget {
 final String token;
 const HistoryPage({super.key,required this.token});
 @override State<HistoryPage> createState()=>_HistoryPageState();
}
class _HistoryPageState extends State<HistoryPage> {
 List<Map<String,dynamic>> items=[];
 bool loading=true;
 String error='',filter='all',downloadingId='';
 @override void initState(){super.initState();loadHistory();}
 Future<void> loadHistory() async {
  if(!mounted)return;
  setState(()=>loading=true);
  try{final rows=await Api.loadGenerations(widget.token);if(mounted)setState(()=>{items=rows,error=''});}
  catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
  finally{if(mounted)setState(()=>loading=false);}
 }
 String? mediaUrl(Map<String,dynamic> item){
  final urls=item['result_urls'];
  if(urls is List&&urls.isNotEmpty)return urls.first.toString();
  if(urls is String&&urls.isNotEmpty){try{final d=jsonDecode(urls);if(d is List&&d.isNotEmpty)return d.first.toString();}catch(_){}}
  return null;
 }
 String dateLabel(dynamic raw){try{final d=DateTime.parse(raw.toString()).toLocal();return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} • ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';}catch(_){return 'Date unavailable';}}
 Future<void> download(Map<String,dynamic> item) async {
  final url=mediaUrl(item);if(url==null||!url.startsWith('http'))return;
  final id=(item['id']??'').toString();setState(()=>downloadingId=id);
  try{
   final r=await http.get(Uri.parse(url)).timeout(const Duration(minutes:2));
   if(r.statusCode<200||r.statusCode>=300||r.bodyBytes.isEmpty)throw Exception('This media link may have expired. Generate it again to get a fresh file.');
   final type=(item['type']??'image').toString();
   final ext=type=='video'?'mp4':type=='music'?'mp3':'png';
   final mime=type=='video'?MimeType.mp4Video:type=='music'?MimeType.mp3:MimeType.png;
   await FileSaver.instance.saveAs(name:'Devora-AI-${type}-${DateTime.now().millisecondsSinceEpoch}',bytes:r.bodyBytes,ext:ext,mimeType:mime);
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Saved to your phone.')));
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
  finally{if(mounted)setState(()=>downloadingId='');}
 }
 @override Widget build(BuildContext context){
  final filtered=items.where((x)=>filter=='all'?['image','video','music'].contains(x['type']):x['type']==filter).toList();
  return RefreshIndicator(onRefresh:loadHistory,child:ListView(padding:const EdgeInsets.all(16),children:[
   Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Generation history',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900)),SizedBox(height:4),Text('Your images, videos and music saved to your Supabase account.',style:TextStyle(color:Colors.white60,fontSize:12))])),IconButton(onPressed:loading?null:loadHistory,icon:const Icon(Icons.refresh_rounded))]),
   const SizedBox(height:14),
   Wrap(spacing:8,children:['all','image','video','music'].map((v)=>ChoiceChip(label:Text(v=='all'?'ALL':v.toUpperCase()),selected:filter==v,onSelected:(_)=>setState(()=>filter=v))).toList()),
   const SizedBox(height:12),
   if(loading&&items.isEmpty)const Padding(padding:EdgeInsets.all(40),child:Center(child:CircularProgressIndicator())),
   if(error.isNotEmpty)Glass(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[Text(error,style:const TextStyle(color:Colors.redAccent)),TextButton(onPressed:loadHistory,child:const Text('Try again'))]))),
   if(!loading&&error.isEmpty&&filtered.isEmpty)Glass(child:const Padding(padding:EdgeInsets.all(28),child:Column(children:[Icon(Icons.history_rounded,size:42,color:Color(0xFF55DCCB)),SizedBox(height:10),Text('No generations yet',style:TextStyle(fontWeight:FontWeight.w800,fontSize:17)),SizedBox(height:5),Text('Your successful image, video and music creations will appear here.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60))]))),
   ...filtered.map((item){
    final type=(item['type']??'image').toString();
    final state=(item['status']??'processing').toString().toLowerCase();
    final url=mediaUrl(item);
    final prompt=(item['prompt']??'').toString();
    final id=(item['id']??'').toString();
    final icon=type=='video'?Icons.movie_creation_outlined:type=='music'?Icons.music_note_rounded:Icons.image_outlined;
    final ready=state=='completed'&&url!=null&&url.startsWith('http');
    return Padding(padding:const EdgeInsets.only(bottom:10),child:Glass(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Row(children:[Container(width:42,height:42,decoration:BoxDecoration(color:const Color(0xFF55DCCB).withOpacity(.12),borderRadius:BorderRadius.circular(12)),child:Icon(icon,color:const Color(0xFF55DCCB))),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(type.toUpperCase(),style:const TextStyle(fontWeight:FontWeight.w800,letterSpacing:1)),Text((item['model']??'AI model').toString(),style:const TextStyle(color:Colors.white54,fontSize:11))])),Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:state=='completed'?const Color(0xFF124B3F):state=='failed'?const Color(0xFF55272D):const Color(0xFF273342),borderRadius:BorderRadius.circular(20)),child:Text(state.toUpperCase(),style:const TextStyle(fontSize:9,fontWeight:FontWeight.w800)))]),
     const SizedBox(height:10),
     if(type=='image'&&ready)ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.network(url,fit:BoxFit.cover,width:double.infinity,height:190,errorBuilder:(c,e,st)=>Container(height:70,alignment:Alignment.center,child:const Text('Preview unavailable')))),
     Text(prompt, maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(height:1.35)),
     const SizedBox(height:7),
     Text(dateLabel(item['created_at']),style:const TextStyle(color:Colors.white38,fontSize:11)),
     if(ready)Padding(padding:const EdgeInsets.only(top:8),child:OutlinedButton.icon(onPressed:downloadingId==id?null:()=>download(item),icon:downloadingId==id?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.download_rounded),label:Text(downloadingId==id?'Saving…':'Download to phone'))),
    ]))));
   }),
  ]));
 }
}

class AccountPage extends StatelessWidget{final String email;final num? wallet;final Future<void> Function() refresh,logout;const AccountPage({super.key,required this.email,required this.wallet,required this.refresh,required this.logout});@override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[const Text('Account',style:TextStyle(fontSize:25,fontWeight:FontWeight.w800)),const SizedBox(height:16),Glass(child:ListTile(leading:const Icon(Icons.person_outline),title:Text(email),subtitle:const Text('Devora AI member'))),const SizedBox(height:10),Glass(child:ListTile(leading:const Icon(Icons.bolt,color:Color(0xFF8DB1FF)),title:Text(wallet==null?'Credit balance unavailable':wallet.toString()+' credits'),trailing:IconButton(onPressed:refresh,icon:const Icon(Icons.refresh)))),const SizedBox(height:22),FilledButton.tonalIcon(onPressed:()=>logout(),icon:const Icon(Icons.logout),label:const Text('Sign out'))]);}
class Glass extends StatelessWidget{final Widget child;const Glass({super.key,required this.child});@override Widget build(BuildContext c)=>Container(decoration:BoxDecoration(color:Colors.white.withOpacity(.045),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white.withOpacity(.1))),child:child);}


class CreditsPage extends StatefulWidget {
 final String token;
 final Future<void> Function() onPaid;
 const CreditsPage({super.key, required this.token, required this.onPaid});
 @override State<CreditsPage> createState() => _CreditsPageState();
}
class _CreditsPageState extends State<CreditsPage> {
 bool busy = false;
 String message = '';
 String? reference;
 num? amount;
 num? credits;
 final packages = const [
  {'id':'pack_1333','credits':100,'amount':1333},
  {'id':'pack_2665','credits':200,'amount':2665},
  {'id':'pack_3998','credits':300,'amount':3998},
  {'id':'pack_5330','credits':400,'amount':5330},
  {'id':'pack_6663','credits':500,'amount':6663},
  {'id':'pack_7996','credits':600,'amount':7996},
  {'id':'pack_9328','credits':700,'amount':9328},
  {'id':'pack_10661','credits':800,'amount':10661},
  {'id':'pack_11993','credits':900,'amount':11993},
  {'id':'pack_13326','credits':1000,'amount':13326},
  {'id':'pack_26652','credits':2000,'amount':26652},
  {'id':'pack_39978','credits':3000,'amount':39978},
  {'id':'pack_53304','credits':4000,'amount':53304},
  {'id':'pack_66630','credits':5000,'amount':66630},
  {'id':'pack_79956','credits':6000,'amount':79956},
  {'id':'pack_93282','credits':7000,'amount':93282},
  {'id':'pack_106608','credits':8000,'amount':106608},
  {'id':'pack_119934','credits':9000,'amount':119934},
  {'id':'pack_133260','credits':10000,'amount':133260},
  {'id':'pack_146586','credits':11000,'amount':146586},
  {'id':'pack_159912','credits':12000,'amount':159912},
 ];
 String naira(num n) => '₦${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';
 Future<void> buy(Map<String,dynamic> p) async {
  setState(() { busy=true; message='Creating secure Flutterwave checkout…'; reference=null; });
  try {
   final d = await Api.call('devora-credit-payments', widget.token, {'action':'create','packageId':p['id']});
   final ref = (d['reference'] ?? '').toString();
   final link = (d['checkoutUrl'] ?? '').toString();
   if (!link.startsWith('https://')) throw Exception('Flutterwave did not return a valid checkout link.');
   setState(() { reference=ref; amount=d['amountNgn'] as num? ?? p['amount'] as num; credits=d['credits'] as num? ?? p['credits'] as num; message='Checkout opened. Complete payment, return here, then tap Verify payment.'; });
   final opened = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
   if (!opened && mounted) setState(() => message='Checkout link is ready, but could not open automatically. Reference: $ref');
  } catch(e) {
   if(mounted) setState(()=>message=e.toString().replaceFirst('Exception: ',''));
  } finally { if(mounted) setState(()=>busy=false); }
 }
 Future<void> verify() async {
  final ref=reference;
  if(ref==null || ref.isEmpty) return;
  setState(()=>{busy=true,message='Verifying payment with Flutterwave…'});
  try {
   final d=await Api.call('devora-credit-payments',widget.token,{'action':'verify','reference':ref});
   if(d['success']==true) {
    setState(()=>message='Payment verified! ${d['credits'] ?? credits} credits are available. Your balance: ${d['balance'] ?? 'refreshed'}.');
    await widget.onPaid();
   } else {
    setState(()=>message=(d['message']??'Payment is not confirmed yet. Try again shortly.').toString());
   }
  } catch(e) {
   setState(()=>message=e.toString().replaceFirst('Exception: ',''));
  } finally { if(mounted) setState(()=>busy=false); }
 }
 @override Widget build(BuildContext context) => ListView(
  padding: const EdgeInsets.all(16),
  children: [
   const Text('Buy credits',style:TextStyle(fontSize:26,fontWeight:FontWeight.w800)),
   const SizedBox(height:6),
   const Text('Secure checkout with Flutterwave. Pay by card, bank transfer or USSD where available.',style:TextStyle(color:Colors.white60)),
   const SizedBox(height:16),
   Glass(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Row(children:[Icon(Icons.verified_user_outlined,color:Color(0xFF8DB1FF)),SizedBox(width:8),Text('Protected payment',style:TextStyle(fontWeight:FontWeight.bold))]),
    const SizedBox(height:6),
    const Text('Credits are added only after the server verifies a successful payment. Never share your card PIN or OTP.',style:TextStyle(color:Colors.white60,fontSize:12)),
   ]))),
   const SizedBox(height:16),
   ...packages.map((p)=>Padding(
    padding:const EdgeInsets.only(bottom:9),
    child:Glass(child:ListTile(
     leading:const CircleAvatar(backgroundColor:Color(0xFF182E56),child:Icon(Icons.bolt,color:Color(0xFF9DC0FF))),
     title:Text('${p['credits']} credits',style:const TextStyle(fontWeight:FontWeight.bold)),
     subtitle:Text(naira(p['amount'] as num)),
     trailing:FilledButton(onPressed:busy?null:()=>buy(p),child:const Text('Buy')),
    )),
   )),
   if(reference!=null) ...[
    const SizedBox(height:8),
    Glass(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const Text('PAYMENT REFERENCE',style:TextStyle(color:Colors.white54,fontSize:11,letterSpacing:1.3)),
     const SizedBox(height:6),
     SelectableText(reference!,style:const TextStyle(color:Color(0xFF9DC0FF),fontWeight:FontWeight.bold)),
     if(amount!=null&&credits!=null) Padding(padding:const EdgeInsets.only(top:5),child:Text('${naira(amount!)} • ${credits!} credits')),
     const SizedBox(height:10),
     FilledButton.icon(onPressed:busy?null:verify,icon:const Icon(Icons.verified_outlined),label:const Text('Verify payment'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48))),
    ]))),
   ],
   if(busy) const Padding(padding:EdgeInsets.all(12),child:Center(child:CircularProgressIndicator())),
   if(message.isNotEmpty) Padding(padding:const EdgeInsets.only(top:12),child:Glass(child:Padding(padding:const EdgeInsets.all(12),child:Text(message)))),
  ],
 );
}
