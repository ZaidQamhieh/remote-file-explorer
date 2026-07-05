import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// AppSettingsScreen widget tests — the global "general settings" surface that
// edits the app-wide view defaults via settingsProvider.
// (Tests relocated to task-specific screens; this file is deprecated as of Task 6)

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

}
