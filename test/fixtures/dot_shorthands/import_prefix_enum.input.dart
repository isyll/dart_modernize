import 'prefixed_lib.dart' as ph;

enum PermissionResult { granted, limited, denied }

PermissionResult mapStatus(ph.PermissionStatus status) {
  return switch (status) {
    ph.PermissionStatus.granted => PermissionResult.granted,
    ph.PermissionStatus.limited => PermissionResult.limited,
    ph.PermissionStatus.denied => PermissionResult.denied,
  };
}

ph.PermissionStatus defaultStatus() => ph.PermissionStatus.granted;
