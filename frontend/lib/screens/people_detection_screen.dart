import 'package:flutter/material.dart';

class PeopleDetectionScreen extends StatelessWidget {
  const PeopleDetectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'People Detection Screen',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
