import * as functions from 'firebase-functions';
import { RtcTokenBuilder, RtcRole } from 'agora-token';

const AGORA_APP_ID = '1c8f63330cd84646a45c26d3177d4c18';
const AGORA_APP_CERTIFICATE = '64f5551e619f43b59f7d2a4f41a131bb';
const TOKEN_EXPIRY = 3600; // 1 hour

interface TokenRequest {
  channelName: string;
  uid: number;
  role?: 'publisher' | 'subscriber';
}

/**
 * Generate Agora RTC token for real-time communication
 * Called by mobile app to get token before joining a call
 */
export const generateAgoraToken = functions.https.onCall(
  async (data: TokenRequest, context) => {
    // Verify user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated to generate Agora tokens'
      );
    }

    const { channelName, uid } = data;
    const role = data.role === 'subscriber' ? RtcRole.SUBSCRIBER : RtcRole.PUBLISHER;

    // Validate input
    if (!channelName || !uid) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'channelName and uid are required'
      );
    }

    if (typeof uid !== 'number' || uid < 0 || uid > 2147483647) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'uid must be a valid integer (0-2147483647)'
      );
    }

    try {
      // Generate token
      const token = RtcTokenBuilder.buildTokenWithUid(
        AGORA_APP_ID,
        AGORA_APP_CERTIFICATE,
        channelName,
        uid,
        role,
        Math.floor(Date.now() / 1000) + TOKEN_EXPIRY
      );

      console.log(
        `[Agora Token] Generated token for user ${context.auth.uid} on channel ${channelName}`
      );

      return {
        token,
        channelName,
        uid,
        expiry: TOKEN_EXPIRY,
      };
    } catch (error) {
      console.error('[Agora Token] Error generating token:', error);
      throw new functions.https.HttpsError(
        'internal',
        'Failed to generate Agora token: ' + (error as Error).message
      );
    }
  }
);

/**
 * Generate token for channel (used for call signaling)
 */
export const generateCallToken = functions.https.onCall(
  async (data: { callId: string; uid: number }, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const { callId, uid } = data;

    if (!callId || !uid) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'callId and uid are required'
      );
    }

    try {
      const token = RtcTokenBuilder.buildTokenWithUid(
        AGORA_APP_ID,
        AGORA_APP_CERTIFICATE,
        callId, // Use callId as channel name
        uid,
        RtcRole.PUBLISHER,
        Math.floor(Date.now() / 1000) + TOKEN_EXPIRY
      );

      console.log(
        `[Agora Token] Generated call token for user ${context.auth.uid} on call ${callId}`
      );

      return {
        token,
        channelName: callId,
        uid,
        expiry: TOKEN_EXPIRY,
      };
    } catch (error) {
      console.error('[Agora Token] Error generating call token:', error);
      throw new functions.https.HttpsError(
        'internal',
        'Failed to generate token'
      );
    }
  }
);
