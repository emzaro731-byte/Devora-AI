import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:file_saver/file_saver.dart';

const _supabaseUrl = 'https://vihbsfrwnslnmheowkhy.supabase.co';
const _supabasePublishableKey = 'sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';

class LongVideoPage extends StatefulWidget {
  final String token;
  const LongVideoPage({super.key, required this.token});
  @override State<LongVideoPage> createState() => _LongVideoPageState();
}
class _LongVideoPageState extends State<LongVideoPage> {
  final prompt = TextEditingController();
  String resolution = '720p', ratio = '16:9', message = '';
  int minutes = 10;
  bool submitting = false;
  List<Map<String, dynamic>> projects = [];
  Timer? timer;
  int get rate => resolution == '480p' ? 28 : resolution == '1080p' ? 158 : 63;
  int get estimate => rate * minutes * 60;
  Map<String, String> get headers => {'apikey': _supabasePublishableKey, 'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'};

  @override void initState() { super.initState(); loadProjects(); timer = Timer.periodic(const Duration(seconds: 8), (_) => loadProjects()); }
  @override void dispose() { timer?.cancel(); prompt.dispose(); super.dispose(); }
  Future<void> loadProjects() async {
    try {
      final r = await http.get(Uri.parse('$_supabaseUrl/rest/v1/devora_long_video_projects?select=id,prompt,resolution,target_duration_seconds,status,completed_scenes,total_scenes,output_url,error_message,estimated_credits,created_at&order=created_at.desc&limit=10'), headers: headers).timeout(const Duration(seconds: 20));
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('Could not load projects: ${r.body}');
      final d = jsonDecode(r.body) as List;
      if (mounted) setState(() { projects = d.map((x) => Map<String, dynamic>.from(x)).toList(); });
    } catch (e) { if (mounted && projects.isEmpty) setState(() => message = e.toString().replaceFirst('Exception: ', '')); }
  }
  Future<void> createProject() async {
    final idea = prompt.text.trim();
    if (idea.isEmpty) { setState(() => message = 'Describe the video you want Devora to create.'); return; }
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Confirm long-video generation'),
      content: Text('Devora will automatically plan and generate scenes in the background, then assemble one MP4.\n\nDuration: $minutes minute(s)\nResolution: $resolution\nEstimated KIE credits: $estimate\n\nAt 720p, a 60-minute video is estimated at 226,800 KIE credits. Actual provider pricing may vary. This project will use your connected KIE account. Continue?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm cost'))],
    ));
    if (ok != true || !mounted) return;
    setState(() { submitting = true; message = 'Queueing your project…'; });
    try {
      final userResponse = await http.get(Uri.parse('$_supabaseUrl/auth/v1/user'), headers: headers).timeout(const Duration(seconds: 20));
      if (userResponse.statusCode < 200 || userResponse.statusCode >= 300) throw Exception('Your session expired. Sign in again.');
      final userData = jsonDecode(userResponse.body) as Map<String, dynamic>;
      final userId = (userData['id'] ?? '').toString();
      if (userId.isEmpty) throw Exception('Could not verify your account.');
      final r = await http.post(Uri.parse('$_supabaseUrl/rest/v1/devora_long_video_projects'),
        headers: {...headers, 'Prefer': 'return=representation'},
        body: jsonEncode({'user_id': userId, 'prompt': idea, 'model': 'bytedance/seedance-2-5', 'resolution': resolution, 'aspect_ratio': ratio, 'target_duration_seconds': minutes * 60, 'status': 'queued', 'estimated_credits': estimate}),
      ).timeout(const Duration(seconds: 30));
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('Could not queue project: ${r.body}');
      prompt.clear();
      setState(() => message = 'Project queued. Scenes are planned automatically and stay hidden from this screen.');
      await loadProjects();
    } catch (e) { setState(() => message = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => submitting = false); }
  }
  Future<void> openOutput(String url) async {
    setState(() => message = 'Downloading the finished MP4 to your phone…');
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
        throw Exception('The video download failed. Please retry.');
      }
      await FileSaver.instance.saveAs(
        name: 'Devora-AI-Long-Video-${DateTime.now().millisecondsSinceEpoch}',
        bytes: response.bodyBytes,
        ext: 'mp4',
        mimeType: MimeType.mp4Video,
      );
      if (mounted) setState(() => message = 'Video saved to your phone.');
    } catch (e) {
      if (mounted) setState(() => message = 'Could not save video: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Long video studio')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: const Color(0xFF09282B), border: Border.all(color: const Color(0xFF1B6B69))),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.movie_creation_outlined, size: 36, color: Color(0xFF67E8D8)),
          SizedBox(height: 10), Text('Create up to 1 hour', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          SizedBox(height: 6), Text('Devora creates the scene plan automatically, generates clips in the background, and assembles one MP4. You do not need to edit scenes.', style: TextStyle(color: Colors.white70, height: 1.4)),
        ])),
      const SizedBox(height: 16),
      TextField(controller: prompt, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Describe your full video', hintText: 'A cinematic story about…', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      Text('Video length: ${minutes == 60 ? '1 hour' : '$minutes minute(s)'}', style: const TextStyle(fontWeight: FontWeight.w800)),
      Slider(value: minutes.toDouble(), min: 1, max: 60, divisions: 59, label: '${minutes} min', onChanged: submitting ? null : (v) => setState(() => minutes = v.round())),
      DropdownButtonFormField<String>(value: resolution, decoration: const InputDecoration(labelText: 'Resolution'), items: const [
        DropdownMenuItem(value: '480p', child: Text('480p — 28 credits/second')),
        DropdownMenuItem(value: '720p', child: Text('720p — 63 credits/second')),
        DropdownMenuItem(value: '1080p', child: Text('1080p — 158 credits/second')),
      ], onChanged: submitting ? null : (v) => setState(() => resolution = v ?? '720p')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: ratio, decoration: const InputDecoration(labelText: 'Aspect ratio'), items: const [
        DropdownMenuItem(value: '16:9', child: Text('16:9 — Landscape')),
        DropdownMenuItem(value: '9:16', child: Text('9:16 — Portrait')),
        DropdownMenuItem(value: '1:1', child: Text('1:1 — Square')),
      ], onChanged: submitting ? null : (v) => setState(() => ratio = v ?? '16:9')),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Estimated provider cost', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5), Text('$estimate KIE credits', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4), const Text('Estimate uses the configured Seedance rates. KIE may change pricing. No generation starts until you confirm.', style: TextStyle(color: Colors.white60, fontSize: 12)),
      ]))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: submitting ? null : createProject, icon: submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded), label: Text(submitting ? 'Queueing…' : 'Confirm estimate & create video')),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message, style: const TextStyle(color: Colors.white70))),
      const SizedBox(height: 20), const Text('YOUR PROJECTS', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      if (projects.isEmpty) const Text('No long-video projects yet.', style: TextStyle(color: Colors.white54)),
      ...projects.map((p) {
        final status = (p['status'] ?? 'queued').toString();
        final done = (p['completed_scenes'] as num?)?.toInt() ?? 0;
        final total = (p['total_scenes'] as num?)?.toInt() ?? 0;
        final url = (p['output_url'] ?? '').toString();
        final error = (p['error_message'] ?? '').toString();
        return Card(margin: const EdgeInsets.only(top: 8), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((p['prompt'] ?? 'Video project').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6), Text('${status.toUpperCase()} · ${done}/${total == 0 ? '?' : total} clips', style: const TextStyle(color: Colors.white70)),
          if (total > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(value: done / total)),
          if (status == 'completed' && url.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.icon(onPressed: () => openOutput(url), icon: const Icon(Icons.download_rounded), label: const Text('Open / download finished MP4'))),
          if (status == 'failed' && error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error, style: const TextStyle(color: Colors.redAccent))),
        ])));
      }),
    ]),
  );
}
