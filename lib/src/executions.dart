class Executions {
  static List<String> createJobsTable(String tableName) => [
        // Create table
        '''
      CREATE TABLE IF NOT EXISTS $tableName (
        id UUID PRIMARY KEY,
        job_name VARCHAR(128) NOT NULL,
        cron VARCHAR(128) NOT NULL,
        next_run_at TIMESTAMP WITH TIME ZONE,
        last_run_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE NOT NULL,
        data JSONB,
        status VARCHAR(32) NOT NULL,
        priority INTEGER DEFAULT 0,
        
        CONSTRAINT ${tableName}_status_check CHECK (status IN ('queued', 'processing', 'completed', 'failed'))
      )
    ''',

        // Create status and next_run index
        '''
      CREATE INDEX IF NOT EXISTS idx_${tableName}_status_next_run 
      ON $tableName (status, next_run_at) 
      WHERE status = 'queued'
    ''',

        // Create job name index
        '''
      CREATE INDEX IF NOT EXISTS idx_${tableName}_name 
      ON $tableName (job_name)
    '''
      ];

  static final insertJob = '''
      INSERT INTO jobs 
        (id, job_name, cron, next_run_at, created_at, data, status, priority)
      VALUES 
        (@id, @jobName, @cron, @nextRunAt, @createdAt, @data::jsonb, @status, @priority)
      '''
      .trim();

  static final nextRunJob = '''
      UPDATE jobs
      SET status = 'processing'
      WHERE id = (
        SELECT id
        FROM jobs
        WHERE status = 'queued'
          AND next_run_at <= NOW()
        ORDER BY priority DESC, next_run_at ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED
      )
      RETURNING *;
      '''
      .trim();

  static final updateJob = '''
              UPDATE jobs 
              SET 
                last_run_at = NOW(),
                next_run_at = @nextRun,
                status = 'queued'
              WHERE id = @id
              '''
      .trim();

  static final failJob = '''
              UPDATE jobs 
              SET status = 'failed'
              WHERE id = @id
              '''
      .trim();
}
