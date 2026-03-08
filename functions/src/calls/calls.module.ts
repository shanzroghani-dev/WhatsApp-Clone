import { Module } from '@nestjs/common';
import { CallNotificationService } from './call-notification.service';
import { CallTriggerService } from './call-trigger.service';

@Module({
  providers: [CallNotificationService, CallTriggerService],
  exports: [CallTriggerService],
})
export class CallsModule {}
