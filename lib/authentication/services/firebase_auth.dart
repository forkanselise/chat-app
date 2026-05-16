import 'package:firebase_auth/firebase_auth.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<User?> register(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);

    if (credential.user != null) {
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'email': credential.user!.email,
      });
    }

    return credential.user;
  }

  Future<User?> login(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(email: email, password: password);
    
    // Ensure user doc exists
    if (credential.user != null) {
      await _firestore.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'email': credential.user!.email,
      }, SetOptions(merge: true));
    }

    return credential.user;
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
