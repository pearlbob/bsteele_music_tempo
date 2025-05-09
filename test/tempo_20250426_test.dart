import 'dart:io';

import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

var fileName = '20250426.log';

DateTime? _lastBpmDateTime;

void main() {
  Logger.level = Level.info;

  test('test $fileName', () {
    Logger.level = Level.info;
    logger.i('test $fileName');

    // var dir = Directory('test/assets');
    // logger.i('dir: ${dir.absolute} ');

    var file = File('./test/assets/$fileName');
    logger.i('file: ${file.absolute} ');
    logger.i('');

    for (var line in file.readAsLinesSync()) {
      // logger.i('line: "$line"');
      Match? m = webSocketCallbackRegex.firstMatch(line);
      if (m != null) {
        logger.i('webSocketCallback: $line');
        continue;
      }
      m = songTempoUpdateRegex.firstMatch(line);
      if (m != null) {
        logger.i('songTempoUpdate:');
        logger.i('    songId: "${m.group(1)}"');
        logger.i('    currentBPM: ${m.group(2)}');
        logger.i('    user: ${m.group(3)}');
        logger.i('    level: ${m.group(4)}');
        continue;
      }
      m = stalledRegex.firstMatch(line);
      if (m != null) {
        //  ignore
        // logger.i('stalled: $line');
        continue;
      }
      m = bpmRegex.firstMatch(line);
      if (m != null) {
        logger.i('bpm: $line');
        var dateTime = DateTime.parse(m.group(1)!);
        logger.i('     dateTime: $dateTime');

        double level = double.parse(m.group(2)!);
        logger.i('     level: $level');
        double durationS = double.parse(m.group(3)!);
        logger.i('     durationS: $durationS');
        int tpm = int.parse(m.group(4)!);
        logger.i('     tpm: $tpm');
        double f = double.parse(m.group(5)!);
        logger.i('     f: $f hz');
        double bpm = double.parse(m.group(6)!);
        logger.i('     bpm: $bpm');

        _processBpm(dateTime);
        continue;
      }
      m = bestBpmRegex.firstMatch(line);
      if (m != null) {
        logger.i('bestBpm: $line');
        var dateTime = DateTime.parse(m.group(1)!);
        logger.i('     dateTime: $dateTime');
        int bestBpm = int.parse(m.group(2)!);
        logger.i('     bestBpm: $bestBpm');
        double level = double.parse(m.group(3)!);
        logger.i('     level: $level');
        int tapsPerMeasure = int.parse(m.group(4)!);
        logger.i('     tapsPerMeasure: $tapsPerMeasure');
        int beatsPerMeasure = int.parse(m.group(4)!);
        logger.i('     beatsPerMeasure: $beatsPerMeasure');
        continue;
      }

      logger.i('NOT FOUND: "$line"');
    }
  });
}

_processBpm(DateTime dateTime){
  if ( _lastBpmDateTime != null ) {
    logger.i('duration: ${dateTime.difference(_lastBpmDateTime!)}');
  }
  _lastBpmDateTime = dateTime;
    
}

//  webSocketCallback: SongUpdate: "What's Up" by "4 Non Blondes" : , moment: 0, beat: 0, measure: A, repeat: 1/2, key: C,
final RegExp webSocketCallbackRegex = RegExp(r'^webSocketCallback: ');

//  SongTempoUpdate: "Song_Across_The_Universe_by_Beatles_The", currentBPM: 73, user: tempo, level: 0.034
final RegExp songTempoUpdateRegex = RegExp(
  r'^SongTempoUpdate: "(.*)", *currentBPM: *(\d+), user: *(\w+), *level: (\d+\.\d+)$',
);

final dT = r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6})';

//  2025-04-26 13:15:06.138026: 288001: stalled @0.000 <= 0.000, from 0.045 < 1.0
final RegExp stalledRegex = RegExp(dT + r'.* stalled ');

//  2025-04-26 13:26:34.424863: @    1.000,    1.709 s / 2 =    1.170 hz =   70.227 bpm
final RegExp bpmRegex = RegExp(dT + r': +@ +(\d\.\d+), +(\d\.\d+) +s +/ +(\d) += +(\d\.\d+) +hz += +(\d+\.\d+) +bpm$');

//  2025-04-26 13:26:32.675041: bestBpm: 73 @ 1.000, tpm: 0/4
final RegExp bestBpmRegex = RegExp(dT + r': +bestBpm: +(\d+) +@ +(\d\.\d+), +tpm: (\d)/(\d)$');
