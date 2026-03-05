import { Injectable } from '@nestjs/common';
import * as admin from 'firebase-admin';

@Injectable()
export class FirebaseAdminService {
  // No need to initialize here, it's done globally in index.ts
  firestore() {
    return admin.firestore();
  }

  messaging() {
    return admin.messaging();
  }

  database() {
    return admin.database();
  }
}

