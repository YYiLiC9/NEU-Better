abstract interface class CampusWifi {
  Future<String?> currentSsid();
  Future<String?> ipv4Address(String ssid);
}

class CampusWifiException implements Exception {
  const CampusWifiException(this.message);

  final String message;
}

class CampusWifiPermissionRequired extends CampusWifiException {
  const CampusWifiPermissionRequired(super.message);
}
