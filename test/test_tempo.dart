import 'dart:collection';
import 'dart:math';

import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:bsteele_music_tempo/bsteele_music_tempo.dart';
import 'package:bsteele_music_tempo/process_tempo.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const Level _logDetail = Level.debug;
const Level _logSummary = Level.debug;
const Level _logCallback = Level.debug;


testTempo(final int beatsPerMeasure) {

  for (int tapsPerMeasure = 1; tapsPerMeasure <= beatsPerMeasure; tapsPerMeasure++) {
    final Queue<bool> pattern = Queue();
    int i = 0;
    for ( ; i < tapsPerMeasure; i++) {
      pattern.add(true);
    }
    for ( ; i < beatsPerMeasure; i++) {
      pattern.add(false);
    }
    logger.i(pattern.toString());
    testTempoPattern( beatsPerMeasure, pattern.toList());
  }

  //  alternate
  if ( beatsPerMeasure >= 3 ) {
    for (int tapsPerMeasure = 1; tapsPerMeasure <= beatsPerMeasure; tapsPerMeasure++) {
      final Queue<bool> pattern = Queue();
       for (int i = 0; i < beatsPerMeasure; i++) {
        pattern.add(false);
        i++;
        if ( i < beatsPerMeasure ) {
          pattern.add(true);
        }
      }
      logger.i(pattern.toString());
      testTempoPattern(beatsPerMeasure, pattern.toList());
    }
  }
}

testTempoPattern(final int beatsPerMeasure, final List<bool> tapPattern) {
  double f = 180.0; //  tone pitch
  final ampMax = 1 << (audioConfiguration.bitDepth - 1);
  double toneFraction = 0.15;

  ProcessTempo processTempo = ProcessTempo();
  processTempo.callback = () {
    logger.log(_logCallback, 'callback: bpm: ${processTempo.bestBpm}, tpm: ${processTempo.tapsPerMeasure}');
  };

  int sample = 0;

  processTempo.beatsPerMeasure = beatsPerMeasure;
  processTempo.verbose = true;

  logger.i('pattern: $tapPattern');
  assert(tapPattern.length % beatsPerMeasure == 0);

  for (int currentBpm = 55; currentBpm <= 200; currentBpm += 5) {
    processTempo.expectedBpm = currentBpm; //  limit the range allowed

    logger.i('');
    logger.i('currentBpm: $currentBpm, $processTempo, beatsPerMeasure: $beatsPerMeasure');

    bool lastInSignal = false;
    double periodS = 60 / currentBpm;
    logger.i('currentBpm: $currentBpm, taps: $tapPattern');
    int sampleCycle = (sampleRate * periodS).toInt();
    int samplesOn = (sampleCycle * toneFraction).toInt();
    int patternCount = 0;

    int testEnd = sample + 8 * tapPattern.length * periodS.ceil() * sampleRate;
    print('testEnd: testEnd = ${testEnd / sampleRate} s, sample: $sample');
    var lastWasZero = true;
    for (; sample < testEnd; sample++) {
      var amp = (sample % sampleCycle < samplesOn) ? ampMax : 0;

      //  generate a pulse train every requested pattern
      int value = 0;
      if (tapPattern[patternCount % tapPattern.length]) {
        value = (amp * sin(2 * pi * f * sample / sampleRate)).toInt();
      }
      if ((amp != 0) != lastWasZero) {
        logger.log(
            _logDetail,'amp: $amp @ $sample, value: $value, patternCount: $patternCount');
        lastWasZero = (amp != 0);
      }

      processTempo.processNewTempo(value, epochUs: sample * Duration.microsecondsPerSecond / sampleRate);
      logger.log(
        _logDetail,
        'sample: $sample: ${value.toStringAsFixed(2).padLeft(9)}',
        // ' $processTempo',
      );

      if (lastInSignal != processTempo.isSignal) {
        lastInSignal = processTempo.isSignal;
        logger.log(
          _logSummary,
          'sample ${sample.toString().padLeft(9)} = ${(sample / sampleRate).toStringAsFixed(3)}s:'
          ' ${value.toStringAsFixed(2).padLeft(8)}'
          ' $processTempo',
        );
      }

      if (sample % sampleCycle == sampleCycle - 1) {
        patternCount++;
      }
    }
    expect(processTempo.bestBpm, currentBpm);
  }
}
