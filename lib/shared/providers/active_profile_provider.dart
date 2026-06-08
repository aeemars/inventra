import 'package:flutter_riverpod/legacy.dart';
import '../../features/auth/domain/entities/user_profile.dart';

class ActiveProfileNotifier extends StateNotifier<UserProfile?> {
  ActiveProfileNotifier() : super(null);
  void setProfile(UserProfile p) => state = p;
  void clear() => state = null;
}

final activeProfileProvider =
    StateNotifierProvider<ActiveProfileNotifier, UserProfile?>(
  (_) => ActiveProfileNotifier(),
);
