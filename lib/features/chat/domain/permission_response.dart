/// The three outcomes OpenCode accepts for a pending tool-call permission,
/// per `POST /session/{id}/permissions/{permissionID}`.
library;

enum PermissionResponse {
  /// Approve just this request.
  once,

  /// Approve future requests matching the patterns OpenCode suggests, for
  /// potentially across sessions in the same directory instance. The server
  /// controls rule retention; this must never be presented as session-only.
  always,

  /// Deny the request.
  reject,
}

extension PermissionResponseWireValue on PermissionResponse {
  /// The exact string OpenCode's REST API expects for this response.
  String get wireValue {
    return switch (this) {
      PermissionResponse.once => 'once',
      PermissionResponse.always => 'always',
      PermissionResponse.reject => 'reject',
    };
  }
}
