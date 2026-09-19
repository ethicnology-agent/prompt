class PermissionModeChoice {
  const PermissionModeChoice({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;
}
