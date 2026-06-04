import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

/// Web implementation — injects a <video> element via JS eval.
void jsInjectVideo(String src, VoidCallback onEnded) {
  js.context.callMethod('eval', [
    '''
    (function() {
      var view = document.querySelector('flt-platform-view');
      if (!view) {
        setTimeout(function() { window.postMessage('retry-video', '*'); }, 100);
        return;
      }
      view.innerHTML = '';
      var v = document.createElement('video');
      v.src = '$src';
      v.autoplay = true;
      v.muted = true;
      v.playsInline = true;
      v.style.width = '100%';
      v.style.height = '100%';
      v.style.objectFit = 'cover';
      v.style.borderRadius = '24px';
      v.onended = function() {
        window.postMessage('welcome-video-ended', '*');
      };
      v.onerror = function() {
        window.postMessage('welcome-video-failed', '*');
      };
      view.appendChild(v);
    })();
    '''
  ]);
}
