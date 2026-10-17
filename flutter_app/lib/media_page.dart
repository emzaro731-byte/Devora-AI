import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const mediaSupabaseUrl = 'https://vihbsfrwnslnmheowkhy.supabase.co';
const mediaSupabaseKey = 'sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';
const mediaBackend = 'https://devora-ai-zcmz.onrender.com';

class MediaPage extends StatefulWidget {
 final String token;
 const MediaPage({super.key,required this.token});
 @override State<MediaPage> createState()=>_MediaPageState();
}
class _MediaPageState extends State<MediaPage>{
 final prompt=TextEditingController();
 String type='image',style='Photorealistic',ratio='1:1',model='';
 bool busy=false,creditLoading=false,purchaseBusy=false;String status='';String? error,mediaUrl,pendingReference;int? creditBalance;
 final styles=['Auto','Photorealistic','Cinematic','Anime','3D render','Digital art','Illustration','Watercolor','Oil painting','Comic book','Fantasy art','Cyberpunk','Pixel art','Minimalist','Fashion editorial','Vintage film','Documentary','Music video','Film noir','Retro futurism','Commercial'];
 Future<Map<String,dynamic>> paymentCall(Map<String,dynamic> body)async{
  final r=await http.post(Uri.parse(mediaSupabaseUrl+'/functions/v1/devora-credit-payments'),headers:{'Content-Type':'application/json','apikey':mediaSupabaseKey,'Authorization':'Bearer '+widget.token},body:jsonEncode(body)).timeout(const Duration(seconds:45));
  final d=jsonDecode(r.body) as Map<String,dynamic>;if(r.statusCode<200||r.statusCode>=300)throw Exception(d['error']??d['message']??'Payment request failed');return d;
 }
 Future<void> refreshBalance()async{
  if(creditLoading)return;setState(()=>creditLoading=true);
  try{final d=await call({'action':'credits'});if(mounted)setState(()=>creditBalance=(d['balance'] as num?)?.toInt());}
  catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
  finally{if(mounted)setState(()=>creditLoading=false);}
 }
 Future<void> buyCredits(String packageId)async{
  setState(() { purchaseBusy=true; error=null; });
  try{
   final d=await paymentCall({'action':'create','packageId':packageId});
   final ref=d['reference']?.toString()??'';final link=d['checkoutUrl']?.toString()??'';
   if(ref.isEmpty||link.isEmpty)throw Exception('Flutterwave did not return a checkout link.');
   setState(()=>pendingReference=ref);
   final opened=await launchUrl(Uri.parse(link),mode:LaunchMode.externalApplication);
   if(!opened)throw Exception('Could not open Flutterwave checkout. Check your browser and try again.');
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Complete payment in Flutterwave, then return here and tap Verify payment.')));
  }catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
  finally{if(mounted)setState(()=>purchaseBusy=false);}
 }
 Future<void> verifyPurchase()async{
  final ref=pendingReference;if(ref==null)return;
  setState(() { purchaseBusy=true; error=null; status='Verifying Flutterwave payment…'; });
  try{
   final d=await paymentCall({'action':'verify','reference':ref});
   if(d['pending']==true){setState(()=>status=d['message']?.toString()??'Payment is still pending. Try again shortly.');return;}
   setState(() { pendingReference=null; status='Payment confirmed. '+(d['credits']?.toString()??'')+' credits added.'; });
   await refreshBalance();
  }catch(e){setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
  finally{if(mounted)setState(()=>purchaseBusy=false);}
 }
 void showCreditPacks(){
  showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:const Color(0xFF111B2B),builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   const Text('Buy Devora credits',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('Secure checkout powered by Flutterwave · NGN',style:TextStyle(color:Colors.white60)),const SizedBox(height:14),
   for(final pack in const [{'id':'starter','credits':500,'price':500,'name':'Starter'},{'id':'creator','credits':1000,'price':1000,'name':'Creator'},{'id':'studio','credits':2000,'price':2000,'name':'Studio'},{'id':'filmmaker','credits':5000,'price':5000,'name':'Filmmaker'}])
    Card(color:const Color(0xFF17253A),child:ListTile(title:Text(pack['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(pack['credits'].toString()+' credits'),trailing:FilledButton(onPressed:purchaseBusy?null:(){Navigator.pop(ctx);buyCredits(pack['id'].toString());},child:Text('₦'+(pack['price'] as int).toString())))),
   const SizedBox(height:8),const Text('Credits are added only after Flutterwave confirms the payment.',style:TextStyle(color:Colors.white54,fontSize:12))
  ]))));
 }
 Future<Map<String,dynamic>> call(Map<String,dynamic> body)async{
  final r=await http.post(Uri.parse(mediaSupabaseUrl+'/functions/v1/devora-media'),headers:{'Content-Type':'application/json','apikey':mediaSupabaseKey,'Authorization':'Bearer '+widget.token},body:jsonEncode(body)).timeout(const Duration(seconds:90));
  final d=jsonDecode(r.body) as Map<String,dynamic>;if(r.statusCode<200||r.statusCode>=300||d['error']!=null)throw Exception(d['error']??'Media request failed');return d;
 }
 Future<void> generate()async{
  final p=prompt.text.trim();if(p.isEmpty){setState(()=>error='Enter a prompt first.');return;}
  setState((){busy=true;error=null;mediaUrl=null;status='Starting generation…';});
  try{
   final st=type=='music'?'auto':style, ar=type=='music'?'auto':ratio;
   final enhanced=(st!='Auto'&&st!='auto'?'Visual style: '+st+'. ':'')+(ar!='auto'?'Aspect ratio: '+ar+'. ':'')+p;
   final req=DateTime.now().microsecondsSinceEpoch.toString();
   final task=await call({'type':type,'model':model,'requestId':req,'prompt':enhanced,'style':st,'aspectRatio':ar,'aspect_ratio':ar,'files':[],'attachments':[]});
   Map<String,dynamic>? done;
   for(var i=0;i<90;i++){
    await Future.delayed(const Duration(seconds:3));
    final chk=await call({'action':'status','taskId':task['taskId'],'requestId':req});
    if(chk['state']=='success'){done=chk;break;}
    if(chk['state']=='fail'||chk['state']=='failed')throw Exception(chk['failMsg']??'Generation failed.');
    if(mounted)setState(()=>status='Generating '+type+'… '+(chk['progress']?.toString()??'')+'%');
   }
   if(done==null)throw Exception('Generation is still running. Task ID: '+(task['taskId']?.toString()??'unknown'));
   final url=done['url']?.toString();if(url==null||url.isEmpty)throw Exception('No media URL returned.');
   setState(()=>status='Copying media to your private Supabase storage…');
   final kind=type=='image'?'generated_image':type=='video'?'generated_video':'generated_music';
   final name='devora-'+type+'-'+DateTime.now().millisecondsSinceEpoch.toString()+(type=='image'?'.png':type=='video'?'.mp4':'.mp3');
   final saved=await http.post(Uri.parse(mediaBackend+'/api/storage/import'),headers:{'Content-Type':'application/json','Authorization':'Bearer '+widget.token},body:jsonEncode({'url':url,'name':name,'assetType':kind,'metadata':{'prompt':enhanced,'model':model,'style':st,'aspect_ratio':ar,'request_id':req,'source':'native_flutter'}})).timeout(const Duration(seconds:150));
   final sd=jsonDecode(saved.body) as Map<String,dynamic>;if(saved.statusCode<200||saved.statusCode>=300)throw Exception(sd['error']??'Supabase storage failed.');
   final path=sd['path']?.toString();String display=url;
   if(path!=null){
    final signed=await http.post(Uri.parse(mediaSupabaseUrl+'/storage/v1/object/sign/devora-assets/'+path.split('/').map(Uri.encodeComponent).join('/')),headers:{'apikey':mediaSupabaseKey,'Authorization':'Bearer '+widget.token,'Content-Type':'application/json'},body:jsonEncode({'expiresIn':604800}));
    if(signed.statusCode>=200&&signed.statusCode<300){final sj=jsonDecode(signed.body);final sp=(sj['signedURL']??sj['signedUrl'])?.toString();if(sp!=null)display=sp.startsWith('http')?sp:mediaSupabaseUrl+'/storage/v1'+sp;}
   }
   final user=await http.get(Uri.parse(mediaSupabaseUrl+'/auth/v1/user'),headers:{'apikey':mediaSupabaseKey,'Authorization':'Bearer '+widget.token});
   if(user.statusCode!=200)throw Exception('Media saved, but account verification for chat history failed.');
   final uid=(jsonDecode(user.body) as Map)['id'];
   final title=type.toUpperCase()+': '+(enhanced.length>55?enhanced.substring(0,55):enhanced);
   final messages=[{'role':'user','content':'Create '+type+': '+enhanced},{'role':'assistant','content':'Generated '+type+' saved in Supabase. File: '+name+'. Storage path: '+(path??'unknown')+'. Media URL: '+display,'media_type':type,'media_url':display,'storage_path':path,'file_name':name,'prompt':enhanced}];
   final hist=await http.post(Uri.parse(mediaSupabaseUrl+'/rest/v1/devora_conversations'),headers:{'apikey':mediaSupabaseKey,'Authorization':'Bearer '+widget.token,'Content-Type':'application/json','Prefer':'return=minimal'},body:jsonEncode({'user_id':uid,'title':title,'messages':messages,'updated_at':DateTime.now().toUtc().toIso8601String()}));
   if(hist.statusCode<200||hist.statusCode>=300)throw Exception('Media saved, but chat history save failed: '+hist.body);
   setState((){mediaUrl=display;status='Saved to Supabase Storage and chat history.';});
  }catch(e){final message=e.toString().replaceFirst('Exception: ','');setState(()=>error=message);if(message.toLowerCase().contains('insufficient credit'))WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted)showCreditPacks(); });}
  finally{if(mounted)setState(()=>busy=false);await refreshBalance();}
 }
 @override void initState(){super.initState();refreshBalance();}
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
  const Text('DEVORA AI STUDIO',style:TextStyle(color:Color(0xFF22D3EE),letterSpacing:2,fontWeight:FontWeight.bold)),
  const SizedBox(height:8),const Text('Create image, video or music',style:TextStyle(fontSize:25,fontWeight:FontWeight.bold)),
  const SizedBox(height:8),const Text('Each successful generation is uploaded to Supabase and recorded in chat history.',style:TextStyle(color:Colors.white60)),
  const SizedBox(height:14),
  Card(color:const Color(0xFF102A34),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   const Text('YOUR DEVORA CREDITS',style:TextStyle(color:Color(0xFF22D3EE),fontWeight:FontWeight.bold,letterSpacing:1)),
   const SizedBox(height:5),Row(children:[Expanded(child:Text(creditLoading?'Loading balance…':creditBalance==null?'Balance unavailable':'${creditBalance} credits',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold))),IconButton(onPressed:creditLoading?null:refreshBalance,icon:const Icon(Icons.refresh)),FilledButton.icon(onPressed:purchaseBusy?null:showCreditPacks,icon:const Icon(Icons.add_card),label:const Text('Buy credits'))]),
   if(pendingReference!=null)Padding(padding:const EdgeInsets.only(top:8),child:FilledButton.tonalIcon(onPressed:purchaseBusy?null:verifyPurchase,icon:const Icon(Icons.verified_outlined),label:Text(purchaseBusy?'Checking payment…':'Verify payment'))),
   if(pendingReference!=null)const Text('After completing checkout, return to Devora and verify your payment.',style:TextStyle(color:Colors.white60,fontSize:12))
  ]))),
  const SizedBox(height:18),
  SegmentedButton<String>(segments:const [ButtonSegment(value:'image',label:Text('Image'),icon:Icon(Icons.image_outlined)),ButtonSegment(value:'video',label:Text('Video'),icon:Icon(Icons.videocam_outlined)),ButtonSegment(value:'music',label:Text('Music'),icon:Icon(Icons.music_note))],selected:{type},onSelectionChanged:(v)=>setState(() { type=v.first; model=''; mediaUrl=null; })),
  const SizedBox(height:14),TextField(controller:prompt,minLines:3,maxLines:6,decoration:InputDecoration(labelText:type.toUpperCase()+' prompt',hintText:type=='music'?'Describe the song, genre, mood and vocals…':'Describe what you want to create…',alignLabelWithHint:true)),
  if(type!='music')...[
   const SizedBox(height:14),const Text('Visual style'),const SizedBox(height:6),DropdownButtonFormField<String>(value:style,items:styles.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>style=v??style)),
   const SizedBox(height:14),const Text('Aspect ratio'),const SizedBox(height:6),DropdownButtonFormField<String>(value:ratio,items:const ['Auto','16:9','9:16','1:1','4:3','3:4','3:2','2:3','21:9'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>ratio=v??ratio)),
  ],
  const SizedBox(height:14),const Text('KIE.ai model'),const SizedBox(height:6),
  DropdownButtonFormField<String>(value:model.isEmpty?null:model,hint:const Text('Use provider default'),items:(type=='image'?const {'':'Provider default','nano-banana':'Nano Banana','flux-1.1-pro':'Flux 1.1 Pro'}:type=='video'?const {'':'Provider default','bytedance/seedance-2-5':'Seedance 2.5','veo-3-1':'Veo 3.1','kling-3.0/video':'Kling 3.0','grok-imagine-video-1-5-preview':'Grok Imagine Video 1.5'}:const {'':'Provider default','music':'AI music','suno':'Suno'}).entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>setState(()=>model=v??'')),
  const SizedBox(height:16),FilledButton.icon(onPressed:busy?null:generate,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.auto_awesome),label:Text(busy?'Generating and saving…':'Generate '+type),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52),backgroundColor:const Color(0xFF258BFF))),
  if(busy)const Padding(padding:EdgeInsets.only(top:12),child:LinearProgressIndicator()),
  if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:Colors.redAccent))),
  if(status.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Text(status,style:const TextStyle(color:Color(0xFF22D3EE)))),
  if(mediaUrl!=null)Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(type.toUpperCase()+' saved',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),if(type=='image')Image.network(mediaUrl!,errorBuilder:(_,__,___)=>const Text('Image saved. Use the link below to open it.'))else Text('Your '+type+' is saved in Supabase. Open the link to play or download.'),SelectableText(mediaUrl!)]))),
 ]);
}
