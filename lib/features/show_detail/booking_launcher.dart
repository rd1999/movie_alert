import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the official booking page in the official app (if it handles the
/// link) or the browser. We never book ourselves (spec §2).
Future<void> openBooking(BuildContext context, Uri url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var ok = false;
  try {
    ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text("Couldn't open $url")));
  }
}
