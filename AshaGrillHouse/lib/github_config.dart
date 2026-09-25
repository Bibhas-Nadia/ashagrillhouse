

import 'db_helper.dart';

class GithubConfig {
  // 1. Change 'const' to 'String' so they can be updated at runtime
  static String token='';
  static String username='';
  static String repo='';
  static String pin='123456';
  static String status='deactive';

  // 2. Remove 'this' from parameters and body (static methods don't use 'this')
  static Future<void> loadConfig() async {
    final config = await DBHelper.getConfig();

    if (config != null) {
      // 3. Update the global variables directly
      token = config['githubToken'] ?? token;
      username = config['githubUsername'] ?? username;
      repo = config['githubRepo'] ?? repo;
      pin = config['appPassword'] ?? pin;
      status = config['status'] ?? status;
      print("=================================================================================================");
      print("=================================================================================================");
      print("Config loaded successfully from DB in config file");
      print(token);
      print(username);
      print(repo);
      print(pin);
      print(status);
    }
  }
}
