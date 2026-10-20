import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// YouTube pleyeri — telefonda: WebView ichida (sahifaning o'zida o'ynaydi).
Widget youtubeEmbed(String id) => _Embed(key: ValueKey(id), id: id);

class _Embed extends StatefulWidget {
  final String id;
  const _Embed({super.key, required this.id});

  @override
  State<_Embed> createState() => _EmbedState();
}

class _EmbedState extends State<_Embed> {
  late final WebViewController _web;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Pleyer manba manzilini (referrer) talab qiladi — sahifa shu `baseUrl` bilan yuklanadi,
    // aks holda YouTube "153" xatosini ko'rsatadi.
    const origin = 'https://www.youtube-nocookie.com';
    final src = '$origin/embed/${widget.id}?autoplay=1&playsinline=1&rel=0&modestbranding=1';
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        // pleyer ichidagi havolalar (kanal, "YouTube'da ko'rish") ilovani olib ketmasin
        onNavigationRequest: (r) =>
            r.url.startsWith(origin) || r.url == 'about:blank' ? NavigationDecision.navigate : NavigationDecision.prevent,
      ))
      ..loadHtmlString('''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000}iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="$src" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
</body></html>''', baseUrl: origin);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        WebViewWidget(controller: _web),
        if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF8052FF))),
      ]);
}

/// Yuklangan video (R2) — telefonda: WebView ichida HTML5 `<video>`. Ochilishi bilan birinchi kadr
/// va o'ynatish tugmasi ko'rinadi; to'liq ekran tugmasi WebView'ning o'zida ishlaydi.
Widget videoEmbed(String url) => _FileVideo(key: ValueKey(url), url: url);

class _FileVideo extends StatefulWidget {
  final String url;
  const _FileVideo({super.key, required this.url});

  @override
  State<_FileVideo> createState() => _FileVideoState();
}

class _FileVideoState extends State<_FileVideo> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    final src = const HtmlEscape().convert(widget.url);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => r.url == 'about:blank' ? NavigationDecision.navigate : NavigationDecision.prevent,
      ))
      ..loadHtmlString('''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000}video{position:fixed;inset:0;width:100%;height:100%;object-fit:contain;background:#000}</style>
</head><body>
<video src="$src#t=0.1" controls playsinline preload="metadata" controlsList="nodownload"></video>
</body></html>''');
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
