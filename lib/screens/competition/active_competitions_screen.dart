import 'package:flutter/material.dart';

class ActiveCompetitionsScreen extends StatelessWidget {
  const ActiveCompetitionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktif Yarışmalar'),
      ),
      body: const Center(
        child: Text(
          'Aktif Yarışmalar ekranı (şimdilik boş)',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
