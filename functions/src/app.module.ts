import { Module } from '@nestjs/common';
import { FirebaseAdminModule } from './firebase/firebase-admin.module';
import { NotificationsModule } from './notifications/notifications.module';
import { MessagesModule } from './messages/messages.module';

@Module({
  imports: [FirebaseAdminModule, NotificationsModule, MessagesModule],
})
export class AppModule {}
