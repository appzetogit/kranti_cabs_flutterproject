import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Prefixes a server-relative media path (e.g. `/uploads/..`) with the media
/// host so it can be loaded. Absolute http(s) and data: URLs pass through
/// untouched. Use this before handing any server image path to an image widget.
String resolveMediaUrl(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return '';
  if (t.startsWith('http://') || t.startsWith('https://') || t.startsWith('data:')) {
    return t;
  }
  final origin = AppConstants.mediaBaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$origin/${t.replaceFirst(RegExp(r'^/+'), '')}';
}

/// Safely builds an [ImageProvider] from a URL, local file path, or data URI string.
/// Prevents `Invalid argument(s): No host specified in URI file:///` when local file paths,
/// data URLs, or invalid URI strings are passed to NetworkImage.
ImageProvider? buildSafeImageProvider(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final trimmed = url.trim();

  // Network HTTP / HTTPS URL
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return NetworkImage(trimmed);
  }

  // Base64 Data URL (e.g. data:image/png;base64,...)
  if (trimmed.startsWith('data:image/')) {
    try {
      final base64String = trimmed.split(',').last;
      final bytes = base64Decode(base64String);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // file:// URI scheme
  if (trimmed.startsWith('file://')) {
    try {
      final uri = Uri.parse(trimmed);
      final file = File.fromUri(uri);
      if (file.existsSync()) {
        return FileImage(file);
      }
    } catch (_) {
      final path = trimmed.replaceFirst('file://', '');
      final file = File(path);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }

  // Direct local file path
  try {
    final file = File(trimmed);
    if (file.existsSync()) {
      return FileImage(file);
    }
  } catch (_) {}

  return null;
}

/// Safely builds a [DecorationImage] from a URL, file path, or data URI string.
DecorationImage? buildSafeDecorationImage(String? url, {BoxFit fit = BoxFit.cover}) {
  final provider = buildSafeImageProvider(url);
  if (provider == null) return null;
  return DecorationImage(image: provider, fit: fit);
}
