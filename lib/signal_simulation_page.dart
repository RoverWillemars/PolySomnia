import 'package:flutter/material.dart';

class SignalSimulationPage extends StatelessWidget {
  const SignalSimulationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 100,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.circle_notifications),
              onPressed: () {},
            ),
          ],
        ),
        title: const Text('Signal Simulation'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_emotions),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events),
            onPressed: () {},
          ),
        ],
      ),
      body: const Center(
        child: Text('Signal Simulation Page'),
      ),
    );
  }
}
