// A real browser notification permission + display bridge for the web
// build (this app currently only runs as web). Compiles to a no-op stub
// on any other platform target instead of failing to build.
export 'push_notifications_stub.dart'
    if (dart.library.js_interop) 'push_notifications_web.dart';
