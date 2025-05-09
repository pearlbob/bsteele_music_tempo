import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';

// import 'package:bsteele_bass_common/low_pass_filter.dart';
import 'package:bsteele_music_lib/songs/song_tempo_update.dart';
import 'package:bsteele_music_lib/songs/song_update.dart';
import 'package:bsteele_music_lib/util/song_update_service.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:bsteele_music_tempo/process_tempo.dart';
import 'package:bsteele_music_tempo/utc_date.dart';
import 'package:logger/logger.dart';

const String version = '0.0.1';
String host = 'cj.local';
bool verbose = false;
bool veryVerbose = false;
bool isWebsocket = true;
bool isWebsocketFeedback = true;

SongUpdateService songUpdateService = SongUpdateService();
late ProcessTempo processTempo;
// LowPassFilter400Hz _lowPass400 = LowPassFilter400Hz();
AudioConfiguration audioConfiguration = AudioConfiguration(2);

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      // abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addOption('host', valueHelp: 'hostUrl', help: 'Select the host server by name.')
    ..addFlag('noWebsocketFeedback', abbr: 'w', negatable: false, help: 'Turn the websocket feedback off back to host.')
    ..addFlag('nowebsocket', abbr: 'W', negatable: false, help: 'Turn the websocket interface off.')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Show verbose command output.')
    ..addFlag('veryVerbose', abbr: 'V', negatable: false, help: 'Show very verbose command output.')
    ..addFlag('version', negatable: false, help: 'Print the tool version.');
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

    // Process the parsed arguments.
    if (results.wasParsed('help')) {
      printUsage(argParser);
      return;
    }
    if (results.wasParsed('noWebsocketFeedback')) {
      isWebsocketFeedback = false;
    }
    if (results.wasParsed('nowebsocket')) {
      isWebsocket = false;
    }
    if (results.wasParsed('version')) {
      print('bsteele_music_tempo version: $version');
      return;
    }
    if (results.wasParsed('verbose')) {
      verbose = true;
    }
    if (results.wasParsed('veryVerbose')) {
      verbose = true;
      veryVerbose = true;
    }

    host = results.option('host') ?? 'cj.local';
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
    return;
  }

  if (verbose) {
    print(
      'isWebsocket: $isWebsocket, isWebsocketFeedback: $isWebsocketFeedback'
      ', verbose: $verbose, veryVerbose: $veryVerbose',
    );
  }

  //  show compile date
  print('release date: ${releaseUtcDate()} UTC');

  // setup the web socket
  if (isWebsocket) {
    try {
      print('fixme: does not do well if web socket host not found!');

      SongUpdateService.open();
      songUpdateService.user = 'tempo';
      songUpdateService.callback = webSocketCallback;
      songUpdateService.host = host;

      print('songUpdateService.host: "${songUpdateService.host}"');

      await runARecord();
    } on Exception catch (e) {
      // Anything else that is an exception
      print('Unknown exception: $e');
    } catch (e, stackTrace) {
      print('web socket catch: $e');
      print('web socket trace: $stackTrace');
    }
  } else {
    await runARecord();
  }
}

Future<void> runARecord() async {
  //  find the target device
  String deviceName = '';
  var format = 'S16_LE';
  var bitDepthBytes = 2;

  //  loop forever, looking for hardware
  for (;;) {
    await Process.run('arecord', ['-l']).then((value) {
      for (var s in value.stdout.toString().split('\n')) {
        var m = _cardLineRegExp.firstMatch(s);
        if (m != null) {
          assert(m.groupCount == 2);
          print('Plugable USB Audio found:');
          deviceName = 'hw:${m.group(1)},${m.group(2)}';
          //  give the scarlett solo preference without a break; here
        }
        m = _scarlettSoloRegExp.firstMatch(s);
        if (m != null) {
          assert(m.groupCount == 2);
          print('Scarlett Solo found:');
          deviceName = 'hw:${m.group(1)},${m.group(2)}';
          format = 'S32_LE'; //  required
          bitDepthBytes = 4;
          break;
        }
      }
    });

    if (deviceName.isNotEmpty) {
      if (verbose) print('deviceName: "$deviceName"');
      break; //  hardware found
    }

    print('Error: hardware interface not found!  looking for Scarlett Solo');
    sleep(Duration(seconds: 60));
  }

  audioConfiguration = AudioConfiguration(bitDepthBytes);

  //  listen to the device audio
  List<String> arecordCommandArgs = [
    '-v',
    '-c$channels',
    '-r',
    sampleRate.toString(),
    '-f',
    format,
    '-t',
    'raw',
    //  the two below don't work for bob linux box
    '-D',
    deviceName,
  ];
  if (verbose) {
    print('arecord ${arecordCommandArgs.toString().replaceAll(RegExp(r'[\[\]]'), '').replaceAll(RegExp(r', '), ' ')}');
  }
  var process = await Process.start(
    //  arecord -v -c2 -r 48000 -f S16_LE -t raw -D hw:2,0
    'arecord',
    arecordCommandArgs,
  );

  final StreamController<List<int>> streamController = StreamController();
  processTempo = ProcessTempo();
  processTempo.callback = processTempoCallback;
  processTempo.verbose = verbose;
  processTempo.veryVerbose = veryVerbose;
  streamController.stream.listen((data) {
    var bytes = Uint8List.fromList(data);
    var byteData = bytes.buffer.asByteData();
    // if (veryVerbose) print('heard ${data.length} bytes');
    for (
      int i = 0;
      i < data.length;
      i += bitDepthBytes * channels //  bytes per frame
    ) {
      //  add signals in case only one of the stereo channels is active
      int value = 0;
      switch (audioConfiguration.bitDepthBytes) {
        case 2:
          for (var channel = 0; channel < channels; channel++) {
            value += byteData.getInt16(i + channel * bitDepthBytes, Endian.little);
          }
          break;
        case 4:
          for (var channel = 0; channel < channels; channel++) {
            value += byteData.getInt32(i + channel * bitDepthBytes, Endian.little);
          }
          break;
        default:
          print('bad bitDepthBytes: ${audioConfiguration.bitDepthBytes}');
          exit(-1);
      }
      //print(value); //  way temp

      //  filter out noise
      // value = _lowPass400.process(value.toDouble()).toInt();

      processTempo.processNewTempo(value);
    }
  }, cancelOnError: false);
  process.stdout.pipe(streamController);
}

processTempoCallback() {
  // print('processTempoCallback():');
  if (processTempo.bestBpm != _bpm || processTempo.tapsPerMeasure != _tpm) {
    _bpm = processTempo.bestBpm;
    _tpm = processTempo.tapsPerMeasure;
    if (_songTempoUpdate != null) {
      var songTempoUpdate = SongTempoUpdate(_songTempoUpdate!.songId, _bpm, processTempo.maxAmp);
      if (isWebsocketFeedback) {
        try {
          songUpdateService.issueSongTempoUpdate(songTempoUpdate);
          if (veryVerbose) print(songTempoUpdate.toString());
        } catch (e) {
          print('tempo update caught: $e');
        }
      }
      if (verbose) {
        print(
          '${DateTime.now()}: bestBpm: ${processTempo.bestBpm}'
          ' @ ${audioConfiguration.debugAmp(processTempo.instateMaxAmp)}'
          ', tpm: ${processTempo.tapsPerMeasure}/${processTempo.beatsPerMeasure}',
        );
      }
    }
  }
}

///
void webSocketCallback(final SongUpdate songUpdate) {
  if (veryVerbose) {
    print('webSocketCallback: $songUpdate, bpm: ${songUpdate.currentBeatsPerMinute}');
  }
  //print('webSocketCallback: title: "${songUpdate.song.title}", beatsPerMinute: ${songUpdate.song.beatsPerMinute}');

  processTempo.expectedBpm = songUpdate.currentBeatsPerMinute;

  //  induce a call back to the server on a song change
  _bpm = 0;
  _tpm = 0;

  processTempo.beatsPerMeasure = songUpdate.song.beatsPerBar;
  _songTempoUpdate = SongTempoUpdate(songUpdate.song.songId, songUpdate.currentBeatsPerMinute, processTempo.maxAmp);
}

SongTempoUpdate? _songTempoUpdate;
int _bpm = 0;
int _tpm = 0; //  taps per measure as read
const _targetDevice = 'Plugable USB Audio Device'; //  known misspelling
final _cardLineRegExp = RegExp(
  r'^card\s+([0-9]+):\s+\w+\s+\['
  '$_targetDevice'
  r'\],\s+device\s+([0-9]+):',
); //
final _scarlettSoloRegExp = RegExp(
  r'^card\s+([0-9]+):\s+\w+\s+\['
  'Scarlett Solo.*'
  r'\],\s+device\s+([0-9]+):',
); //
