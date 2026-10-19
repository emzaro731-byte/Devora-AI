import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const sbUrl='https://vihbsfrwnslnmheowkhy.supabase.co';
const sbKey='sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';
const uuid=Uuid();
void main()=>runApp(const DevoraApp());

class DevoraApp extends StatefulWidget { const DevoraApp({super.key}); @override State<DevoraApp> createState()=>_AppState(); }
class _AppState extends State<DevoraApp>{
 String? token,email; bool loading=true;
 @override void initState(){super.initState();restore();}
 Future<void> restore()async{final p=await SharedPreferences.getInstance();setState((){token=p.getString('access_token');email=p.getString('email');loading=false;});}
 Future<void> login(String t,String e)async{final p=await SharedPreferences.getInstance();await p.setString('access_token',t);await p.setString('email',e);setState((){token=t;email=e;});}
 Future<void> logout()async{final p=await SharedPreferences.getInstance();await p.remove('access_token');await p.remove('email');setState(()=>token=null);}
 @override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,title:'Devora AI',theme:ThemeData(useMaterial3:true,brightness:Brightness.dark,scaffoldBackgroundColor:const Color(0xFF060A14),colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF558AFF),brightness:Brightness.dark)),home:loading?const Scaffold(body:Center(child:CircularProgressIndicator())):token==null?AuthPage(onLogin:login):MainPage(token:token!,email:email??'',onLogout:logout));
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
 static Future<Map<String,dynamic>> call(String fn,String t,Map<String,dynamic> body)async{
  final r=await http.post(Uri.parse(sbUrl+'/functions/v1/'+fn),headers:headers(t),body:jsonEncode(body)).timeout(const Duration(seconds:90));
  dynamic d;try{d=jsonDecode(r.body);}catch(_){d={'error':r.body};}
  if(r.statusCode<200||r.statusCode>=300||d is! Map||(d['error']!=null&&d['success']!=true))throw Exception(d is Map?(d['error']??d['message']??'Request failed'): 'Request failed');
  return Map<String,dynamic>.from(d);
 }
}
class AuthPage extends StatefulWidget{final Future<void> Function(String,String) onLogin;const AuthPage({super.key,required this.onLogin});@override State<AuthPage> createState()=>_AuthState();}
class _AuthState extends State<AuthPage>{
 final e=TextEditingController(),p=TextEditingController();bool signup=false,busy=false;String err='';
 Future<void> go()async{setState(()=>{busy=true,err=''});try{final d=await Api.auth(signup?'signup':'signin',e.text.trim(),p.text);await widget.onLogin(d['access_token'],(d['user']?['email']??e.text).toString());}catch(x){setState(()=>err=x.toString().replaceFirst('Exception: ',''));}if(mounted)setState(()=>busy=false);}
 @override Widget build(BuildContext c)=>Scaffold(body:Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF142A55),Color(0xFF060A14),Color(0xFF080E1C)])),child:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:430),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Icon(Icons.auto_awesome,size:66,color:Color(0xFF77A7FF)),const SizedBox(height:16),const Text('Devora AI',textAlign:TextAlign.center,style:TextStyle(fontSize:32,fontWeight:FontWeight.w900)),const SizedBox(height:8),const Text('Your personal AI studio',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60)),const SizedBox(height:28),Glass(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[TextField(controller:e,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.mail_outline),border:InputBorder.none)),const Divider(color:Colors.white12),TextField(controller:p,obscureText:true,decoration:const InputDecoration(labelText:'Password',prefixIcon:Icon(Icons.lock_outline),border:InputBorder.none))]))),if(err.isNotEmpty)Padding(padding:const EdgeInsets.all(10),child:Text(err,style:const TextStyle(color:Colors.redAccent))),const SizedBox(height:12),FilledButton(onPressed:busy?null:go,style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52)),child:busy?const CircularProgressIndicator():Text(signup?'Create account':'Sign in')),TextButton(onPressed:()=>setState(()=>{signup=!signup,err=''}),child:Text(signup?'Already registered? Sign in':'Create a new account'))])))))));
}
class MainPage extends StatefulWidget{final String token,email;final Future<void> Function() onLogout;const MainPage({super.key,required this.token,required this.email,required this.onLogout});@override State<MainPage> createState()=>_MainState();}
class _MainState extends State<MainPage>{int tab=0;num? wallet;@override void initState(){super.initState();refresh();}
 Future<void> refresh()async{try{final d=await Api.call('devora-media',widget.token,{'action':'wallet'});if(mounted)setState(()=>wallet=d['balance']);}catch(_){}}
 @override
 Widget build(BuildContext c) => Scaffold(
   appBar: AppBar(
     title: const Row(children: [
       Icon(Icons.auto_awesome, color: Color(0xFF77A7FF)),
       SizedBox(width: 10),
       Text('Devora AI', style: TextStyle(fontWeight: FontWeight.w800)),
     ]),
     actions: [
       if (wallet != null)
         Center(child: Padding(
           padding: const EdgeInsets.only(right: 16),
           child: Text('${wallet.toString()} credits'),
         )),
     ],
   ),
   body: IndexedStack(index: tab, children: [
     ChatPage(token: widget.token),
     MediaPage(token: widget.token, refresh: refresh),
     AccountPage(email: widget.email, wallet: wallet, refresh: refresh, logout: widget.onLogout),
   ]),
   bottomNavigationBar: NavigationBar(
     selectedIndex: tab,
     onDestinationSelected: (v) => setState(() => tab = v),
     destinations: const [
       NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
       NavigationDestination(icon: Icon(Icons.movie_creation_outlined), label: 'Create'),
       NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
     ],
   ),
 );
}
class ChatPage extends StatefulWidget{final String token;const ChatPage({super.key,required this.token});@override State<ChatPage> createState()=>_ChatState();}
class _ChatState extends State<ChatPage>{final input=TextEditingController();final msgs=<Map<String,String>>[{'role':'assistant','content':'Hi! I am Devora AI. Ask a question or use Create to generate media.'}];bool busy=false;String mode='Chat';
 Future<void> send()async{final q=input.text.trim();if(q.isEmpty||busy)return;input.clear();setState(()=>{msgs.add({'role':'user','content':q}),busy=true});try{final d=await Api.call('destiny-ai',widget.token,{'message':q,'prompt':q,'mode':mode,'messages':msgs});final a=(d['reply']??d['response']??d['message']??d['content']??'No response returned.').toString();setState(()=>msgs.add({'role':'assistant','content':a}));}catch(x){setState(()=>msgs.add({'role':'assistant','content':'Chat error: '+x.toString().replaceFirst('Exception: ','')}));}if(mounted)setState(()=>busy=false);}
 @override Widget build(BuildContext c)=>Column(children:[Padding(padding:const EdgeInsets.all(12),child:Row(children:[const Text('AI ASSISTANT',style:TextStyle(color:Colors.white54,letterSpacing:1.4)),const Spacer(),DropdownButton<String>(value:mode,items:['Chat','Code','Study','Write','Creative'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>mode=v!))])),Expanded(child:ListView.builder(padding:const EdgeInsets.all(14),itemCount:msgs.length+(busy?1:0),itemBuilder:(c,i){if(i>=msgs.length)return const Text('Devora is thinking…',style:TextStyle(color:Colors.white54));final m=msgs[i];final user=m['role']=='user';return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:Container(constraints:const BoxConstraints(maxWidth:340),margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:user?const Color(0xFF1B3B70):const Color(0xFF111A2B),borderRadius:BorderRadius.circular(18),border:Border.all(color:Colors.white10)),child:Text(m['content']??'',style:const TextStyle(height:1.45))));})),SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(12),child:Glass(child:Row(children:[Expanded(child:TextField(controller:input,minLines:1,maxLines:4,onSubmitted:(_)=>send(),decoration:const InputDecoration(hintText:'Message Devora AI…',border:InputBorder.none,contentPadding:EdgeInsets.all(12))),),IconButton(onPressed:busy?null:send,icon:const Icon(Icons.arrow_upward),style:IconButton.styleFrom(backgroundColor:const Color(0xFF477DFF)))]))))]);}
class MediaPage extends StatefulWidget{final String token;final Future<void> Function() refresh;const MediaPage({super.key,required this.token,required this.refresh});@override State<MediaPage> createState()=>_MediaState();}
class _MediaState extends State<MediaPage>{
 final prompt=TextEditingController();String type='image',model='gpt-image-2-text-to-image',resolution='720p',ratio='auto',status='',result='';int duration=10;bool busy=false;
 final models={'image':['gpt-image-2-text-to-image','nano-banana-2-1','nano-banana-2','nano-banana-pro','grok-imagine-image-2-0/text-to-image','bytedance/seedream-v4-text-to-image','flux-2/pro-text-to-image','qwen2-1/text-to-image'],'video':['bytedance/seedance-2-5','veo-3-1','kling-3.0/video','grok-imagine-video-1-5-preview'],'music':['V6','V6_MINI','V6_WILD']};
 int get cost=>type=='image'?({'gpt-image-2-text-to-image':6,'nano-banana-2-1':12,'nano-banana-2':8,'nano-banana-pro':24,'grok-imagine-image-2-0/text-to-image':10,'bytedance/seedream-v4-text-to-image':8,'flux-2/pro-text-to-image':10,'qwen2-1/text-to-image':6}[model]??8):type=='video'?({'bytedance/seedance-2-5':170,'veo-3-1':255,'kling-3.0/video':70,'grok-imagine-video-1-5-preview':20}[model]??70):(model=='V6_MINI'?10:12);
 Future<void> generate()async{if(prompt.text.trim().isEmpty){setState(()=>status='Enter a prompt first.');return;}setState(()=>{busy=true,status='Starting generation…',result=''});try{final d=await Api.call('devora-media',widget.token,{'type':type,'model':model,'prompt':prompt.text.trim(),'requestId':uuid.v4(),'resolution':resolution,'aspectRatio':ratio,'duration':duration});final task=(d['taskId']??'').toString();setState(()=>status='Queued task '+task);if(task.isNotEmpty)await poll(task);}catch(x){setState(()=>status=x.toString().replaceFirst('Exception: ',''));}if(mounted){setState(()=>busy=false);await widget.refresh();}}
 Future<void> poll(String task)async{for(var i=0;i<120;i++){await Future.delayed(const Duration(seconds:3));if(!mounted)return;try{final d=await Api.call('devora-media',widget.token,{'action':'status','taskId':task});final state=(d['state']??'').toString().toLowerCase();final urls=d['urls'];String u=(d['url']??'').toString();if(u.isEmpty&&urls is List&&urls.isNotEmpty)u=urls.first.toString();if(u.startsWith('http')){setState(()=>{result=u,status='Finished. Open the result link to view or save it.'});return;}if(state.contains('fail')||state.contains('error')){setState(()=>status=(d['failMsg']??'Generation failed').toString());return;}setState(()=>status='Generating… '+((i+1)*3).toString()+' seconds');}catch(_){setState(()=>status='Waiting for provider status…');}}setState(()=>status='Still processing. Task ID: '+task);}
 @override
 Widget build(BuildContext c) {
   return ListView(
     padding: const EdgeInsets.all(16),
     children: [
       const Text('Create something amazing', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
       const SizedBox(height: 5),
       const Text('AI images, videos and music', style: TextStyle(color: Colors.white60)),
       const SizedBox(height: 18),
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
       const SizedBox(height: 12),
       Glass(child: Padding(
         padding: const EdgeInsets.all(14),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             const Text('PROMPT', style: TextStyle(color: Colors.white54, letterSpacing: 1.5)),
             TextField(controller: prompt, minLines: 4, maxLines: 7, decoration: const InputDecoration(hintText: 'Describe your creation…', border: InputBorder.none)),
             const Divider(color: Colors.white12),
             const Text('MODEL', style: TextStyle(color: Colors.white54, letterSpacing: 1.5)),
             DropdownButtonFormField<String>(
               value: model,
               isExpanded: true,
               decoration: const InputDecoration(border: InputBorder.none),
               items: models[type]!.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
               onChanged: busy ? null : (v) => setState(() => model = v!),
             ),
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
                 items: ['auto', '1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3', '21:9'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
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
         Padding(padding: const EdgeInsets.only(top: 12), child: Glass(child: Padding(
           padding: const EdgeInsets.all(14),
           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
             const Text('RESULT LINK', style: TextStyle(fontWeight: FontWeight.bold)),
             const SizedBox(height: 8),
             SelectableText(result, style: const TextStyle(color: Color(0xFF9DC0FF))),
             const Text('Tap and hold the link to copy it, then open it to save the file.', style: TextStyle(color: Colors.white54, fontSize: 12)),
           ]),
         ))),
       const SizedBox(height: 20),
       const Text('API secrets stay on Supabase, not inside this APK.', style: TextStyle(color: Colors.white38, fontSize: 11)),
     ],
   );
 }
}
class AccountPage extends StatelessWidget{final String email;final num? wallet;final Future<void> Function() refresh,logout;const AccountPage({super.key,required this.email,required this.wallet,required this.refresh,required this.logout});@override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[const Text('Account',style:TextStyle(fontSize:25,fontWeight:FontWeight.w800)),const SizedBox(height:16),Glass(child:ListTile(leading:const Icon(Icons.person_outline),title:Text(email),subtitle:const Text('Devora AI member'))),const SizedBox(height:10),Glass(child:ListTile(leading:const Icon(Icons.bolt,color:Color(0xFF8DB1FF)),title:Text(wallet==null?'Credit balance unavailable':wallet.toString()+' credits'),trailing:IconButton(onPressed:refresh,icon:const Icon(Icons.refresh)))),const SizedBox(height:22),FilledButton.tonalIcon(onPressed:()=>logout(),icon:const Icon(Icons.logout),label:const Text('Sign out'))]);}
class Glass extends StatelessWidget{final Widget child;const Glass({super.key,required this.child});@override Widget build(BuildContext c)=>Container(decoration:BoxDecoration(color:Colors.white.withOpacity(.045),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white.withOpacity(.1))),child:child);}
