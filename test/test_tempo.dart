import 'dart:math';

import 'package:bsteele_music_tempo/app_logger.dart';
import 'package:bsteele_music_tempo/audio_configuration.dart';
import 'package:bsteele_music_tempo/bsteele_music_tempo.dart';
import 'package:bsteele_music_tempo/process_tempo.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const Level _logDetail = Level.debug;
const Level _logSummary = Level.debug;

testTempo(final int beatsPerMeasure) {
  double f = 180.0; //  tone pitch
  final ampMax = 1 << (audioConfiguration.bitDepth - 1);
  double toneFraction = 0.15;

  ProcessTempo processTempo = ProcessTempo();
  processTempo.callback = () {
    logger.log(_logDetail, 'callback: bpm: ${processTempo.bestBpm}, tpm: ${processTempo.tapsPerMeasure}');
  };

  int sample = 0;

  processTempo.beatsPerMeasure = beatsPerMeasure;
  processTempo.verbose = true;

  for (int currentBpm = 50; currentBpm <= 200; currentBpm += 5) {
    processTempo.expectedBpm = currentBpm; //  limit the range allowed

    for (int tapsPerMeasure in [1, beatsPerMeasure != 3 ? 2 : beatsPerMeasure, beatsPerMeasure]) {
      logger.i('');
      logger.i('currentBpm: $currentBpm, $processTempo, beatsPerMeasure: $beatsPerMeasure');

      bool lastInSignal = false;
      double periodS = 60 * beatsPerMeasure / (tapsPerMeasure * currentBpm);
      logger.i('currentBpm: $currentBpm, taps: $tapsPerMeasure => periodS $periodS = ${1 / periodS} hz');
      int sampleCycle = (sampleRate * periodS).toInt();
      int samplesOn = (sampleCycle * toneFraction).toInt();

      int sampleEnd = sample + 28 * periodS.ceil() * sampleRate;
      print('sampleEnd: $sampleEnd = ${sampleEnd / sampleRate} s, sample: $sample');
      for (; sample < sampleEnd; sample++) {
        int value = 0;
        var amp = (sample % sampleCycle < samplesOn) ? ampMax : 0;

        //  generate a pulse train every bpm
        value = (amp * sin(2 * pi * f * sample / sampleRate)).toInt();

        processTempo.processNewTempo(value, epochUs: sample * Duration.microsecondsPerSecond / sampleRate);
        logger.log(
          _logDetail,
          'sample: $sample: ${value.toStringAsFixed(2).padLeft(9)}'
          ' $processTempo',
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
      }
      expect(processTempo.bestBpm, currentBpm);
    }
  }
}
