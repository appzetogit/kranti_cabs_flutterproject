import 'package:hive_flutter/hive_flutter.dart';
import '../constants/storage_keys.dart';

class LocalStorageService {
  late Box recentSearches;
  late Box savedAddresses;
  late Box emergencyContacts;
  late Box favoriteDrivers;
  late Box settings;
  late Box apiCache;

  Future<void> init() async {
    await Hive.initFlutter();
    recentSearches = await Hive.openBox(StorageKeys.recentSearchesBox);
    savedAddresses = await Hive.openBox(StorageKeys.savedAddressesBox);
    emergencyContacts = await Hive.openBox(StorageKeys.emergencyContactsBox);
    favoriteDrivers = await Hive.openBox(StorageKeys.favoriteDriversBox);
    settings = await Hive.openBox(StorageKeys.settingsBox);
    apiCache = await Hive.openBox(StorageKeys.apiCacheBox);
  }
}
