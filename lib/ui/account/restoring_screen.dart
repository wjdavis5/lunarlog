/// Data-free "Restoring your data…" step (U6; F3, AE13): held while the
/// bind-time full pull runs on an empty device, so the operator never
/// sees an empty app or the name form before the account's profiles land.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

class RestoringScreen extends StatelessWidget {
  const RestoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('restoring'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Restoring your data…',
              style: LLType.titleMedium.toTextStyle(),
            ),
          ],
        ),
      ),
    );
  }
}
