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
