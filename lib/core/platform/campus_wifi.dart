abstract interface class CampusWifi {
  Future<String?> currentSsid({String? preferred});
  Future<String?> ipv4Address(String ssid);
  Future<void> connect(String ssid);
}

class CampusWifiException implements Exception {
  const CampusWifiException(this.message);

  final String message;
}
