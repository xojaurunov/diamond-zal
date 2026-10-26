import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';

/// YouTube pleyeri — brauzerda: sahifaning o'ziga qo'yilgan `<iframe>` (yangi oyna ochilmaydi).
Widget youtubeEmbed(String id) => HtmlElementView.fromTagName(
      key: ValueKey(id),
      tagName: 'iframe',
      onElementCreated: (el) {
        final f = el as JSObject;
        void set(String k, String v) => f.setProperty(k.toJS, v.toJS);
        set('src', 'https://www.youtube-nocookie.com/embed/$id?autoplay=1&playsinline=1&rel=0&modestbranding=1');
        set('allow', 'autoplay; encrypted-media; picture-in-picture; fullscreen');
        set('allowFullscreen', 'true');
        (f.getProperty('style'.toJS) as JSObject)
          ..setProperty('border'.toJS, '0'.toJS)
          ..setProperty('background'.toJS, '#000'.toJS);
      },
    );

/// Yuklangan video (R2) — brauzerda: sahifaning o'zidagi `<video>` (o'ynatish, surish, to'liq ekran).
/// [speed] — tezlik (0.5 — texnikani sekin ko'rish).
Widget videoEmbed(String url, {double speed = 1}) => _WebVideo(key: ValueKey(url), url: url, speed: speed);

class _WebVideo extends StatefulWidget {
  final String url;
  final double speed;
  const _WebVideo({super.key, required this.url, this.speed = 1});

  @override
  State<_WebVideo> createState() => _WebVideoState();
}

class _WebVideoState extends State<_WebVideo> {
  JSObject? _video;

  void _applySpeed() => _video?.setProperty('playbackRate'.toJS, widget.speed.toJS);

  @override
  void didUpdateWidget(_WebVideo old) {
    super.didUpdateWidget(old);
    if (old.speed != widget.speed) _applySpeed();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'video',
        onElementCreated: (el) {
          final v = _video = el as JSObject;
          v.setProperty('src'.toJS, '${widget.url}#t=0.1'.toJS);
          v.setProperty('controls'.toJS, true.toJS);
          v.setProperty('playsInline'.toJS, true.toJS);
          v.setProperty('preload'.toJS, 'metadata'.toJS);
          (v.getProperty('style'.toJS) as JSObject)
            ..setProperty('background'.toJS, '#000'.toJS)
            ..setProperty('objectFit'.toJS, 'contain'.toJS);
          _applySpeed();
        },
      );
}
