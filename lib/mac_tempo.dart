import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:bsteele_bass_common/low_pass_filter.dart';
import 'package:bsteele_music_lib/songs/song_tempo_update.dart';
import 'package:bsteele_music_lib/songs/song_update.dart';
import 'package:bsteele_music_lib/util/song_update_service.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:bsteele_music_tempo/process_tempo.dart';
import 'package:logger/logger.dart';

const String version = '0.0.1';
String host = 'cj.local';
bool verbose = false;
bool veryVerbose = false;
bool isWebsocket = true;
bool isWebsocketFeedback = true;

SongUpdateService songUpdateService = SongUpdateService();
late ProcessTempo processTempo;
LowPassFilter400Hz _lowPass400 = LowPassFilter400Hz();
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

  if (verbose) print('isWebsocket: $isWebsocket');

  // setup the web socket
  if (isWebsocket) {
    try {
      print('fixme: does not do well if web socket host not found!');

      SongUpdateService.open();
      songUpdateService.user = 'tempo';
      songUpdateService.callback = webSocketCallback;
      songUpdateService.host = host;

      print('songUpdateService.host: "${songUpdateService.host}"');

      await runRec();
    } on Exception catch (e) {
      // Anything else that is an exception
      print('Unknown exception: $e');
    } catch (e, stackTrace) {
      print('web socket catch: $e');
      print('web socket trace: $stackTrace');
    }
  } else {
    await runRec();
  }
}

Future<void> runRec() async {
  //  find the target device
  String deviceName = 'Scarlett Solo USB';
  var bitDepthBytes = 4;

  if (verbose) print('deviceName: "$deviceName"');
  if (deviceName.isEmpty) {
    print('Error: hardware interface not found!');
    exit(1);
  }
  audioConfiguration = AudioConfiguration(bitDepthBytes);

  //  listen to the device audio
  List<String> arecordCommandArgs = [
    // rec -r 48000 -c 1 test.flac trim 0 10
    '-r',
    sampleRate.toString(),
    '-c',
    '$channels',
    '-L',
    '-b',
    '32',

    // '-t',
    // 'raw',
    'output.wav',
    'trim', '0', '10',
  ];
  var processName = 'rec';
  if (verbose) {
    print(
      '$processName ${arecordCommandArgs.toString().replaceAll(RegExp(r'[\[\]]'), '').replaceAll(RegExp(r', '), ' ')}',
    );
  }
  var process = await Process.start(processName, arecordCommandArgs);
  // stdout.addStream(process.stdout);
  // stderr.addStream(process.stderr);

  final StreamController<List<int>> streamController = StreamController();
  processTempo = ProcessTempo();
  processTempo.callback = processTempoCallback;
  processTempo.verbose = verbose;
  processTempo.veryVerbose = veryVerbose;
  streamController.stream.listen((data) {
    var bytes = Uint8List.fromList(data);
    var byteData = bytes.buffer.asByteData();
    print('heard ${data.length} bytes');
    for (
      int i = 0;
      i < data.length;
      i += bitDepthBytes * channels //  bytes per frame
    ) {
      //  add signals in case only one of the stereo channels is active
      int value = 0;
      for (var channel = 0; channel < channels; channel++) {
        value += byteData.getInt32(i + channel * bitDepthBytes, Endian.little);
      }

      print(value); //  way temp

      processTempo.processNewTempo(value);
    }
  }, cancelOnError: false);
  process.stdout.pipe(streamController);
}

processTempoCallback() {
  if (processTempo.bestBpm != _bpm || processTempo.tapsPerMeasure != _tpm) {
    _bpm = processTempo.bestBpm;
    _tpm = processTempo.tapsPerMeasure;
    if (_songTempoUpdate != null) {
      var songTempoUpdate = SongTempoUpdate(_songTempoUpdate!.songId, _bpm, processTempo.maxAmp);
      if (isWebsocketFeedback) {
        try {
          songUpdateService.issueSongTempoUpdate(songTempoUpdate);
        } catch (e) {
          print('tempo update caught: $e');
        }
      }
      print(
        '${DateTime.now()}: bestBpm: ${processTempo.bestBpm}'
        ' @ ${processTempo.instateMaxAmp}'
        ', tpm: ${processTempo.tapsPerMeasure}/${processTempo.beatsPerMeasure}'
      );
    }
  }
}

///
void webSocketCallback(final SongUpdate songUpdate) {
  if (verbose) {
    print(
      'webSocketCallback: $songUpdate, bpm: ${songUpdate.currentBeatsPerMinute}'
    );
  }
  processTempo.expectedBpm = songUpdate.currentBeatsPerMinute;
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
  'Scarlett Solo USB'
  r'\],\s+device\s+([0-9]+):',
); //

/*

rec:      SoX v

Usage summary: [gopts] [[fopts] infile]... [fopts] outfile [effect [effopt]]...

SPECIAL FILENAMES (infile, outfile):
-                        Pipe/redirect input/output (stdin/stdout); may need -t
-d, --default-device     Use the default audio device (where available)
-n, --null               Use the `null' file handler; e.g. with synth effect
-p, --sox-pipe           Alias for `-t sox -'

SPECIAL FILENAMES (infile only):
"|program [options] ..." Pipe input from external program (where supported)
http://server/file       Use the given URL as input file (where supported)

GLOBAL OPTIONS (gopts) (can be specified at any point before the first effect):
--buffer BYTES           Set the size of all processing buffers (default 8192)
--clobber                Don't prompt to overwrite output file (default)
--combine concatenate    Concatenate all input files (default for sox, rec)
--combine sequence       Sequence all input files (default for play)
-D, --no-dither          Don't dither automatically
--dft-min NUM            Minimum size (log2) for DFT processing (default 10)
--effects-file FILENAME  File containing effects and options
-G, --guard              Use temporary files to guard against clipping
-h, --help               Display version number and usage information
--help-effect NAME       Show usage of effect NAME, or NAME=all for all
--help-format NAME       Show info on format NAME, or NAME=all for all
--i, --info              Behave as soxi(1)
--input-buffer BYTES     Override the input buffer size (default: as --buffer)
--no-clobber             Prompt to overwrite output file
-m, --combine mix        Mix multiple input files (instead of concatenating)
--combine mix-power      Mix to equal power (instead of concatenating)
-M, --combine merge      Merge multiple input files (instead of concatenating)
--norm                   Guard (see --guard) & normalise
--play-rate-arg ARG      Default `rate' argument for auto-resample with `play'
--plot gnuplot|octave    Generate script to plot response of filter effect
-q, --no-show-progress   Run in quiet mode; opposite of -S
--replay-gain track|album|off  Default: off (sox, rec), track (play)
-R                       Use default random numbers (same on each run of SoX)
-S, --show-progress      Display progress while processing audio data
--single-threaded        Disable parallel effects channels processing
--temp DIRECTORY         Specify the directory to use for temporary files
-T, --combine multiply   Multiply samples of corresponding channels from all
                         input files (instead of concatenating)
--version                Display version number of SoX and exit
-V[LEVEL]                Increment or set verbosity level (default 2); levels:
                           1: failure messages
                           2: warnings
                           3: details of processing
                           4-6: increasing levels of debug messages
FORMAT OPTIONS (fopts):
Input file format options need only be supplied for files that are headerless.
Output files will have the same format as the input file where possible and not
overridden by any of various means including providing output format options.

-v|--volume FACTOR       Input file volume adjustment factor (real number)
--ignore-length          Ignore input file length given in header; read to EOF
-t|--type FILETYPE       File type of audio
-e|--encoding ENCODING   Set encoding (ENCODING may be one of signed-integer,
                         unsigned-integer, floating-point, mu-law, a-law,
                         ima-adpcm, ms-adpcm, gsm-full-rate)
-b|--bits BITS           Encoded sample size in bits
-N|--reverse-nibbles     Encoded nibble-order
-X|--reverse-bits        Encoded bit-order
--endian little|big|swap Encoded byte-order; swap means opposite to default
-L/-B/-x                 Short options for the above
-c|--channels CHANNELS   Number of channels of audio data; e.g. 2 = stereo
-r|--rate RATE           Sample rate of audio
-C|--compression FACTOR  Compression factor for output format
--add-comment TEXT       Append output file comment
--comment TEXT           Specify comment text for the output file
--comment-file FILENAME  File containing comment text for the output file
--no-glob                Don't `glob' wildcard match the following filename

AUDIO FILE FORMATS: 8svx aif aifc aiff aiffc al amb au avr caf cdda cdr cvs cvsd cvu dat dvms f32 f4 f64 f8 fap flac fssd gsm gsrt hcom htk ima ircam la lpc lpc10 lu mat mat4 mat5 maud mp2 mp3 nist ogg opus paf prc pvf raw s1 s16 s2 s24 s3 s32 s4 s8 sb sd2 sds sf sl sln smp snd sndfile sndr sndt sou sox sph sw txw u1 u16 u2 u24 u3 u32 u4 u8 ub ul uw vms voc vorbis vox w64 wav wavpcm wve xa xi
PLAYLIST FORMATS: m3u pls
AUDIO DEVICE DRIVERS: coreaudio

EFFECTS: allpass band bandpass bandreject bass bend biquad chorus channels compand contrast dcshift deemph delay dither divide+ downsample earwax echo echos equalizer fade fir firfit+ flanger gain highpass hilbert input# loudness lowpass mcompand noiseprof noisered norm oops output# overdrive pad phaser pitch rate remix repeat reverb reverse riaa silence sinc spectrogram speed splice stat stats stretch swap synth tempo treble tremolo trim upsample vad vol
  * Deprecated effect    + Experimental effect    # LibSoX-only effect
EFFECT OPTIONS (effopts): effect dependent; see --help-effect

 */
