import mysql from 'mysql2/promise';

const execute = process.argv.includes('--execute');
const SYSTEM_USER_IDS = new Set(['user-bot']);

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL is required');
}

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

function messagePreview(row) {
  if (row.encrypted_text) return 'Сообщение';
  switch (row.media_kind) {
    case 'image':
      return '📷 Фото';
    case 'file':
      return `📎 ${row.media_file_name || 'Файл'}`;
    case 'voice':
      return '🎤 Голосовое';
    case 'video_note':
      return '🎬 Видеокружок';
    default:
      break;
  }
  if (row.image_url) return '📷 Фото';
  return String(row.text || '').slice(0, 120) || 'Сообщение';
}

const connection = await mysql.createConnection({
  uri: process.env.DATABASE_URL,
  dateStrings: true,
});

try {
  const [userRows] = await connection.execute(
    `SELECT id, username
     FROM users
     WHERE email IS NULL OR TRIM(email) = ''
     ORDER BY username`
  );
  const users = userRows.filter((user) => !SYSTEM_USER_IDS.has(String(user.id)));
  const userIds = users.map((user) => String(user.id));

  if (userIds.length === 0) {
    console.log('No users without email found.');
    process.exitCode = 0;
  } else {
    const [directChatRows] = await connection.query(
      `SELECT DISTINCT c.id
       FROM chats c
       JOIN chat_participants cp ON cp.chat_id = c.id
       WHERE c.type = 'direct' AND cp.user_id IN (?)`,
      [userIds]
    );
    const [ownedChatRows] = await connection.query(
      'SELECT id FROM chats WHERE channel_owner_id IN (?)',
      [userIds]
    );
    const deletedChatIds = [
      ...new Set(
        [...directChatRows, ...ownedChatRows].map((row) => String(row.id))
      ),
    ];

    console.log(
      JSON.stringify(
        {
          mode: execute ? 'execute' : 'dry-run',
          preservedSystemUsers: [...SYSTEM_USER_IDS],
          users,
          deletedDirectOrOwnedChats: deletedChatIds.length,
        },
        null,
        2
      )
    );

    if (!execute) {
      console.log('Run again with --execute to apply the cleanup.');
    } else {
      await connection.beginTransaction();
      try {
        const [removedMessageRows] = await connection.query(
          'SELECT id FROM messages WHERE sender_id IN (?)',
          [userIds]
        );
        const removedMessageIds = removedMessageRows.map((row) => String(row.id));

        if (removedMessageIds.length > 0) {
          await connection.query(
            'UPDATE messages SET reply_to_message_id = NULL WHERE reply_to_message_id IN (?)',
            [removedMessageIds]
          );
        }

        const [reactionRows] = await connection.query(
          'SELECT id, reactions FROM messages WHERE reactions IS NOT NULL'
        );
        const removedUserIds = new Set(userIds);
        for (const row of reactionRows) {
          const reactions = parseJson(row.reactions, {});
          const cleaned = {};
          for (const [emoji, reactionUserIds] of Object.entries(reactions)) {
            const remaining = Array.isArray(reactionUserIds)
              ? reactionUserIds.filter((id) => !removedUserIds.has(String(id)))
              : [];
            if (remaining.length > 0) cleaned[emoji] = remaining;
          }
          await connection.execute(
            'UPDATE messages SET reactions = CAST(? AS JSON) WHERE id = ?',
            [JSON.stringify(Object.keys(cleaned).length > 0 ? cleaned : null), row.id]
          );
        }

        for (const table of [
          'auth_sessions',
          'push_subscriptions',
          'user_chat_muted',
          'user_chat_pinned',
          'user_e2ee_devices',
          'user_e2ee_key_backups',
        ]) {
          await connection.query(`DELETE FROM \`${table}\` WHERE user_id IN (?)`, [
            userIds,
          ]);
        }

        if (deletedChatIds.length > 0) {
          await connection.query(
            'DELETE FROM user_chat_muted WHERE chat_id IN (?)',
            [deletedChatIds]
          );
          await connection.query(
            'DELETE FROM user_chat_pinned WHERE chat_id IN (?)',
            [deletedChatIds]
          );
          await connection.query('DELETE FROM chats WHERE id IN (?)', [
            deletedChatIds,
          ]);
        }

        await connection.query('DELETE FROM messages WHERE sender_id IN (?)', [
          userIds,
        ]);
        await connection.query(
          'DELETE FROM chat_participants WHERE user_id IN (?)',
          [userIds]
        );
        await connection.query('DELETE FROM users WHERE id IN (?)', [userIds]);

        const [chatRows] = await connection.query(
          'SELECT id, unread, last_read_at FROM chats'
        );
        for (const chat of chatRows) {
          const unread = parseJson(chat.unread, {});
          const lastReadAt = parseJson(chat.last_read_at, {});
          for (const userId of userIds) {
            delete unread[userId];
            delete lastReadAt[userId];
          }
          await connection.execute(
            `UPDATE chats
             SET unread = CAST(? AS JSON), last_read_at = CAST(? AS JSON)
             WHERE id = ?`,
            [
              JSON.stringify(unread),
              JSON.stringify(Object.keys(lastReadAt).length > 0 ? lastReadAt : null),
              chat.id,
            ]
          );
        }

        await connection.execute(
          `UPDATE chats c
           LEFT JOIN messages m
             ON m.chat_id = c.id AND m.id = c.pinned_message_id
           SET c.pinned_message_id = NULL
           WHERE c.pinned_message_id IS NOT NULL AND m.id IS NULL`
        );

        const [remainingChats] = await connection.query('SELECT id FROM chats');
        for (const chat of remainingChats) {
          const [latestRows] = await connection.execute(
            `SELECT sender_id, text, encrypted_text, image_url, media_kind,
                    media_file_name, created_at
             FROM messages
             WHERE chat_id = ? AND deleted = 0
             ORDER BY created_at DESC
             LIMIT 1`,
            [chat.id]
          );
          const latest = latestRows[0];
          const lastMessage = latest
            ? {
                text: messagePreview(latest),
                time: Number(latest.created_at),
                senderId: String(latest.sender_id),
              }
            : null;
          await connection.execute(
            'UPDATE chats SET last_message = CAST(? AS JSON) WHERE id = ?',
            [JSON.stringify(lastMessage), chat.id]
          );
        }

        // The normalized tables are authoritative. Remove the stale legacy snapshot.
        await connection.execute('DELETE FROM app_state WHERE id = ?', ['main']);

        await connection.commit();
        console.log(`Deleted ${users.length} users without email.`);
      } catch (error) {
        await connection.rollback();
        throw error;
      }
    }
  }
} finally {
  await connection.end();
}
