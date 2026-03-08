import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { onValueCreated, onValueUpdated } from 'firebase-functions/v2/database';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import { AppModule } from './app.module';
import { MessagesTriggerService } from './messages/messages-trigger.service';
import { MessageReadTriggerService } from './messages/message-read-trigger.service';
import { MessagesCleanupService } from './messages/messages-cleanup.service';
import { CallTriggerService } from './calls/call-trigger.service';
import { generateAgoraToken, generateCallToken } from './agora/agora-token';

// Initialize Firebase Admin globally before anything else
if (!admin.apps.length) {
  admin.initializeApp();
}

let messagesTriggerPromise: Promise<MessagesTriggerService> | null = null;
let messageReadTriggerPromise: Promise<MessageReadTriggerService> | null = null;
let cleanupServicePromise: Promise<MessagesCleanupService> | null = null;
let callTriggerPromise: Promise<CallTriggerService> | null = null;

async function getMessagesTriggerService(): Promise<MessagesTriggerService> {
  if (!messagesTriggerPromise) {
    messagesTriggerPromise = NestFactory.createApplicationContext(AppModule).then((app) =>
      app.get(MessagesTriggerService),
    );
  }
  return messagesTriggerPromise;
}

async function getMessageReadTriggerService(): Promise<MessageReadTriggerService> {
  if (!messageReadTriggerPromise) {
    messageReadTriggerPromise = NestFactory.createApplicationContext(AppModule).then((app) =>
      app.get(MessageReadTriggerService),
    );
  }
  return messageReadTriggerPromise;
}

async function getCleanupService(): Promise<MessagesCleanupService> {
  if (!cleanupServicePromise) {
    cleanupServicePromise = NestFactory.createApplicationContext(AppModule).then((app) =>
      app.get(MessagesCleanupService),
    );
  }
  return cleanupServicePromise;
}

async function getCallTriggerService(): Promise<CallTriggerService> {
  if (!callTriggerPromise) {
    callTriggerPromise = NestFactory.createApplicationContext(AppModule).then((app) =>
      app.get(CallTriggerService),
    );
  }
  return callTriggerPromise;
}

export const onChatMessageCreated = onValueCreated(
  {
    ref: 'messages/{messageId}',
    region: 'us-central1',
  },
  async (event) => {
    const service = await getMessagesTriggerService();
    await service.onMessageCreated(event);
  },
);

// Trigger when a message is updated - delete it if marked as read
export const onMessageMarkAsRead = onValueUpdated(
  {
    ref: 'messages/{messageId}',
    region: 'us-central1',
  },
  async (event) => {
    const service = await getMessageReadTriggerService();
    await service.onMessageRead(event);
  },
);

// Scheduled cleanup - run every 5 minutes to delete old delivered messages
export const cleanupOldMessages = onSchedule(
  'every 5 minutes',
  async (context) => {
    console.log('Cleanup scheduled function triggered', {
      timestamp: new Date().toISOString(),
    });
    const service = await getCleanupService();
    await service.deleteOldDeliveredMessages();
  },
);

// Trigger when a call is created in Firestore - send push notification
export const onCallCreated = onDocumentCreated(
  {
    document: 'calls/{callId}',
    region: 'us-central1',
  },
  async (event) => {
    const service = await getCallTriggerService();
    await service.onCallCreated(event.data!);
  },
);

// Trigger when a call is updated in Firestore - handle status changes
export const onCallUpdated = onDocumentUpdated(
  {
    document: 'calls/{callId}',
    region: 'us-central1',
  },
  async (event) => {
    const service = await getCallTriggerService();
    await service.onCallUpdated(event.data!.before, event.data!.after);
  },
);

// Export Agora token generation functions
export { generateAgoraToken, generateCallToken };
