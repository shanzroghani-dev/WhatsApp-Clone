import { Module } from '@nestjs/common';
import { FirebaseAdminModule } from './firebase/firebase-admin.module';
import { NotificationsModule } from './notifications/notifications.module';
import { MessagesModule } from './messages/messages.module';
import { CallsModule } from './calls/calls.module';

@Module({
  imports: [FirebaseAdminModule, NotificationsModule, MessagesModule, CallsModule],
})
export class AppModule {}
