import 'dart:ffi';

import 'package:ffi/ffi.dart';

const _fileAttributeHidden = 0x2;
const _fileAttributeNormal = 0x80;
const _invalidFileAttributes = 0xFFFFFFFF;

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _getFileAttributes = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)
    >('GetFileAttributesW');

final _setFileAttributes = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32),
      int Function(Pointer<Utf16>, int)
    >('SetFileAttributesW');

/// Whether [path] has the Windows hidden attribute (false if missing).
bool isHidden(String path) => using((arena) {
  final attributes = _getFileAttributes(path.toNativeUtf16(allocator: arena));
  return attributes != _invalidFileAttributes &&
      attributes & _fileAttributeHidden != 0;
});

/// Sets the Windows hidden attribute on [path], if it exists.
void hide(String path) => using((arena) {
  final native = path.toNativeUtf16(allocator: arena);
  final attributes = _getFileAttributes(native);
  if (attributes == _invalidFileAttributes ||
      attributes & _fileAttributeHidden != 0) {
    return;
  }
  // FILE_ATTRIBUTE_NORMAL is only valid alone.
  _setFileAttributes(
    native,
    (attributes & ~_fileAttributeNormal) | _fileAttributeHidden,
  );
});
