// Service Worker для Silentix - Push-уведомления

const PUSH_TAG = 'silentix-push';

self.addEventListener('push', (event) => {
  const data = event.data?.json() || {};
  
  const title = data.title || 'Silentix';
  const body = data.body || 'Новое сообщение';
  const tag = data.tag || PUSH_TAG;
  
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/icon-192.png',
      badge: '/badge-72.png',
      tag,
      data: data.data,
      vibrate: [200, 100, 200],
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  const chatId = event.notification.data?.chatId;
  const url = chatId ? `/?chat=${chatId}` : '/';
  
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          if (chatId) {
            client.navigate(url);
          }
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(url);
      }
      return Promise.resolve();
    })
  );
});
