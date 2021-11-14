// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:cbl/cbl.dart';
import 'package:cbl_ffi/cbl_ffi.dart';
import 'package:cbl_flutter/cbl_flutter.dart';
import 'package:cbl_flutter_ce/cbl_flutter_ce.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() {
  return SentryFlutter.init(
    (options) {
      options.dsn =
          'https://b4ea9f398704486ea870ba823d4bcd29@o1067908.ingest.sentry.io/6061985';
      options.tracesSampleRate = 1.0;

      if (Platform.isAndroid) {
        // Because the CBL log breadcrumbs for the native Sentry SDK include all
        // log levels, from error to verbose, maxBreadcrumbs should be increased
        // from the default of 100 to capture enough breadcrumbs to be useful.
        options.maxBreadcrumbs = 500;
      }
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();

      CblFlutterCe.registerWith();
      await CouchbaseLiteFlutter.init();

      // Logs breadcrumbs to the Dart/Flutter Sentry SDK. In case of an
      // unhandled Dart exception in the Flutter app, the breadcrumbs will be
      // attached to the event.
      Database.log.custom = SentryLogger()..level = LogLevel.verbose;

      if (Platform.isAndroid) {
        // Logs breadcrumbs to the Sentry Native SDK. In case of a crash in
        // native code, the breadcrumbs will be attached to the event.
        // Only works for Android, currently.
        if (CBLBindings.instance.logging.setSentryBreadcrumbs(enabled: true)) {
          print('CBL log breadcrumbs for native Sentry SDK enabled');
        } else {
          Sentry.captureMessage(
            'Could not enable CBL log breadcrumbs for the native Sentry SDK',
            level: SentryLevel.warning,
          );
        }
      }

      runApp(const App());
    },
  );
}

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Container(
          padding: const EdgeInsets.all(16),
          child: const ButtonBar(
            children: [
              ElevatedButton(
                onPressed: startWork,
                child: Text('Start work'),
              ),
              ElevatedButton(
                onPressed: throwDartException,
                child: Text('Throw dart exception'),
              ),
              ElevatedButton(
                onPressed: causeNativeCrash,
                child: Text('Cause native crash'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

void throwDartException() {
  throw Exception('This is a Dart exception');
}

final proc = DynamicLibrary.process();
final abort = proc.lookupFunction<Void Function(), void Function()>('abort');

void causeNativeCrash() {
  abort();
}

void startWork() async {
  final db = await Database.openAsync('test');

  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    await db.saveDocument(MutableDocument());
  }
}

class SentryLogger extends Logger {
  @override
  void log(LogLevel level, LogDomain domain, String message) {
    print(message);
    Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      type: 'debug',
      level: level.sentryLevel,
      category: domain.sentryCategory,
    ));
  }
}

extension on LogDomain {
  String get sentryCategory {
    switch (this) {
      case LogDomain.database:
        return 'cbl.db';
      case LogDomain.query:
        return 'cbl.query';
      case LogDomain.replicator:
        return 'cbl.sync';
      case LogDomain.network:
        return 'cbl.ws';
    }
  }
}

extension on LogLevel {
  SentryLevel get sentryLevel {
    switch (this) {
      case LogLevel.debug:
      case LogLevel.verbose:
        return SentryLevel.debug;
      case LogLevel.info:
        return SentryLevel.info;
      case LogLevel.warning:
        return SentryLevel.warning;
      case LogLevel.error:
        return SentryLevel.error;
      case LogLevel.none:
        throw UnimplementedError();
    }
  }
}
