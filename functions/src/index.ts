import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { onValueCreated, onValueUpdated } from 'firebase-functions/v2/database';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import { AppModule } from './app.module';
import { MessagesTriggerService } from './messages/messages-trigger.service';
import { MessageReadTriggerService } from './messages/message-read-trigger.service';
import { MessagesCleanupService } from './messages/messages-cleanup.service';

// Initialize Firebase Admin globally before anything else
if (!admin.apps.length) {
  admin.initializeApp();
}

let messagesTriggerPromise: Promise<MessagesTriggerService> | null = null;
let messageReadTriggerPromise: Promise<MessageReadTriggerService> | null = null;
let cleanupServicePromise: Promise<MessagesCleanupService> | null = null;

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
