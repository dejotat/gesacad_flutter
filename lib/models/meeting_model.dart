/// Reunión virtual de un curso (CU-09).
class Meeting {
  const Meeting({
    required this.id,
    required this.courseId,
    required this.teacherName,
    required this.title,
    required this.provider,
    required this.url,
    required this.scheduledAt,
    required this.isLive,
  });

  final int id;
  final int courseId;
  final String teacherName;
  final String title;

  /// `jitsi` (sala automática), `meet`, `zoom` o `teams`.
  final String provider;
  final String url;

  /// Hora programada en hora local, o `null` si se inició al momento.
  final DateTime? scheduledAt;

  /// `true` si ya se puede entrar; `false` si está programada para más tarde.
  final bool isLive;

  String get providerName => switch (provider) {
        'meet' => 'Google Meet',
        'zoom' => 'Zoom',
        'teams' => 'Microsoft Teams',
        _ => 'Jitsi Meet',
      };

  factory Meeting.fromJson(Map<String, dynamic> j) => Meeting(
        id: j['id'] as int,
        courseId: j['courseId'] as int,
        teacherName: j['teacherName']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Reunión de clase',
        provider: j['provider']?.toString() ?? 'jitsi',
        url: j['url']?.toString() ?? '',
        scheduledAt: j['scheduledAt'] == null
            ? null
            : DateTime.tryParse(j['scheduledAt'].toString())?.toLocal(),
        isLive: j['status'] != 'scheduled',
      );
}
