import { Injectable } from '@nestjs/common';
import { FirebaseAdminService } from '../firebase/firebase-admin.service';

@Injectable()
export class NotificationsService {
  constructor(private readonly fb: FirebaseAdminService) {}

  async sendToToken(params: {
    receiverFcmToken: string;
    receiverUid: string;
    senderUid: string;
    chatId: string;
    messageId: string;
    title: string;
    body: string;
    cipher?: string;
    iv?: string;
    messageType?: string;
  }): Promise<void> {
    const token = params.receiverFcmToken.trim();
    if (token.length === 0) return;

    try {
      const data: Record<string, string> = {
        type: params.messageType ?? 'chat_message',
        chatId: params.chatId,
        messageId: params.messageId,
        senderUID: params.senderUid,
        receiverUID: params.receiverUid,
        title: params.title,
        body: params.body,
      };

      // Include encrypted data if available
      if (params.cipher && params.iv) {
        data.cipher = params.cipher;
        data.iv = params.iv;
        console.log('FCM data includes encryption:', {
          cipherLen: params.cipher.length,
          ivLen: params.iv.length,
        });
      } else {
        console.log('FCM data - no encryption:', {
          hasCipher: !!params.cipher,
          hasIv: !!params.iv,
        });
      }

      const firebaseMessageId = await this.fb.messaging().send({
        token,
        notification: {
          title: params.title,
          body: params.body,
        },
        data,
        android: { priority: 'high' },
        apns: { headers: { 'apns-priority': '10' } },
      });

      console.log('sendToToken success', {
        receiverUid: params.receiverUid,
        messageId: params.messageId,
        firebaseMessageId,
      });
    } catch (e: any) {
      const code = e?.errorInfo?.code ?? e?.code ?? 'unknown';
      console.error('sendToToken failed', {
        code,
        receiverUid: params.receiverUid,
        messageId: params.messageId,
      });

      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        try {
          await this.fb
            .firestore()
            .collection('users')
            .doc(params.receiverUid)
            .update({ fcmToken: '' });
        } catch (_) {}
      }

      throw e;
    }
  }
}
