import { useCallback, useEffect, useState } from 'react';
import * as api from '@/lib/api';

export type PushSubscriptionStatus = 'unsupported' | 'denied' | 'granted' | 'pending' | 'default';

export function usePushNotifications() {
  const [status, setStatus] = useState<PushSubscriptionStatus>('pending');
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    checkStatus();
  }, []);

  const checkStatus = useCallback(async () => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      setStatus('unsupported');
      return;
    }

    const permission = Notification.permission;
    if (permission === 'denied') {
      setStatus('denied');
      return;
    }

    if (permission !== 'granted') {
      setStatus('default');
      return;
    }

    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      setIsSubscribed(!!sub);
      setStatus('granted');
    } catch {
      setStatus('unsupported');
    }
  }, []);

  const requestPermission = useCallback(async (): Promise<boolean> => {
    if (!('Notification' in window)) {
      return false;
    }

    const permission = await Notification.requestPermission();
    if (permission === 'granted') {
      setStatus('granted');
      return true;
    }
    
    if (permission === 'denied') {
      setStatus('denied');
    } else {
      setStatus('default');
    }
    return false;
  }, []);

  const subscribe = useCallback(async (): Promise<boolean> => {
    if (status === 'unsupported') return false;

    setLoading(true);
    try {
      // Запрашиваем разрешение если нужно
      if (Notification.permission !== 'granted') {
        const granted = await requestPermission();
        if (!granted) return false;
      }

      // Регистрируем Service Worker
      const reg = await navigator.serviceWorker.register('/sw.js', { scope: '/' });
      await navigator.serviceWorker.ready;

      // Получаем публичный ключ
      const { publicKey } = await api.getPushVapidPublicKey();

      // Создаём подписку
      const subscription = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey),
      });

      // Отправляем подписку на сервер
      const subData = subscription.toJSON();
      await api.subscribePush({
        endpoint: subscription.endpoint,
        keys: {
          p256dh: subData.keys?.p256dh || '',
          auth: subData.keys?.auth || '',
        },
      });

      setIsSubscribed(true);
      return true;
    } catch (err) {
      console.error('Push subscription failed:', err);
      return false;
    } finally {
      setLoading(false);
    }
  }, [status, requestPermission]);

  const unsubscribe = useCallback(async (): Promise<boolean> => {
    setLoading(true);
    try {
      const reg = await navigator.serviceWorker.ready;
      const subscription = await reg.pushManager.getSubscription();
      
      if (subscription) {
        await subscription.unsubscribe();
        await api.unsubscribePush(subscription.endpoint);
      }
      
      setIsSubscribed(false);
      return true;
    } catch (err) {
      console.error('Push unsubscribe failed:', err);
      return false;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    status,
    isSubscribed,
    loading,
    subscribe,
    unsubscribe,
    requestPermission,
    refresh: checkStatus,
  };
}

function urlBase64ToUint8Array(base64String: string): ArrayBuffer {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray.buffer;
}
