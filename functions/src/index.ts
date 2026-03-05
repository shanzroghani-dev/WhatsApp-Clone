import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { onValueCreated } from 'firebase-functions/v2/database';
import * as admin from 'firebase-admin';
import { AppModule } from './app.module';
import { MessagesTriggerService } from './messages/messages-trigger.service';

// Initialize Firebase Admin globally before anything else
if (!admin.apps.length) {
  admin.initializeApp();
}

let servicePromise: Promise<MessagesTriggerService> | null = null;

async function getService(): Promise<MessagesTriggerService> {
  if (!servicePromise) {
    servicePromise = NestFactory.createApplicationContext(AppModule).then((app) =>
      app.get(MessagesTriggerService),
    );
  }
  return servicePromise;
}

export const onChatMessageCreated = onValueCreated(
  {
    ref: 'messages/{receiverUid}/{messageId}',
    region: 'us-central1',
  },
  async (event) => {
    const service = await getService();
    await service.onMessageCreated(event);
  },
);

// Version 2.0 - Realtime Database trigger
