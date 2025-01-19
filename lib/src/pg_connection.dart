import 'package:postgres/postgres.dart';

class PgConnection {
  late Endpoint endpoint;
  ConnectionSettings? settings;

  PgConnection(this.endpoint, {this.settings});

  PgConnection.url(String connUrl, {this.settings}) {
    final uri = Uri.parse(connUrl);

    if (uri.scheme != 'postgresql' && uri.scheme != 'postgres') {
      throw ArgumentError('Connection URL must use the "postgres" scheme.');
    }

    final host = uri.host;
    final database = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    final username = uri.userInfo.split(':').first;
    final password = uri.userInfo.split(':').length > 1 ? uri.userInfo.split(':')[1] : null;
    final port = uri.port == 0 ? 5432 : uri.port;

    endpoint = Endpoint(
      host: host,
      database: database,
      username: username,
      password: password,
      port: port,
    );
  }
}
