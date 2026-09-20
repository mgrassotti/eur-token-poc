/// FFI wrapper around the `mat_dlc` cdylib (adaptor CET signing).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _JsonNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _JsonDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

class DlcSignatures {
  const DlcSignatures({required this.adaptorSigs, required this.refundSig});

  final List<String> adaptorSigs;
  final String refundSig;
}

class MatDlcException implements Exception {
  MatDlcException(this.message);
  final String message;
  @override
  String toString() => 'MatDlcException: $message';
}

class MatDlc {
  MatDlc._(this._json, this._free);

  final _JsonDart _json;
  final _FreeDart _free;

  static MatDlc? _instance;
  static bool _lookupFailed = false;

  static MatDlc? instance() {
    if (_instance != null) return _instance;
    if (_lookupFailed) return null;
    try {
      final lib = _open();
      final jsonFn = lib.lookupFunction<_JsonNative, _JsonDart>('mat_dlc_json');
      final freeFn = lib.lookupFunction<_FreeNative, _FreeDart>('mat_dlc_string_free');
      _instance = MatDlc._(jsonFn, freeFn);
      return _instance;
    } catch (_) {
      _lookupFailed = true;
      return null;
    }
  }

  static DynamicLibrary _open() {
    if (Platform.isMacOS) {
      for (final name in ['libmat_dlc.dylib', 'mat_dlc.dylib']) {
        try {
          return DynamicLibrary.open(name);
        } catch (_) {}
      }
    }
    if (Platform.isLinux) {
      for (final name in ['libmat_dlc.so', 'mat_dlc.so']) {
        try {
          return DynamicLibrary.open(name);
        } catch (_) {}
      }
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libmat_dlc.so');
    }
    return DynamicLibrary.process();
  }

  Map<String, dynamic> call(String op, Map<String, dynamic> request) {
    final opPtr = op.toNativeUtf8();
    final reqPtr = jsonEncode(request).toNativeUtf8();
    final outPtr = _json(opPtr, reqPtr);
    malloc.free(opPtr);
    malloc.free(reqPtr);
    if (outPtr == nullptr) {
      throw MatDlcException('null response');
    }
    final raw = outPtr.toDartString();
    _free(outPtr);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw MatDlcException(decoded['error']?.toString() ?? 'dlc error');
    }
    return decoded;
  }

  static String fundPubkey(String mnemonic) {
    final dlc = instance();
    if (dlc == null) {
      throw MatDlcException('mat_dlc native library not loaded');
    }
    return dlc.call('fund_keys', {'mnemonic': mnemonic})['pubkey_hex'] as String;
  }

  static DlcSignatures signAdaptor({
    required String mnemonic,
    required Map<String, dynamic> signPackage,
  }) {
    final dlc = instance();
    if (dlc == null) {
      throw MatDlcException('mat_dlc native library not loaded');
    }
    final out = dlc.call('sign_adaptor', {
      'mnemonic': mnemonic,
      'sign_package': signPackage,
    });
    return DlcSignatures(
      adaptorSigs: (out['adaptor_sigs'] as List<dynamic>).map((e) => e.toString()).toList(),
      refundSig: out['refund_sig'] as String,
    );
  }
}
