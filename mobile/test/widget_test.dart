import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brenkschat_mobile/screens/login_screen.dart';
import 'package:brenkschat_mobile/theme/app_theme.dart';

void main() {
  testWidgets('Экран входа показывает бренд и кнопку входа',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBrenksTheme(),
        home: LoginScreen(
          onAuthenticated: (_) {},
          themeMode: ThemeMode.dark,
          onThemeModeChanged: (_) {},
        ),
      ),
    );

    expect(find.text('БренксЧат'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Регистрация'), findsOneWidget);

    // Переключение на вкладку регистрации показывает поле почты.
    await tester.tap(find.text('Регистрация'));
    await tester.pumpAndSettle();
    expect(find.text('Создать аккаунт'), findsOneWidget);
    expect(find.text('Почта'), findsOneWidget);
  });
}
