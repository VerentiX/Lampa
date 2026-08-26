import 'package:flutter/foundation.dart';

enum LampaDownloadKind { app, geo }

class LampaDownloadJob {
  const LampaDownloadJob({
    required this.kind,
    required this.label,
    this.received = 0,
    this.total,
  });

  final LampaDownloadKind kind;
  final String label;
  final int received;
  final int? total;

  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }

  int? get percent {
    final f = fraction;
    if (f == null) return null;
    return (f * 100).round().clamp(0, 100);
  }
}

/// In-flight Lampa downloads (app APK / geo `.srs`) for the home badge.
class LampaDownloadProgress extends ChangeNotifier {
  LampaDownloadProgress._();
  static final LampaDownloadProgress I = LampaDownloadProgress._();

  final Map<LampaDownloadKind, LampaDownloadJob> _jobs = {};

  List<LampaDownloadJob> get jobs => _jobs.values.toList(growable: false);

  bool get active => _jobs.isNotEmpty;

  bool isKindActive(LampaDownloadKind kind) => _jobs.containsKey(kind);

  double? get overallFraction {
    if (_jobs.isEmpty) return null;
    final known = _jobs.values.where((j) => j.fraction != null).toList();
    if (known.isEmpty) return null;
    final sum = known.fold<double>(0, (a, j) => a + j.fraction!);
    return sum / known.length;
  }

  void start({
    required LampaDownloadKind kind,
    required String label,
    int? total,
  }) {
    _jobs[kind] = LampaDownloadJob(kind: kind, label: label, total: total);
    notifyListeners();
  }

  void update({
    required LampaDownloadKind kind,
    int? received,
    int? total,
    String? label,
  }) {
    final prev = _jobs[kind];
    if (prev == null) return;
    _jobs[kind] = LampaDownloadJob(
      kind: kind,
      label: label ?? prev.label,
      received: received ?? prev.received,
      total: total ?? prev.total,
    );
    notifyListeners();
  }

  void finish(LampaDownloadKind kind) {
    if (_jobs.remove(kind) == null) return;
    notifyListeners();
  }
}
