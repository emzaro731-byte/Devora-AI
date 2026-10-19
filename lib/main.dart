import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

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
       DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[Color(0xFF91A9FF),Color(0xFF4DE0F3)]),borderRadius:BorderRadius.all(Radius.circular(12))),child:SizedBox(width:38,height:38,child:Icon(Icons.auto_awesome_rounded,color:Color(0xFF07101F),size:22))),
       SizedBox(width:11),
       Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
         Text('Devora AI',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18,letterSpacing:-.4)),
         Text('YOUR CREATIVE STUDIO',style:TextStyle(fontSize:9,letterSpacing:1.5,color:Colors.white54,fontWeight:FontWeight.w600)),
       ]),
     ]),
     actions: [
       if(wallet!=null) Padding(padding:const EdgeInsets.only(right:12),child:Center(child:Container(padding:const EdgeInsets.symmetric(horizontal:11,vertical:8),decoration:BoxDecoration(color:const Color(0xFF172746),borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFF405D9B))),child:Row(children:[const Icon(Icons.bolt_rounded,size:15,color:Color(0xFF9AB8FF)),const SizedBox(width:4),Text(wallet.toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12)),const SizedBox(width:3),const Text('CR',style:TextStyle(fontSize:10,color:Colors.white60))])))),
     ],
   ),
   body: DecoratedBox(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFF0B1428),Color(0xFF070B16),Color(0xFF070B16)])),child:IndexedStack(index:tab,children:[
     ChatPage(token:widget.token),
     MediaPage(token:widget.token,refresh:refresh),
     CreditsPage(token:widget.token,onPaid:refresh),
     AccountPage(email:widget.email,wallet:wallet,refresh:refresh,logout:widget.onLogout),
   ])),
   bottomNavigationBar:NavigationBar(height:68,selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[
     NavigationDestination(icon:Icon(Icons.chat_bubble_outline_rounded),selectedIcon:Icon(Icons.chat_rounded),label:'Chat'),
     NavigationDestination(icon:Icon(Icons.auto_awesome_mosaic_outlined),selectedIcon:Icon(Icons.auto_awesome),label:'Create'),
     NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),selectedIcon:Icon(Icons.account_balance_wallet_rounded),label:'Credits'),
     NavigationDestination(icon:Icon(Icons.person_outline_rounded),selectedIcon:Icon(Icons.person_rounded),label:'Account'),
   ]),
 );
}
class ChatPage extends StatefulWidget{final String token;const ChatPage({super.key,required this.token});@override State<ChatPage> createState()=>_ChatState();}
class _ChatState extends State<ChatPage>{final input=TextEditingController();final msgs=<Map<String,String>>[{'role':'assistant','content':'Hi! I am Devora AI. Ask a question or use Create to generate media.'}];bool busy=false;String mode='Chat';
 Future<void> send()async{final q=input.text.trim();if(q.isEmpty||busy)return;input.clear();setState(()=>{msgs.add({'role':'user','content':q}),busy=true});try{final d=await Api.call('destiny-ai',widget.token,{'message':q,'prompt':q,'mode':mode,'messages':msgs});final a=(d['reply']??d['response']??d['message']??d['content']??'No response returned.').toString();setState(()=>msgs.add({'role':'assistant','content':a}));}catch(x){setState(()=>msgs.add({'role':'assistant','content':'Chat error: '+x.toString().replaceFirst('Exception: ','')}));}if(mounted)setState(()=>busy=false);}
 @override Widget build(BuildContext c)=>Column(children:[Padding(padding:const EdgeInsets.all(12),child:Row(children:[const Icon(Icons.auto_awesome_rounded,color:Color(0xFF8DA9FF),size:18),const SizedBox(width:8),const Text('AI ASSISTANT',style:TextStyle(color:Colors.white70,letterSpacing:1.4,fontWeight:FontWeight.w800,fontSize:11)),const Spacer(),DropdownButton<String>(value:mode,items:['Chat','Code','Study','Write','Creative'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>mode=v!))])),Expanded(child:ListView.builder(padding:const EdgeInsets.all(14),itemCount:msgs.length+(busy?1:0),itemBuilder:(c,i){if(i>=msgs.length)return const Text('Devora is thinking…',style:TextStyle(color:Colors.white54));final m=msgs[i];final user=m['role']=='user';return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:Container(constraints:const BoxConstraints(maxWidth:340),margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:user?const Color(0xFF1B3B70):const Color(0xFF111A2B),borderRadius:BorderRadius.circular(18),border:Border.all(color:Colors.white10)),child:Text(m['content']??'',style:const TextStyle(height:1.45))));})),SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(12),child:Glass(child:Row(children:[Expanded(child:TextField(controller:input,minLines:1,maxLines:4,onSubmitted:(_)=>send(),decoration:const InputDecoration(hintText:'Message Devora AI…',border:InputBorder.none,contentPadding:EdgeInsets.all(12))),),IconButton(onPressed:busy?null:send,icon:const Icon(Icons.arrow_upward),style:IconButton.styleFrom(backgroundColor:const Color(0xFF477DFF)))]))))]);}
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
       Glass(child:Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF263F79),Color(0xFF101B35),Color(0xFF11172A)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         Container(width:42,height:42,decoration:BoxDecoration(color:const Color(0xFF8DA9FF).withOpacity(.16),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.auto_awesome_rounded,color:Color(0xFF9EB7FF),size:24)),
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
