enum AppFontPreference { bundled, system, imported }

class ImportedAppFont {
  const ImportedAppFont({required this.id, required this.name});

  final String id;
  final String name;

  static final _idPattern = RegExp(r'^[a-f0-9]{64}$');

  static bool isValidId(String id) => _idPattern.hasMatch(id);

  static ImportedAppFont? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || !isValidId(id) || name is! String || name.isEmpty) {
      return null;
    }
    return ImportedAppFont(id: id, name: name);
  }

  Map<String, String> toJson() => {'id': id, 'name': name};
}
