import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whatsapp_clone/screens/login.dart';
import 'package:whatsapp_clone/screens/register.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget buildAuthApp() {
    return MaterialApp(
      home: const LoginScreen(),
      routes: {
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const Scaffold(body: Center(child: Text('Home Stub'))),
      },
    );
  }

  group('Auth UI flow', () {
    testWidgets('login shows required field errors on empty submit', (
      tester,
    ) async {
      await tester.pumpWidget(buildAuthApp());
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Email or number is required'), findsOneWidget);
    });

    testWidgets('navigates from login to register and back', (tester) async {
      await tester.pumpWidget(buildAuthApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsWidgets);

      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Back!'), findsOneWidget);
    });

    testWidgets('register validates required and max-length fields', (
      tester,
    ) async {
      await tester.pumpWidget(buildAuthApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Email required'), findsOneWidget);

      final displayNameField = find.byType(TextField).at(1);
      await tester.enterText(displayNameField, 'x' * 41);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Display name is too long'), findsOneWidget);
    });
  });
}
