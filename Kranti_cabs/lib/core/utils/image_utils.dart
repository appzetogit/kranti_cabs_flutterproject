import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Turns a CMS image path into something an image widget can actually load.
///
/// The backend stores media as server-relative paths (`/1_Bike.png`,
/// `/uploads/...`), never absolute URLs. Widgets that tested `startsWith('http')`
/// therefore always fell through to their bundled fallback, and ones that passed
/// the raw value to `CachedNetworkImage` got an unloadable URL — either way the
/// CMS image never appeared.
///
/// Values that are already usable as-is (absolute URLs, `data:` URIs, bundled
/// `assets/...` paths) are returned untouched.
String resolveMediaUrl(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('data:') ||
      trimmed.startsWith('assets/')) {
    return trimmed;
  }

  final origin = AppConstants.mediaBaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$origin/${trimmed.replaceFirst(RegExp(r'^/+'), '')}';
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
