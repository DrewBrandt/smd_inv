import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/auth_service.dart';

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth({
    this.authStateStream = const Stream<User?>.empty(),
    this.onSignInWithProvider,
    this.onSignOut,
  });

  final Stream<User?> authStateStream;
  final Future<UserCredential> Function(AuthProvider provider)?
  onSignInWithProvider;
  final Future<void> Function()? onSignOut;
  int authStateChangesCalls = 0;
  int signOutCalls = 0;
  int signInWithProviderCalls = 0;
  AuthProvider? lastSignInProvider;

  @override
  Stream<User?> authStateChanges() {
    authStateChangesCalls += 1;
    return authStateStream;
  }

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    signInWithProviderCalls += 1;
    lastSignInProvider = provider;
    if (onSignInWithProvider != null) {
      return onSignInWithProvider!(provider);
    }
    throw UnimplementedError('signInWithProvider not configured');
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    if (onSignOut != null) {
      await onSignOut!();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() {
    AuthService.canEditOverride = null;
    AuthService.authOverride = null;
    AuthService.googleProviderOverride = null;
  });

  test('authStateChanges works without initialized Firebase app', () async {
    final first = await AuthService.authStateChanges().first;
    expect(first, isNull);
  });

  test('currentUser is null without initialized Firebase app', () {
    expect(AuthService.currentUser, isNull);
  });

  group('AuthService.canEditEmail', () {
    test('accepts UMD domains', () {
      expect(AuthService.canEditEmail('user@umd.edu'), isTrue);
      expect(AuthService.canEditEmail('user@terpmail.umd.edu'), isTrue);
    });

    test('rejects non-UMD domains', () {
      expect(AuthService.canEditEmail('user@gmail.com'), isFalse);
      expect(AuthService.canEditEmail('user@example.org'), isFalse);
    });

    test('handles malformed inputs', () {
      expect(AuthService.canEditEmail(null), isFalse);
      expect(AuthService.canEditEmail(''), isFalse);
      expect(AuthService.canEditEmail('not-an-email'), isFalse);
    });
  });

  test('canEdit uses override when provided', () {
    AuthService.canEditOverride = (_) => true;
    expect(AuthService.canEdit(null), isTrue);
  });

  test('canEdit falls back to email policy without override', () {
    AuthService.canEditOverride = null;
    expect(AuthService.canEdit(null), isFalse);
  });

  test('signInWithGoogle throws when Firebase is not initialized', () async {
    await expectLater(
      AuthService.signInWithGoogle(),
      throwsA(isA<StateError>()),
    );
  });

  test('signOut is a no-op when Firebase is not initialized', () async {
    await AuthService.signOut();
  });

  test('authStateChanges delegates to auth override when provided', () async {
    final auth = _FakeFirebaseAuth(authStateStream: Stream<User?>.value(null));
    AuthService.authOverride = () => auth;

    final first = await AuthService.authStateChanges().first;

    expect(first, isNull);
    expect(auth.authStateChangesCalls, 1);
  });

  test('signInWithGoogle uses provider sign-in on non-web', () async {
    final credential = _FakeUserCredential();
    final auth = _FakeFirebaseAuth(
      onSignInWithProvider: (_) async => credential,
    );
    AuthService.authOverride = () => auth;

    final result = await AuthService.signInWithGoogle();

    expect(result, same(credential));
    expect(auth.signInWithProviderCalls, 1);
    expect(auth.lastSignInProvider, isA<GoogleAuthProvider>());
  });

  test('signOut delegates to auth override when available', () async {
    final auth = _FakeFirebaseAuth();
    AuthService.authOverride = () => auth;

    await AuthService.signOut();

    expect(auth.signOutCalls, 1);
  });

  test('editor policy summary is stable', () {
    expect(
      AuthService.editorPolicySummary(),
      'Editors must sign in with @umd.edu or @terpmail.umd.edu.',
    );
  });
}
