import 'dart:async';

import 'package:pg_worker/pg_worker.dart';

enum JobStatus { queued, processing, completed, failed }

typedef JobHandler<T> = FutureOr<void> Function(Job<T> job);

class Job<T> {
  late String id;
  String jobName;
  String cron;
  DateTime? nextRunAt;
  DateTime? lastRunAt;
  late DateTime createdAt;
  T? data;
  late JobStatus status;
  int? priority;

  Job({
    String? id,
    required this.jobName,
    required this.cron,
    this.nextRunAt,
    this.lastRunAt,
    this.data,
    this.priority = 0,
    DateTime? createdAt,
    JobStatus? status,
  }) {
    this.id = id ?? Uuid().v4();
    this.createdAt = createdAt ?? DateTime.now();
    this.status = status ?? JobStatus.queued;
  }
}
