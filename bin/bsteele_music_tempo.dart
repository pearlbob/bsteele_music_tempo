import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:bsteele_music_lib/songs/song_update.dart';
import 'package:bsteele_music_lib/util/song_update_service.dart';
import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:bsteele_music_tempo/process_tempo.dart';
import 'package:logger/logger.dart';

const String version = '0.0.1';
String host = 'cj.local';

SongUpdateService songUpdateService = SongUpdateService();
final ProcessTempo processTempo = ProcessTempo();

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      // abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addOption(
      'host',
      valueHelp: 'hostUrl',
      help: 'Select the host server by name.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag(
      'version',
      negatable: false,
      help: 'Print the tool version.',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart bsteele_music_tempo.dart <flags> [arguments]');
  print(argParser.usage);
}

void main(List<String> arguments) async {
  Logger.level = Level.info;

  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = false;

    // Process the parsed arguments.
    if (results.wasParsed('help')) {
      printUsage(argParser);
      return;
    }
    if (results.wasParsed('version')) {
      print('bsteele_music_tempo version: $version');
      return;
    }
    if (results.wasParsed('verbose')) {
      verbose = true;
    }

    // Act on the arguments provided.
    print('Positional arguments: ${results.rest}');
    if (verbose) {
      print('[VERBOSE] All arguments: ${results.arguments}');
    }

    host = results.option('host') ?? 'cj.local';
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
    return;
  }

  // setup the web socket
  SongUpdateService.open();
  songUpdateService.user = 'tempo';
  songUpdateService.callback = webSocketCallback; //  not required
  songUpdateService.host = host;

  logger.i('songUpdateService.host: "${songUpdateService.host}"');

  await runArecord();
}

Future<void> runArecord() async {
  //  find the target device
  String deviceName = '';
  await Process.run(
    'arecord',
    [
      '-l',
    ],
  ).then((value) {
    for (var s in value.stdout.toString().split('\n')) {
      var m = cardLineRegExp.firstMatch(s);
      if (m != null) {
        assert(m.groupCount == 2);
        deviceName = 'hw:${m.group(1)},${m.group(2)}';
        //print('$s  => "$deviceName"');
        break;
      }
    }
  });
  assert(deviceName.isNotEmpty);
  print(deviceName);

  //  listen to the device audio
  var process = await Process.start(
    //  arecord -v -c2 -r 48000 -f S16_LE -t raw -D hw:2,0
    'arecord',
    [
      '-v',
      '-c2',
      '-r',
      sampleRate.toString(),
      '-f',
      'S16_LE',
      '-t',
      'raw',
      '-D',
      deviceName,
    ],
  );

  final StreamController<List<int>> streamController = StreamController();
  processTempo.callback = processTempoCallback;
  streamController.stream.listen((data) {
    var bytes = Uint8List.fromList(data);
    for (int i = 0;
        i < data.length;
        i += 2 * 2 //  2 bytes per sample but only use one channel
        ) {
      processTempo.processTempo(bytes.buffer.asByteData().getInt16(i, Endian.little));
    }
  }, cancelOnError: false);
  process.stdout.pipe(streamController);
}

processTempoCallback() {
  if (processTempo.bpm != bpm) {
    bpm = processTempo.bpm;
    var songUpdate = SongUpdate(user: songUpdateService.user, currentBeatsPerMinute: bpm);
    songUpdateService.issueSongUpdate(songUpdate, force: true);
    logger.i('processTempoCallback: ${songUpdate.currentBeatsPerMinute}');
  }
}

/// not required for this feature
void webSocketCallback(SongUpdate songUpdate) {
  logger.i('webSocketCallback: $songUpdate');
}

int bpm = 0;
const targetDevice = 'Plugable USB Audio Device'; //  known misspelling
final cardLineRegExp = RegExp(r'^card\s+([0-9]+):\s+\w+\s+\['
    '$targetDevice'
    r'\],\s+device\s+([0-9]+):'); //
