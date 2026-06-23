import nodemailer from 'nodemailer';

type MailMessage = {
  to: string;
  subject: string;
  text: string;
  html?: string;
};

function mailFrom(): string {
  return (
    process.env.MAIL_FROM ||
    process.env.SMTP_USER ||
    'БренксЧат <no-reply@localhost>'
  );
}

function smtpConfigured(): boolean {
  return Boolean(process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);
}

function resendConfigured(): boolean {
  return Boolean(process.env.RESEND_API_KEY);
}

function emailProvider(): 'resend' | 'smtp' | 'dev' {
  if (process.env.EMAIL_PROVIDER === 'resend') return 'resend';
  if (process.env.EMAIL_PROVIDER === 'smtp') return 'smtp';
  if (resendConfigured()) return 'resend';
  if (smtpConfigured()) return 'smtp';
  return 'dev';
}

function createTransport() {
  if (!smtpConfigured()) return null;
  const port = Number(process.env.SMTP_PORT || 465);
  const timeoutMs = Number(process.env.SMTP_TIMEOUT_MS || 8000);
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port,
    secure:
      process.env.SMTP_SECURE != null
        ? process.env.SMTP_SECURE === 'true'
        : port === 465,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
    connectionTimeout: timeoutMs,
    greetingTimeout: timeoutMs,
    socketTimeout: timeoutMs,
  });
}

export function isEmailDeliveryConfigured(): boolean {
  return resendConfigured() || smtpConfigured();
}

function authEmailHtml(params: {
  code: string;
  title: string;
  action: string;
  purpose: 'login' | 'register' | 'reset' | 'bind';
}): string {
  const subtitle =
    params.purpose === 'login'
      ? 'Подтвердите вход в аккаунт'
      : params.purpose === 'register'
        ? 'Подтвердите почту для нового аккаунта'
        : params.purpose === 'reset'
          ? 'Используйте код для смены пароля'
          : 'Подтвердите привязку почты к аккаунту';
  const hint =
    params.purpose === 'reset'
      ? 'Если вы не запрашивали сброс пароля, просто проигнорируйте это письмо.'
      : 'Если это были не вы, просто проигнорируйте письмо.';

  return `
<!doctype html>
<html lang="ru">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${params.title}</title>
  </head>
  <body style="margin:0;padding:0;background:#f1f7fc;font-family:Inter,Segoe UI,Arial,sans-serif;color:#111827;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f1f7fc;padding:32px 14px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background:rgba(255,255,255,0.96);border:1px solid #dbe7f0;border-radius:24px;overflow:hidden;box-shadow:0 18px 48px rgba(15,23,42,0.10);">
            <tr>
              <td style="padding:26px 28px 18px;background:#ffffff;border-bottom:1px solid #e5eef5;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                  <tr>
                    <td width="52" valign="middle">
                      <div style="width:44px;height:44px;border-radius:16px;background:#eef4f8;border:1px solid #dbe7f0;text-align:center;line-height:44px;font-size:20px;font-weight:800;color:#334155;">B</div>
                    </td>
                    <td valign="middle">
                      <div style="font-size:20px;font-weight:800;letter-spacing:0;color:#111827;">БренксЧат</div>
                      <div style="margin-top:3px;font-size:13px;color:#64748b;">${subtitle}</div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:30px 28px 8px;">
                <div style="font-size:16px;line-height:1.55;color:#334155;">Ваш код для ${params.action}:</div>
                <div style="margin:22px 0 18px;padding:22px 18px;border-radius:20px;background:#f8fafc;border:1px solid #dbe7f0;text-align:center;">
                  <div style="font-size:42px;line-height:1;font-weight:900;letter-spacing:11px;color:#0f172a;">${params.code}</div>
                </div>
                <div style="font-size:14px;line-height:1.55;color:#64748b;">Код действует <strong style="color:#334155;">10 минут</strong>. Никому его не пересылайте.</div>
              </td>
            </tr>
            <tr>
              <td style="padding:18px 28px 30px;">
                <div style="border-radius:16px;background:#eef4f8;border:1px solid #dbe7f0;padding:14px 16px;font-size:13px;line-height:1.5;color:#64748b;">${hint}</div>
              </td>
            </tr>
          </table>
          <div style="padding:18px 12px 0;font-size:12px;color:#94a3b8;">БренксЧат · безопасный вход по почте</div>
        </td>
      </tr>
    </table>
  </body>
</html>
  `.trim();
}

export async function sendMail(message: MailMessage): Promise<void> {
  const provider = emailProvider();
  if (provider === 'resend') {
    await sendWithResend(message);
    return;
  }

  if (provider === 'dev') {
    console.log('[email:dev]', {
      to: message.to,
      subject: message.subject,
      text: message.text,
    });
    return;
  }

  const transport = createTransport();
  if (!transport) throw new Error('SMTP is not configured');
  await transport.sendMail({
    from: mailFrom(),
    ...message,
  });
}

async function sendWithResend(message: MailMessage): Promise<void> {
  if (!process.env.RESEND_API_KEY) {
    throw new Error('RESEND_API_KEY is not configured');
  }
  const timeoutMs = Number(process.env.EMAIL_HTTP_TIMEOUT_MS || 8000);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: mailFrom(),
        to: [message.to],
        subject: message.subject,
        text: message.text,
        html: message.html,
      }),
      signal: controller.signal,
    });
    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`Resend email failed: ${response.status} ${body.slice(0, 300)}`);
    }
  } finally {
    clearTimeout(timeout);
  }
}

export async function sendAuthCodeEmail(
  to: string,
  code: string,
  purpose: 'login' | 'register' | 'reset' | 'bind'
): Promise<void> {
  const title =
    purpose === 'login'
      ? 'Код входа в БренксЧат'
      : purpose === 'register'
        ? 'Подтверждение почты БренксЧат'
        : purpose === 'reset'
          ? 'Сброс пароля БренксЧат'
          : 'Привязка почты БренксЧат';
  const action =
    purpose === 'login'
      ? 'входа'
      : purpose === 'register'
        ? 'подтверждения почты'
        : purpose === 'reset'
          ? 'сброса пароля'
          : 'привязки почты';

  await sendMail({
    to,
    subject: title,
    text: `Ваш код для ${action}: ${code}. Он действует 10 минут.`,
    html: authEmailHtml({ code, title, action, purpose }),
  });
}
