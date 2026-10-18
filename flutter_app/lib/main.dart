import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DevoraApp());
}

/// Interface intentionally removed at the user's request.
/// Backend services and server-side code remain in the repository.
class DevoraApp extends StatelessWidget {
  const DevoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: true,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      ),
    );
  }
}
