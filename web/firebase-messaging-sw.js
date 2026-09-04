// Required by firebase_messaging for web: handles push messages that
// arrive while no tab has focus. Values below must be kept in sync with
// lib/firebase_options.dart (same Firebase Web app config — see that
// file's comment; these values aren't secret).
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyBaw6Ey6FTAmcnhAq1JusVQ5WpDELu5JgA",
  appId: "1:476362648228:web:d57a0e4f1687fa1fe7d431",
  messagingSenderId: "476362648228",
  projectId: "travel-planner-62306",
  authDomain: "travel-planner-62306.firebaseapp.com",
  storageBucket: "travel-planner-62306.firebasestorage.app",
});

// Activate updates to this file immediately instead of waiting for every
// open tab to close first — makes iterating on this file during testing
// much less confusing.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

const messaging = firebase.messaging();

// Raw listener purely for diagnostics — proves whether a push event reaches
// this worker at all, independent of whether Firebase's own parsing below
// succeeds. Safe to run alongside `onBackgroundMessage`; both fire on the
// same event.
self.addEventListener('push', (event) => {
  console.log('[push_worker] push event received, raw payload:', event.data ? event.data.text() : '(no payload)');
});

messaging.onBackgroundMessage((message) => {
  console.log('[push_worker] onBackgroundMessage fired:', message);
  const notification = message.notification || {};
  self.registration.showNotification(notification.title || "TravelPlanner", {
    body: notification.body || "",
    icon: "icons/Icon-192.png",
  });
});

console.log('[push_worker] firebase-messaging-sw.js loaded and messaging initialized');
