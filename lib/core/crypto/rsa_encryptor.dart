import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/api.dart' show PublicKeyParameter;
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;
import 'package:pointycastle/asymmetric/pkcs1.dart' show PKCS1Encoding;
import 'package:pointycastle/asymmetric/rsa.dart' show RSAEngine;

/// Mirrors the `RSAEncryptor` used by pass.neu.edu.cn's `login_neu.js`.
///
/// The school page hard-codes an RSA public key and encrypts `username+password`
/// with PKCS#1 v1.5 padding. Keeping the same behaviour here lets the native
/// login flow work without embedding a browser for the common case.
abstract final class NeuRsaEncryptor {
  static const publicKeyBase64 =
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnjA28DLKXZzxbKmo9/1WkVLf1mr'
      '+wtLXLXt6sC4WiBCtsbzF5ewm7ARZeAdS3iZtqlYPn6IcUoOw42H8nAK/tfFcIb6dZ1K0atn'
      '0U39oWCGPzYuKtLJeMuNZiDXVuAXtojrckOjLW9B3gUnaNGLuIx0fYe66l0o9WjU2cGLNZQfi'
      'Ixs2h00z1EA9IdSnVxiVQWSD+lsP3JZXh2TT287la4Y4603SQNKTK/QvXfcmccwTEd1IW6HwGx'
      'D6QrkInBiHisKWxmveN7UDSaQRZ/J97G0YC32pD38WT53izXeK0p/kU/X37VP555um1wVWFvPI'
      'uc9I7gMP1+hq5a+X6c++tQIDAQAB';

  static final RSAPublicKey _publicKey = _parsePublicKey(publicKeyBase64);

  static String encrypt(String plainText) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(_publicKey));
    final encrypted = engine.process(
      Uint8List.fromList(utf8.encode(plainText)),
    );
    return base64Encode(encrypted);
  }

  static RSAPublicKey _parsePublicKey(String base64Value) {
    final parser = ASN1Parser(Uint8List.fromList(base64Decode(base64Value)));
    final spki = parser.nextObject() as ASN1Sequence;
    final bitString = spki.elements[1] as ASN1BitString;

    final keyParser = ASN1Parser(Uint8List.fromList(bitString.stringValue));
    final rsaSequence = keyParser.nextObject() as ASN1Sequence;
    final modulus = (rsaSequence.elements[0] as ASN1Integer).valueAsBigInteger;
    final exponent = (rsaSequence.elements[1] as ASN1Integer).valueAsBigInteger;

    return RSAPublicKey(modulus, exponent);
  }
}
