import { Injectable } from '@nestjs/common';
import { CallNotificationService } from './call-notification.service';

@Injectable()
export class CallTriggerService {
  constructor(private readonly callNotificationService: CallNotificationService) {}

  async onCallCreated(snapshot: FirebaseFirestore.DocumentSnapshot): Promise<void> {
    const callData = snapshot.data();

    if (!callData) {
      console.log('[CallTrigger] No call data found');
      return;
    }

    console.log(`[CallTrigger] New call created: ${snapshot.id}`);

    // Only send notification if call is in 'ringing' status
    if (callData.status === 'ringing') {
      await this.callNotificationService.sendCallNotification({
        callId: snapshot.id,
        initiatorId: callData.initiatorId,
        initiatorName: callData.initiatorName,
        initiatorProfilePic: callData.initiatorProfilePic,
        receiverId: callData.receiverId,
        receiverName: callData.receiverName,
        receiverProfilePic: callData.receiverProfilePic,
        callType: callData.callType,
        status: callData.status,
        initiatedAt: callData.initiatedAt,
        agoraToken: callData.agoraToken,
        agoraChannel: callData.agoraChannel,
      });
    }
  }

  async onCallUpdated(
    beforeSnapshot: FirebaseFirestore.DocumentSnapshot,
    afterSnapshot: FirebaseFirestore.DocumentSnapshot,
  ): Promise<void> {
    const beforeData = beforeSnapshot.data();
    const afterData = afterSnapshot.data();

    if (!beforeData || !afterData) return;

    const callId = afterSnapshot.id;
    console.log(`[CallTrigger] Call updated: ${callId}, status: ${afterData.status}`);

    // If call ended, send notification to dismiss
    if (beforeData.status !== 'ended' && afterData.status === 'ended') {
      await this.callNotificationService.sendCallEndedNotification(
        callId,
        afterData.receiverId,
        afterData.endReason || 'ended',
      );
    }

    // If call was rejected, notify initiator
    if (beforeData.status !== 'rejected' && afterData.status === 'rejected') {
      await this.callNotificationService.sendCallEndedNotification(
        callId,
        afterData.initiatorId,
        'rejected',
      );
    }
  }
}
