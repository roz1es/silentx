import webpush from 'web-push';
import * as store from './store.js';

// Настройка VAPID (должна быть вызвана перед использованием)
export function setupWebPush(publicKey: string, privateKey: string, subject: string): void {
  webpush.setVapidDetails(subject, publicKey, privateKey);
}

// Отправка push-уведомления пользователю
export async function sendPushNotification(
  userId: string,
  payload: { title: string; body: string; icon?: string; tag?: string; data?: { chatId?: string } }
): Promise<void> {
  const subscriptions = store.getPushSubscriptions(userId);
  if (subscriptions.length === 0) return;

  const pushPayload = JSON.stringify(payload);
  await Promise.allSettled(
    subscriptions.map((sub) =>
      webpush.sendNotification(sub, pushPayload).catch((err: Error & { statusCode?: number }) => {
        // Если подписка больше не валидна (410 Gone), удаляем её
        if (err.statusCode === 410) {
          store.removePushSubscription(userId, sub.endpoint);
        }
      })
    )
  );
}

// Отправка уведомления всем участникам чата кроме отправителя
export async function notifyChatParticipants(
  chatId: string,
  senderId: string,
  title: string,
  body: string
): Promise<void> {
  const chat = store.getChat(chatId);
  if (!chat) return;

  const recipients = chat.participantIds.filter((id) => id !== senderId);
  
  await Promise.allSettled(
    recipients.map((userId) => {
      // Не отправляем если чат у пользователя без звука
      if (store.isChatMutedForUser(userId, chatId)) {
        return Promise.resolve();
      }
      return sendPushNotification(userId, {
        title,
        body,
        tag: `chat-${chatId}`,
        data: { chatId },
      });
    })
  );
}
