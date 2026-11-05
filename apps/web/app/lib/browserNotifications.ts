// Notifications need a secure context. A browser that refuses the constructor, such as Chromium on Android outside a
// service worker, is treated as a failed notification rather than an error the listener must handle.
export type NotificationAccess = 'unsupported' | NotificationPermission;

export function notificationAccess(): NotificationAccess {
  if (!window.isSecureContext || typeof Notification === 'undefined') {
    return 'unsupported';
  }

  return Notification.permission;
}

// The browser shows its permission prompt only in response to a click, so call this from a user action.
export async function requestNotificationAccess(): Promise<NotificationAccess> {
  const access = notificationAccess();

  if (access !== 'default') return access;

  try {
    return await Notification.requestPermission();
  } catch {
    return 'denied';
  }
}

export function showNotification(title: string, body: string): void {
  if (notificationAccess() !== 'granted') return;

  try {
    // One tag means a quick run of skips replaces the alert instead of stacking them.
    const notification = new Notification(title, {
      body,
      tag: 'cadenza-song',
      silent: true,
    });

    notification.onclick = () => {
      window.focus();
      notification.close();
    };
  } catch {
    // The song still changes on screen, so a refused alert is skipped quietly.
  }
}
