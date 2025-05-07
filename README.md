As Dart for server-side is on the rise, I started building this package in Dart today, A persistent job scheduler for postgresql.

Do you think you'll like to use this style of API ?

So it is quite simple
1. Create your PgWorker instance which takes your postgres connection and some config(optional)

2. You just have to start the PgWorker by calling `instance.start()`

3. Now, registering types are only required if you use Custom types when defining your jobs.

4. You just need to pass a job handler(function) of type JobHandler<T> job to handle/process your defined job, in my case 'send-emails'

5. At this point, I just defined a job with its handler so you need to schedule the job with the same name whenever you want to...

It takes a cron expression, the job you want to schedule, and an optional data.
The interesting thing about this is, it's fully persistent, restart your server and it still works.

Below is my example app I just wrote, it works for me.

```dart
class EmailData {
  String receiverEmail;
  String message;
  String subject;

  EmailData(this.receiverEmail, this.subject, this.message);

  factory EmailData.fromJson(Map<String, dynamic> json) => EmailData(
        json['receiverEmail'],
        json['subject'],
        json['message'],
      );
}

void main() async {
  final connection = PgConnection.url(
    'postgresql://admin@localhost:5432/admin?schema=public',
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  final pgWorker = PgWorker(
    connection,
    config: PgWorkerConfig(processEvery: Duration(seconds: 1), tableName: 'jobs'),
  );

  pgWorker.on('error', (error) {
    print(error);
  });

  await pgWorker.start();

  pgWorker.registerType<EmailData>(EmailData.fromJson);

  pgWorker.define<EmailData>('send-emails', (job) {
    print("sending email to ${job.data!.receiverEmail}");
  });

  // send email every 1 minutes
  pgWorker.schedule<EmailData>(
    '*/1 * * * *',
    'send-emails',
    data: EmailData('samuel@gmail.com', 'This is the subject', 'Hello World'),
  );
}
```
