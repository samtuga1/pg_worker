import 'dart:async';
import 'dart:convert';
import 'package:pg_worker/pg_worker.dart' hide Type;

class PgWorkerConfig {
  Duration? processEvery;
  String? tableName;

  PgWorkerConfig({
    this.processEvery,
    this.tableName = 'jobs',
  });
}

class PgWorker {
  PgWorker(this.pgConnection, {this.config})
      : _definitions = {},
        _fromJsonMap = {},
        _eventControllers = {};

  PgWorkerConfig? config;
  PgConnection pgConnection;
  late Connection connection;
  final Map<String, JobHandler> _definitions;
  final Map<Type, Function(Map<String, dynamic>)> _fromJsonMap;
  final Map<String, StreamController> _eventControllers;
  bool _isProcessing = false;

  //
  Timer? _processTimer;

  /// The maximum job priority.
  static const maxPriority = 32767;

  /// The minimum job priority.
  static const minPriority = -32768;

  Future<void> start() async {
    connection = await Connection.open(pgConnection.endpoint, settings: pgConnection.settings);

    // create jobs table if it does not exist
    await _createJobsTable(config?.tableName);

    _processJobs();

    _emit('started', this);

    print('Pg-Worker says Let\'s goooo 🚀');
  }

  void define<T>(String jobName, JobHandler<T> handler) {
    if (!T.isPrimitive) {
      if (!_fromJsonMap.containsKey(T)) {
        throw ArgumentError(
          'Type converter not found for type $T. '
          'Please register a converter using registerType<$T>() before defining jobs.',
        );
      }
    }

    _definitions[jobName] = (Job<dynamic> job) {
      try {
        final data = _fromJsonMap[T]!(job.data as Map<String, dynamic>);
        final typedJob = Job<T>(
          id: job.id,
          jobName: job.jobName,
          cron: job.cron,
          nextRunAt: job.nextRunAt,
          lastRunAt: job.lastRunAt,
          data: data,
          priority: job.priority,
        );

        return handler(typedJob);
      } catch (e) {
        throw ArgumentError('Job data type mismatch: $e');
      }
    };
  }

  void registerType<T>(T Function(Map<String, dynamic>) fromJson) {
    _fromJsonMap[T] = fromJson;
  }

  void _emit(String eventName, dynamic data) {
    if (_eventControllers.containsKey(eventName)) {
      _eventControllers[eventName]!.add(data);
    }
  }

  void on(String eventName, Function(dynamic data) callback) {
    _eventControllers.putIfAbsent(eventName, () => StreamController.broadcast());
    _eventControllers[eventName]!.stream.listen(callback);
  }

  Future<String> schedule<T>(
    String cron,
    String jobName, {
    T? data,
    int priority = 0,
  }) async {
    if (priority < minPriority || priority > maxPriority) {
      throw Exception('[MinPriority: $minPriority] and [MaxPriority: $maxPriority] constraints exceeded');
    }

    final existingJob = await fetchJobByName<T>(jobName);

    if (existingJob != null) return existingJob.id;

    // Create a new job instance
    final job = Job<T>(
      jobName: jobName,
      cron: cron,
      data: data,
      priority: priority,
    );

    final cronParser = UnixCronParser();

    final schedule = cronParser.parse(cron);
    job.nextRunAt = schedule.next().time;

    final jsonData = data != null ? json.encode(data, toEncodable: (_) => data.toJson()) : null;

    // Insert the job into the database
    await connection.execute(
      Sql.named(Executions.insertJob),
      parameters: {
        'id': job.id,
        'jobName': job.jobName,
        'cron': job.cron,
        'nextRunAt': job.nextRunAt?.toUtc(),
        'createdAt': job.createdAt.toUtc(),
        'data': jsonData,
        'status': job.status.name,
        'priority': job.priority,
      },
    );

    return job.id;
  }

  void _processJobs() {
    _processTimer = Timer.periodic(config?.processEvery ?? Duration(seconds: 1), (_) async {
      if (_isProcessing) return;

      _isProcessing = true;

      while (true) {
        final nextJob = await _fetchNextJob();

        if (nextJob != null) {
          try {
            final handler = _definitions[nextJob.jobName];

            if (handler == null) throw Exception('No handler defined for job: ${nextJob.jobName}');

            print('Executing job with id: ${nextJob.id} 🚀');
            await handler(nextJob);
            print('Finishing job execution 🔥');

            final cronParser = UnixCronParser();
            final schedule = cronParser.parse(nextJob.cron);
            final nextRun = schedule.next().time;

            await connection.execute(
              Sql.named(Executions.updateJob),
              parameters: {'id': nextJob.id, 'nextRun': nextRun.toUtc()},
            );
          } catch (error, st) {
            await connection.execute(
              Sql.named(Executions.failJob),
              parameters: {'id': nextJob.id},
            );

            _emit('error', error);

            print('Error processing job ${nextJob.id}: $error');
          } finally {
            _isProcessing = false;
          }
        }
      }
    });
  }

  Future<Job<T>?> fetchJobByName<T>(String jobName) async {
    final result = await connection.execute(
      Sql.named('SELECT id, job_name, cron, next_run_at, last_run_at, created_at, status, priority, data '
          'FROM jobs WHERE job_name = @jobName LIMIT 1'),
      parameters: {'jobName': jobName},
    );

    if (result.isEmpty) return null;

    return _getJobFromResult(result);
  }

  Future<Job?> _fetchNextJob() async {
    final result = await connection.execute(Executions.nextRunJob);

    if (result.isEmpty) return null;

    return _getJobFromResult(result);
  }

  Future<void> _createJobsTable(String? tableName) async {
    final statements = Executions.createJobsTable(tableName ?? 'jobs');

    for (final sql in statements) {
      await connection.execute(sql);
    }
  }

  Job<T> _getJobFromResult<T>(Result result) {
    final row = result.first.toColumnMap();

    dynamic data = row['data'];

    // Convert data if a converter is registered for type T
    if (data != null && _fromJsonMap.containsKey(T)) {
      data = _fromJsonMap[T]!(data as Map<String, dynamic>);
    }

    return Job<T>(
      id: row['id'],
      jobName: row['job_name'],
      cron: row['cron'],
      nextRunAt: row['next_run_at'],
      lastRunAt: row['last_run_at'],
      createdAt: row['created_at'],
      data: data as T?,
      status: JobStatus.values.byName(row['status']),
      priority: row['priority'],
    );
  }

  Future<void> stop() async {
    _processTimer?.cancel();
    await connection.close();
    for (final controller in _eventControllers.values) {
      controller.close();
    }
  }
}
