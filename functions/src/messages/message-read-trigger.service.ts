import { Injectable } from '@nestjs/common';
import { FirebaseAdminService } from '../firebase/firebase-admin.service';

@Injectable()
export class MessageReadTriggerService {
  constructor(
    private readonly fb: FirebaseAdminService,
  ) {}

  async onMessageRead(event: any): Promise<void> {
    const snapshot = event.data as any;
    const data = snapshot.val();
    if (!data || typeof data !== 'object') return;

    const messageId = event.params.messageId;
    const read = data.read as boolean;

    console.log('Message marked as read', {
      messageId,
      read,
    });

    // For flat structure: just log the read status
    // The cleanupOldMessages scheduled function will handle deletion of old messages
    // We do NOT delete on read - we keep messages for the archive/history
  }
}
