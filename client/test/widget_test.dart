import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riff/app/app.dart';

void main() {
  testWidgets('app boots and shows home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RiffApp()));
    // Network calls return 400 in test mode, so the homeDataProvider lands in
    // its error state. We just verify the app scaffold renders.
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
