// Service Worker для БренксЧат - Push-уведомления

const PUSH_TAG = 'brenkschat-push';

self.addEventListener('push', (event) => {
  const data = event.data?.json() || {};
  
  const title = data.title || 'БренксЧат';
  const body = data.body || 'Новое сообщение';
  const tag = data.tag || PUSH_TAG;
  const isCall = !!data.data?.call;
  
  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/icon-192.png',
      badge: '/badge-72.png',
      tag,
      data: data.data,
      requireInteraction: !!data.requireInteraction || isCall,
      renotify: isCall,
      vibrate: isCall ? [300, 120, 300, 120, 300] : [200, 100, 200],
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  const chatId = event.notification.data?.chatId;
  const isCall = !!event.notification.data?.call;
  const url = chatId ? `/?chat=${chatId}` : isCall ? '/?call=1' : '/';
  
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
