import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a web page in the phone's own browser. Tests replace it with a fake.
typedef UrlOpener = Future<bool> Function(Uri url);

final urlOpenerProvider = Provider<UrlOpener>(
  (ref) => (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);
