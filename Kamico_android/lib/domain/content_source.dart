enum ContentSource {
  jm('jm', 'JM'),
  pic('pic', 'Pic');

  const ContentSource(this.id, this.label);
  final String id, label;
  static ContentSource parse(Object? value) => value == 'pic' ? pic : jm;

  // Preserve existing JM keys and paths. Remote IDs are never sent prefixed.
  String key(String remoteId) => this == jm ? remoteId : 'pic|$remoteId';
  String preference(String name) => this == jm ? name : 'pic_$name';
  String remoteId(String key) =>
      this == pic && key.startsWith('pic|') ? key.substring(4) : key;
}
