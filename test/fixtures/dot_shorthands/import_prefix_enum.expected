import 'prefixed_lib.dart' as ph;

enum PermissionResult { granted, limited, denied }

PermissionResult mapStatus(ph.PermissionStatus status) {
  return switch (status) {
    .granted => .granted,
    .limited => .limited,
    .denied => .denied,
  };
}

ph.PermissionStatus defaultStatus() => .granted;
