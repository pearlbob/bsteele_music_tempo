import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import 'test_tempo.dart';

void main() {
  Logger.level = Level.info;

  test('test 4 beatsPerMeasure', () {
    Logger.level = Level.info;
    logger.i('test 4 beatsPerMeasure');
    testTempo(4);
  });
}
