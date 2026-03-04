import 'package:flutter/material.dart';
import 'package:whatsapp_clone/models/user_model.dart';
import 'package:whatsapp_clone/screens/chat/chat_state.dart';

class ChatScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserModel peer;

  const ChatScreen({super.key, required this.currentUser, required this.peer});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}
