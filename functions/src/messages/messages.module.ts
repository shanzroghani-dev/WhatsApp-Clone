import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { MessagesTriggerService } from './messages-trigger.service';

@Module({
  imports: [NotificationsModule],
  providers: [MessagesTriggerService],
  exports: [MessagesTriggerService],
})
export class MessagesModule {}
