import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { MessagesTriggerService } from './messages-trigger.service';
import { MessagesCleanupService } from './messages-cleanup.service';
import { MessageReadTriggerService } from './message-read-trigger.service';
import { FirebaseAdminModule } from '../firebase/firebase-admin.module';

@Module({
  imports: [NotificationsModule, FirebaseAdminModule],
  providers: [MessagesTriggerService, MessagesCleanupService, MessageReadTriggerService],
  exports: [MessagesTriggerService, MessagesCleanupService, MessageReadTriggerService],
})
export class MessagesModule {}
