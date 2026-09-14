// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_image_generator/main.dart';

void main() {
  testWidgets('AI Image Generator renders its main sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ImageStudioApp());

    expect(find.text('AI Image Generator'), findsOneWidget);
    expect(find.text('生成设置'), findsOneWidget);
    expect(find.text('图片预览'), findsOneWidget);
    expect(find.text('生成图片'), findsOneWidget);
  });
}
