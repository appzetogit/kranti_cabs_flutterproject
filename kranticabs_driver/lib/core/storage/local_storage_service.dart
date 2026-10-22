import 'package:hive_flutter/hive_flutter.dart';
import '../constants/storage_keys.dart';

class LocalStorageService {
  late Box emergencyContacts;
  late Box settings;
  late Box recentTrips;
  late Box vehicleMarkerCache;

  Future<void> init() async {
    await Hive.initFlutter();
    emergencyContacts = await Hive.openBox(StorageKeys.emergencyContactsBox);
    settings = await Hive.openBox(StorageKeys.settingsBox);
    recentTrips = await Hive.openBox(StorageKeys.recentTripsBox);
    vehicleMarkerCache = await Hive.openBox(StorageKeys.vehicleMarkerCacheBox);
  }
}
