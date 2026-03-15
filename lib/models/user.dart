class AppUser {
  final String id;
  final String username;
  final String displayName;

  AppUser({
    required this.id,
    required this.username,
    required this.displayName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
  );
}
