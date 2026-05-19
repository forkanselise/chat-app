importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js");

// Initialize Firebase in the service worker
firebase.initializeApp({
  apiKey: "AIzaSyAjSEytqMT-wRYNIMrtxd9MBS1KE36TVu0",
  authDomain: "chat-app-2ea72.firebaseapp.com",
  projectId: "chat-app-2ea72",
  storageBucket: "chat-app-2ea72.firebasestorage.app",
  messagingSenderId: "775220676895",
  appId: "1:775220676895:web:0bf13fdd60f96db6cfc82a"
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log("Received background message: ", payload);
  
  const notificationTitle = payload.notification?.title || "New Message";
  const notificationOptions = {
    body: payload.notification?.body || "",
    icon: "/favicon.png"
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
