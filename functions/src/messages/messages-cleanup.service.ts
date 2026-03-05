import { Injectable } from '@nestjs/common';
import { FirebaseAdminService } from '../firebase/firebase-admin.service';

@Injectable()
export class MessagesCleanupService {
  constructor(private readonly fb: FirebaseAdminService) {}

  /**
   * Delete delivered messages older than 5 minutes
   */
  async deleteOldDeliveredMessages(): Promise<void> {
    const fiveMinutesAgo = Date.now() - 5 * 60 * 1000; // 5 minutes in milliseconds

    try {
      console.log(
        'Starting cleanup of old delivered messages (older than 5 minutes)',
      );

      // Get all messages from flat structure
      const snapshot = await this.fb
        .database()
        .ref('messages')
        .get();

      if (!snapshot.exists() || snapshot.val() === null) {
        console.log('No messages to cleanup');
        return;
      }

      const messagesMap = snapshot.val() as Record<string, any>;
      let deletedCount = 0;

      for (const messageId in messagesMap) {
        const message = messagesMap[messageId];
        const timestamp = message?.timestamp as number;
        const delivered = message?.delivered;
        const read = message?.read;

        // Only delete if BOTH delivered AND read AND older than 5 minutes
        // This allows users to delete unread/undelivered messages for everyone
        if (delivered === true && read === true && timestamp && timestamp < fiveMinutesAgo) {
          try {
            await this.fb
              .database()
              .ref(`messages/${messageId}`)
              .remove();
            deletedCount++;

            console.log('Deleted old read message', {
              messageId,
              age: Math.round((Date.now() - timestamp) / 1000 / 60) + 'min',
            });
          } catch (e) {
            console.error(
              `Failed to delete message ${messageId}:`,
              e,
            );
          }
        }
      }

      console.log('Cleanup completed', {
        deletedCount,
        cutoffTime: new Date(fiveMinutesAgo).toISOString(),
      });
    } catch (e) {
      console.error('Failed to cleanup old delivered messages:', e);
    }
  }
}
