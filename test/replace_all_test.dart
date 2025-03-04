import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

// const Level _logDetail = Level.debug;
// const Level _logSummary = Level.debug;

void main() {
  Logger.level = Level.info;

  test('test replace all', () {
    Logger.level = Level.info;
    logger.i('test replace all');

    var deviceName = 'hw:2,0';

    //  listen to the device audio
    List<String> arecordCommandArgs = [
      '-v',
      '-c$channels',
      '-r',
      sampleRate.toString(),
      '-f',
      'S16_LE',
      '-t',
      'raw',
      '-D',
      deviceName,
    ];
    print(
      'arecord ${arecordCommandArgs.toString()
          .replaceAll(RegExp(r'[\[\]]'), '')
          .replaceAll(RegExp(r', '), ' ')}',
    );
  });
}
