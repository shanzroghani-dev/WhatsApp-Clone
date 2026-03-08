import { Injectable } from '@nestjs/common';
import * as admin from 'firebase-admin';

interface CallData {
  callId: string;
  initiatorId: string;
  initiatorName: string;
  initiatorProfilePic: string;
  receiverId: string;
  receiverName: string;
  receiverProfilePic: string;
  callType: 'voice' | 'video';
  status: string;
  initiatedAt: number;
  agoraToken?: string;
  agoraChannel?: string;
}

@Injectable()
export class CallNotificationService {
  private readonly firestore = admin.firestore();
  private readonly messaging = admin.messaging();

  async sendCallNotification(callData: CallData): Promise<void> {
    try {
      console.log(`[CallNotification] Sending notification for call ${callData.callId}`);

      // Get receiver's FCM token from Firestore
      const userDoc = await this.firestore
        .collection('users')
        .doc(callData.receiverId)
        .get();

      if (!userDoc.exists) {
        console.log(`[CallNotification] User ${callData.receiverId} not found`);
        return;
      }

      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken;

      if (!fcmToken) {
        console.log(`[CallNotification] No FCM token for user ${callData.receiverId}`);
        return;
      }

      // Prepare notification payload
      const callTypeLabel = callData.callType === 'video' ? 'Video' : 'Voice';
      
      const notification: admin.messaging.Message = {
        token: fcmToken,
        notification: {
          title: `Incoming ${callTypeLabel} Call`,
          body: `${callData.initiatorName} is calling...`,
        },
        data: {
          type: 'incoming_call',
          callId: callData.callId,
          initiatorId: callData.initiatorId,
          initiatorName: callData.initiatorName,
          initiatorProfilePic: callData.initiatorProfilePic,
          receiverId: callData.receiverId,
          receiverName: callData.receiverName,
          receiverProfilePic: callData.receiverProfilePic,
          callType: callData.callType,
          status: callData.status,
          initiatedAt: callData.initiatedAt.toString(),
          agoraToken: callData.agoraToken || '',
          agoraChannel: callData.agoraChannel || '',
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'calls',
            priority: 'high',
            defaultSound: true,
            defaultVibrateTimings: true,
            visibility: 'public',
            sound: 'default',
          },
          ttl: 30000, // 30 seconds TTL for call notifications
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-expiration': Math.floor(Date.now() / 1000 + 30).toString(),
          },
          payload: {
            aps: {
              alert: {
                title: `Incoming ${callTypeLabel} Call`,
                body: `${callData.initiatorName} is calling...`,
              },
              sound: 'default',
              category: 'CALL_INVITE',
              'thread-id': callData.callId,
              'interruption-level': 'time-sensitive',
            },
          },
        },
      };

      // Send the notification
      const response = await this.messaging.send(notification);
      console.log(
        `[CallNotification] Successfully sent notification for call ${callData.callId}:`,
        response,
      );
    } catch (error) {
      console.error(
        `[CallNotification] Error sending notification for call ${callData.callId}:`,
        error,
      );
      // Don't throw - call can still work via database listener
    }
  }

  async sendCallEndedNotification(
    callId: string,
    receiverId: string,
    reason: string,
  ): Promise<void> {
    try {
      console.log(`[CallNotification] Sending call ended notification for ${callId}`);

      // Get receiver's FCM token
      const userDoc = await this.firestore
        .collection('users')
        .doc(receiverId)
        .get();

      if (!userDoc.exists) return;

      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken;

      if (!fcmToken) return;

      // Send silent data message to dismiss notification
      await this.messaging.send({
        token: fcmToken,
        data: {
          type: 'call_ended',
          callId: callId,
          reason: reason,
        },
        android: {
          priority: 'high',
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
        },
      });

      console.log(`[CallNotification] Call ended notification sent for ${callId}`);
    } catch (error) {
      console.error(`[CallNotification] Error sending call ended notification:`, error);
    }
  }
}
