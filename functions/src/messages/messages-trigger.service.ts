import { Injectable } from '@nestjs/common';
import { DatabaseEvent } from 'firebase-functions/v2/database';
import { NotificationsService } from '../notifications/notifications.service';
import { FirebaseAdminService } from '../firebase/firebase-admin.service';

@Injectable()
export class MessagesTriggerService {
  constructor(
    private readonly notifications: NotificationsService,
    private readonly fb: FirebaseAdminService,
  ) {}

  async onMessageCreated(
    event: DatabaseEvent<unknown>,
  ): Promise<void> {
    const snapshot = event.data as any;
    const data = snapshot.val();
    if (!data || typeof data !== 'object') return;

    const messageData = data as Record<string, unknown>;
    const messageId = String(event.params.messageId ?? '');
    const receiverUidFromPath = String(event.params.receiverUid ?? '');

    console.log('onMessageCreated triggered', {
      messageId,
      receiverUidFromPath,
      hasPayload: !!messageData,
    });

    // Extract sender and receiver UIDs from message data
    const senderUid = this.pick(messageData, [
      'senderUID',
      'senderUid',
      'fromId',
      'senderId',
    ]);
    const receiverUid = this.pick(messageData, [
      'toId',
      'receiverUid',
      'receiverId',
    ]) ?? receiverUidFromPath;

    if (!senderUid || !receiverUid || senderUid === receiverUid) {
      console.log('onMessageCreated skipped', {
        messageId,
        senderUid,
        receiverUid,
        reason: 'invalid sender/receiver',
      });
      return;
    }

    // Prefer token from message payload to avoid extra Firestore reads.
    // Only fallback to Firestore when missing or invalid.
    let receiverFcmToken = this.pick(messageData, [
      'receiverFcmToken',
      'toFcmToken',
      'receiverToken',
      'fcmToken',
    ]);
    let senderName = this.pick(messageData, ['senderName', 'displayName']);

    // Fetch sender profile only if we need display name.
    if (!senderName) {
      const senderDoc = await this.fb
        .firestore()
        .collection('users')
        .doc(senderUid)
        .get();
      const senderData = senderDoc.exists ? senderDoc.data() : null;
      senderName = (senderData?.displayName as string) ?? 'New message';
    }

    // If payload token is missing, fetch once from Firestore.
    if (!receiverFcmToken || receiverFcmToken.trim().length === 0) {
      const receiverDoc = await this.fb
        .firestore()
        .collection('users')
        .doc(receiverUid)
        .get();
      const receiverData = receiverDoc.exists ? receiverDoc.data() : null;
      receiverFcmToken = (receiverData?.fcmToken as string | undefined) ?? null;
    }

    if (!receiverFcmToken || receiverFcmToken.trim().length === 0) {
      console.log('FCM skipped: no receiver token', {
        messageId,
        senderUid,
        receiverUid,
      });
      return;
    }

    const type = this.pick(messageData, ['type']) ?? 'text';
    const text = this.pick(messageData, ['text', 'message', 'content']);
    // For encrypted messages, 'text' field contains the cipher
    const cipher = this.pick(messageData, ['cipher']) ?? text;
    const iv = this.pick(messageData, ['iv']);

    console.log('Message encryption data extraction', {
      messageId,
      hasText: !!text,
      text: text?.substring(0, 30),
      hasCipher: !!cipher,
      cipher: cipher ? cipher.substring(0, 20) + '...' : null,
      hasIv: !!iv,
      iv: iv ? iv.substring(0, 20) + '...' : null,
      allDataKeys: Object.keys(messageData),
    });

    const body =
      type === 'image'
        ? '📷 Photo'
        : type === 'video'
        ? '🎥 Video'
        : type === 'voice'
        ? '🎤 Voice message'
        : (text ?? 'You have a new message');

    try {
      console.log('Attempting FCM send', {
        messageId,
        senderUid,
        receiverUid,
        tokenPreview: `${receiverFcmToken.substring(0, 12)}...`,
      });

      await this.notifications.sendToToken({
        receiverFcmToken,
        receiverUid,
        senderUid,
        chatId: receiverUid,
        messageId,
        title: senderName,
        body,
        cipher: cipher ?? undefined,
        iv: iv ?? undefined,
        messageType: type,
      });

      console.log('FCM send success', {
        messageId,
        senderUid,
        receiverUid,
      });
    } catch (e) {
      const errorCode = this.getErrorCode(e);
      const retryWithFreshToken =
        errorCode === 'messaging/registration-token-not-registered' ||
        errorCode === 'messaging/invalid-registration-token';

      if (!retryWithFreshToken) {
        console.error('FCM send failed', {
          senderUid,
          receiverUid,
          messageId,
          errorCode,
          error: e instanceof Error ? e.message : String(e),
        });
        throw e;
      }

      // Token appears stale/invalid: fetch latest once and retry once.
      const receiverDoc = await this.fb
        .firestore()
        .collection('users')
        .doc(receiverUid)
        .get();
      const receiverData = receiverDoc.exists ? receiverDoc.data() : null;
      const latestToken = (receiverData?.fcmToken as string | undefined) ?? null;

      if (!latestToken || latestToken.trim().length === 0 || latestToken === receiverFcmToken) {
        console.error('FCM retry skipped - no newer token', {
          senderUid,
          receiverUid,
          messageId,
          errorCode,
        });
        throw e;
      }

      console.log('Retrying FCM with fresh token', {
        messageId,
        senderUid,
        receiverUid,
      });

      await this.notifications.sendToToken({
        receiverFcmToken: latestToken,
        receiverUid,
        senderUid,
        chatId: receiverUid,
        messageId,
        title: senderName,
        body,
        cipher: cipher ?? undefined,
        iv: iv ?? undefined,
        messageType: type,
      });

      console.log('FCM retry success', {
        messageId,
        senderUid,
        receiverUid,
      });
    }

    // Mark message as delivered after notification is sent
    try {
      // Mark delivered in both receiver's incoming path and sender's sent messages path
      await Promise.all([
        this.fb
          .database()
          .ref(`messages/${receiverUid}/${messageId}/delivered`)
          .set(true),
        this.fb
          .database()
          .ref(`sentMessages/${senderUid}/${receiverUid}/${messageId}/delivered`)
          .set(true),
      ]);

      console.log('Delivered status updated', {
        messageId,
        senderUid,
        receiverUid,
      });
    } catch (e) {
      console.error('Failed to mark message as delivered:', e);
    }
  }

  private pick(data: Record<string, unknown>, keys: string[]): string | null {
    for (const key of keys) {
      const value = data[key];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value;
      }
    }
    return null;
  }

  private getErrorCode(error: unknown): string | null {
    if (!error || typeof error !== 'object') return null;
    const withCode = error as { code?: unknown; errorInfo?: { code?: unknown } };
    if (typeof withCode.errorInfo?.code === 'string') return withCode.errorInfo.code;
    if (typeof withCode.code === 'string') return withCode.code;
    return null;
  }
}
