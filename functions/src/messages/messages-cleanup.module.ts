import { Module } from '@nestjs/common';
import { MessagesCleanupService } from './messages-cleanup.service';
import { FirebaseAdminModule } from '../firebase/firebase-admin.module';

@Module({
  imports: [FirebaseAdminModule],
  providers: [MessagesCleanupService],
  exports: [MessagesCleanupService],
})
export class MessagesCleanupModule {}
